#!/usr/bin/env bats
# shellcheck disable=SC2016  # ${IB_APP} and ${VAR} are matched literally here
#
# docker-compose.yml - the profile wiring that decides which image runs.
#
# One file carries both applications, so a broken profile no longer means "the
# wrong service is missing" but "compose silently starts nothing", or worse,
# starts both against the same host ports. None of this needs docker: the
# assertions are the file's contract with .env-dist.

setup() {
	ROOT="${BATS_TEST_DIRNAME}/../.."
	COMPOSE="${ROOT}/docker-compose.yml"
	ENV_DIST="${ROOT}/.env-dist"
}

# Everything indented under `  <name>:` in the services map. Comment lines in
# this file are indented two spaces, so they must not be read as the next
# service - that is what the `#` exclusion below is for.
service_block() {
	awk -v svc="$1" '
		/^services:/           { in_services = 1; next }
		in_services && /^[^[:space:]#]/ { in_services = 0 }
		in_services && $0 ~ "^  " svc ":[[:space:]]*$" { in_svc = 1; next }
		in_svc && /^  [^[:space:]#]/ { in_svc = 0 }
		in_svc                 { print }
	' "$COMPOSE"
}

service_names() {
	awk '
		/^services:/ { in_services = 1; next }
		in_services && /^[^[:space:]#]/ { in_services = 0 }
		in_services && /^  [a-z][a-z0-9_-]*:[[:space:]]*$/ {
			gsub(/[[:space:]:]/, ""); print
		}
	' "$COMPOSE"
}

# The ${VAR} names a service publishes ports through.
port_vars() {
	service_block "$1" | awk '
		/^    ports:/            { in_ports = 1; next }
		in_ports && /^    [^[:space:]-]/ { in_ports = 0 }
		in_ports                 { print }
	' | grep -o '\${[A-Z_]*' | tr -d '${' | sort -u
}

@test "compose: one file defines ib-gateway, tws and bastion" {
	run service_names
	[ "$status" -eq 0 ]
	[ "$(echo "$output" | sort | tr '\n' ' ')" = "bastion ib-gateway tws " ]
}

@test "compose: ib-gateway sits behind the ib-gateway profile" {
	run service_block ib-gateway
	[[ $output == *"profiles:"* ]]
	[[ $output == *"- ib-gateway"* ]]
}

@test "compose: tws sits behind the tws profile" {
	run service_block tws
	[[ $output == *"profiles:"* ]]
	[[ $output == *"- tws"* ]]
}

@test "compose: bastion declares no profile, so it always starts" {
	run service_block bastion
	[[ $output != *"profiles:"* ]]
}

@test ".env-dist: IB_APP feeds COMPOSE_PROFILES" {
	# IB_APP is the name a human edits; COMPOSE_PROFILES is the only name
	# compose reads. Dropping the second line makes IB_APP inert.
	run grep -qx 'IB_APP=ib-gateway' "$ENV_DIST"
	[ "$status" -eq 0 ]
	run grep -qx 'COMPOSE_PROFILES=${IB_APP}' "$ENV_DIST"
	[ "$status" -eq 0 ]
}

@test "compose: ib-gateway and tws publish through disjoint port variables" {
	# IB_APP=ib-gateway,tws is supported, so a shared variable would be a
	# host port collision that only shows up when both are selected.
	local shared
	shared=$(comm -12 <(port_vars ib-gateway) <(port_vars tws))
	[ -z "$shared" ]
}

@test ".env-dist: defines every port variable the compose file substitutes" {
	local var
	for var in $(port_vars ib-gateway) $(port_vars tws); do
		run grep -q "^${var}=" "$ENV_DIST"
		[ "$status" -eq 0 ] || {
			echo "missing from .env-dist: $var"
			return 1
		}
	done
}

@test "env: every key in .env-dist is read by something" {
	# PORT_HOST_SSH_BASTION=2222 sat here for months naming a port nothing
	# published - the bastion publishes SSH_LISTEN_PORT - so a firewall rule
	# written against it protected nothing. A key here is a promise that
	# setting it does something. See docs/OPEN_ITEMS.md #15.
	local key dead=''
	while read -r key; do
		grep -rq "$key" \
			"${ROOT}/docker-compose.yml" \
			"${ROOT}/bastion/docker-compose.yml" \
			"${ROOT}/deploy/provision.sh" \
			"${ROOT}/image-files" \
			"${ROOT}/.github/workflows" 2>/dev/null || dead="${dead} ${key}"
	done < <(grep -oE '^[A-Z_][A-Z0-9_]*=' "$ENV_DIST" | tr -d '=')

	[ -z "$dead" ] || {
		echo "these keys in .env-dist are read by nothing:${dead}"
		echo "wire them up, or delete them - a key that does nothing is worse"
		echo "than no key, because it reads as configuration that works."
		return 1
	}
}

@test "compose: no bind mount depends on the caller's working directory" {
	# ${PWD} in a compose file interpolates from the *shell*, not from .env -
	# a shell always exports PWD, and compose gives the environment precedence
	# over the .env file, so the `PWD=~` that sat in .env could never take
	# effect. Mounts therefore followed the current directory rather than the
	# project: `docker compose -f <repo>/docker-compose.yml config` run from
	# /tmp resolved the bastion's read-only /etc/passwd, /etc/shadow and
	# /etc/ssh mounts to /tmp/data/... and validated happily. Measured
	# 2026-08-30; see docs/OPEN_ITEMS.md #14.
	#
	# A relative path has no such failure mode: compose resolves it against the
	# project directory, which is the compose file's own directory unless
	# --project-directory says otherwise.
	local f hits=''
	for f in "${ROOT}/docker-compose.yml" "${ROOT}/bastion/docker-compose.yml"; do
		hits="${hits}$(grep -n 'PWD' "$f" | sed "s|^|  ${f#"${ROOT}/"}:|" || true)"
	done
	[ -z "$hits" ] || {
		echo "these mounts follow the caller's cwd; use ./ so they follow the project:"
		echo "$hits"
		return 1
	}
}
