#!/usr/bin/env bats
#
# deploy/provision.sh - the decisions that are wrong silently.
#
# Two of these exist because the code shipped here was wrong when first written
# and a live sshd said so:
#
#   * `permitopen` governs -L only and `permitlisten` governs -R only. A key
#     naming one of them leaves the other direction unrestricted, so both the
#     gateway key and the client keys could forward in the direction they had
#     no business using. Measured against a real bastion, not reasoned about.
#   * a secret "left empty" is written as a bare newline, which `-s` calls
#     populated while `file_env` reads it back as the empty string - so the
#     gateway would start with a blank IB password and provisioning would say
#     it had succeeded.

setup() {
	ROOT="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"
	PROVISION="${ROOT}/deploy/provision.sh"
}

# Call one of the script's functions without running main(). Sourcing under a
# different $0 is what keeps main() from firing.
prov() {
	bash -c 'source "$1" >/dev/null 2>&1 || true; shift; "$@"' _ "$PROVISION" "$@"
}

@test "provision: the script is executable and parses" {
	[ -x "$PROVISION" ]
	run bash -n "$PROVISION"
	[ "$status" -eq 0 ]
}

@test "provision: the API port follows the trading mode" {
	# set_ports() in common.sh binds these; the tunnel opens the same number.
	run prov api_port_for paper
	[ "$output" = "4002" ]
	run prov api_port_for live
	[ "$output" = "4001" ]
	# TRADING_MODE=both runs two IBC instances and tunnels the paper port.
	run prov api_port_for both
	[ "$output" = "4002" ]
	run prov api_port_for nonsense
	[ "$status" -ne 0 ]
}

@test "provision: the gateway key may listen on the API port and nothing else" {
	run prov gateway_authorized_key 'ssh-ed25519 AAAAKEY comment' 4002
	[ "$status" -eq 0 ]
	[[ $output == restrict,* ]]
	[[ $output == *'permitlisten="127.0.0.1:4002"'* ]]
	[[ $output == *'permitlisten="localhost:4002"'* ]]
	[[ $output == *'ssh-ed25519 AAAAKEY comment'* ]]
}

@test "provision: the gateway key may not open a local forward" {
	# It needs -R only. `permitlisten` does not restrict -L, and the blanket
	# `port-forwarding` that re-enables -R re-enables -L with it, so without an
	# explicit permitopen this key could reach anything the bastion can.
	run prov gateway_authorized_key 'ssh-ed25519 AAAAKEY comment' 4002
	[[ $output == *'permitopen='* ]]
	[[ $output != *'permitopen="127.0.0.1:4002"'* ]]
	# Pinned to a privileged port the unprivileged session user cannot use.
	[[ $output == *'permitopen="127.0.0.1:1"'* ]]
}

@test "provision: a client key may open the API port and nothing else" {
	run prov client_authorized_key 'ssh-ed25519 CLIENTKEY probe' 4002
	[ "$status" -eq 0 ]
	[[ $output == restrict,* ]]
	[[ $output == *'permitopen="127.0.0.1:4002"'* ]]
	[[ $output == *'permitopen="localhost:4002"'* ]]
	[[ $output == *'ssh-ed25519 CLIENTKEY probe'* ]]
}

@test "provision: a client key may not bind a listener on the bastion" {
	# Without permitlisten a client could bind the API port itself whenever the
	# gateway is not holding it, and serve a counterfeit API to the others.
	run prov client_authorized_key 'ssh-ed25519 CLIENTKEY probe' 4002
	[[ $output == *'permitlisten='* ]]
	[[ $output != *'permitlisten="127.0.0.1:4002"'* ]]
	[[ $output == *'permitlisten="127.0.0.1:1"'* ]]
}

@test "provision: neither key grants a shell, an agent or X11" {
	local line
	for line in "$(prov gateway_authorized_key 'ssh-ed25519 K c' 4002)" \
		"$(prov client_authorized_key 'ssh-ed25519 K c' 4002)"; do
		# `restrict` is all of no-pty, no-agent-forwarding, no-X11-forwarding,
		# no-user-rc and no-port-forwarding; only forwarding is added back.
		[[ $line == restrict,port-forwarding,* ]]
		[[ $line != *no-restrict* ]]
	done
}

@test "provision: known_hosts brackets a non-default port" {
	run prov known_hosts_entry bastion 22 'ssh-ed25519 AAAAHOST'
	[ "$output" = "bastion ssh-ed25519 AAAAHOST" ]

	# ssh writes and looks up a non-22 port as [host]:port; an unbracketed
	# entry silently fails to match and the connection prompts instead.
	run prov known_hosts_entry bastion 22222 'ssh-ed25519 AAAAHOST'
	[ "$output" = "[bastion]:22222 ssh-ed25519 AAAAHOST" ]
}

@test "provision: an empty secret is recognised as empty" {
	local f="${BATS_TEST_TMPDIR}/secret"

	# missing
	run prov blank_file "$f"
	[ "$status" -eq 0 ]

	# what `printf '%s\n' ''` leaves behind: one byte, which `-s` calls
	# populated, and which file_env reads back as the empty string
	printf '\n' >"$f"
	run prov blank_file "$f"
	[ "$status" -eq 0 ]

	printf '   \n\t\n' >"$f"
	run prov blank_file "$f"
	[ "$status" -eq 0 ]

	printf 'hunter2\n' >"$f"
	run prov blank_file "$f"
	[ "$status" -ne 0 ]
}

@test "provision: names that become unix users are validated" {
	local ok bad
	for ok in ibgateway jupyter client-1 a_b; do
		run prov valid_name "$ok"
		[ "$status" -eq 0 ]
	done
	# A name reaches adduser, a directory path and an ssh config stanza.
	for bad in '' 'Jupyter' '1client' '../etc' 'a b' 'a;rm' '-flag' "$(printf 'x%.0s' {1..40})"; do
		run prov valid_name "$bad"
		[ "$status" -ne 0 ]
	done
}

@test "provision: the live deployment's project name is refused" {
	# docker compose identifies a project by name, not by directory: emitting a
	# stack called inv_ibkr would make `up -d` adopt the running containers.
	run grep -c "RESERVED_PROJECT='inv_ibkr'" "$PROVISION"
	[ "$output" = "1" ]
	run grep -q 'RESERVED_CONTAINERS=.*inv_gateway inv_bastion' "$PROVISION"
	[ "$status" -eq 0 ]
}

@test "provision: nothing it emits publishes the IB API port" {
	# The API has no authentication of its own. Reaching it must require a key,
	# not a route: only the bastion's ssh port is ever published.
	run grep -qF 'BASTION_PORT}:22"' "$PROVISION"
	[ "$status" -eq 0 ]
	# No compose `ports:` entry anywhere names an API or socat port.
	run grep -nE '(4001|4002|4003|4004|7496|7497|7498|7499):[0-9]+"' "$PROVISION"
	[ "$status" -ne 0 ]
}

@test "provision: the emitted compose pulls, never builds" {
	# The whole point of the future setup: no build context, and no \$PWD, so
	# the file works from any directory.
	run grep -nE '^\s+build:' "$PROVISION"
	[ "$status" -ne 0 ]
	run grep -q 'IB_GATEWAY_IMAGE=ghcr.io/dennisdeh/ib-gateway' "$PROVISION"
	[ "$status" -eq 0 ]
}

@test "provision: credentials reach the containers as files, not values" {
	# file_env errors out when both VAR and VAR_FILE are set, so the emitted
	# compose must name only the _FILE half.
	run grep -cE '^\s+(TWS_PASSWORD|VNC_SERVER_PASSWORD|SSH_PASSPHRASE|PASSWD)_FILE: /run/secrets/' "$PROVISION"
	[ "$output" -ge 4 ]
	run grep -nE '^\s+TWS_PASSWORD: ' "$PROVISION"
	[ "$status" -ne 0 ]
	run grep -nE '^\s+VNC_SERVER_PASSWORD: ' "$PROVISION"
	[ "$status" -ne 0 ]
}
