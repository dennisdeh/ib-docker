#!/usr/bin/env bats
#
# `CA_ENABLED=yes` must mean something, or refuse to start.
#
# Until 2026-08-28 `set_CA()` resolved both paths by falling back to a default
# whenever the named file was missing - silently - and never checked the
# default either. So `CA_ENABLED=yes` against a `data/` with no certificate in
# it logged "SSH CA enabled", started sshd, and trusted nothing: OpenSSH only
# warns about an absent HostCertificate and says nothing at all about an absent
# TrustedUserCAKeys, so `sshd -t` exits 0 in that state. Nothing failed and
# nothing was in force. See docs/OPEN_ITEMS.md #26.
#
# The two halves are independent - a host certificate frees clients from
# known_hosts, a user CA frees this host from authorized_keys - so either alone
# is a valid setup and must still start. That is the false positive these tests
# exist to rule out, and it is the last test here.
#
# No credentials and no network: the container only ever fails or runs sshd.

IMAGE="${BASTION_IMAGE:-ghcr.io/dennisdeh/bastion:latest}"
# A constant name: bats re-sources this file in a new process per test.
CNAME="bastion-ca-bats"

setup_file() {
	if ! docker image inspect "$IMAGE" >/dev/null 2>&1; then
		skip "image $IMAGE not present - build it or set BASTION_IMAGE"
	fi
	DATA="${BATS_FILE_TMPDIR}/data"
	mkdir -p "$DATA"
	export DATA
	docker run --rm \
		-e USERS=probe -e USER_SHELL=/usr/sbin/nologin \
		-e TOTP_ENABLED=no -e CA_ENABLED=no -e BANNER_ENABLED=no \
		-v "${DATA}:/data" "$IMAGE" /provision.sh >/dev/null 2>&1
}

teardown_file() {
	docker rm -f "$CNAME" >/dev/null 2>&1 || true
	if [ -n "${DATA:-}" ]; then
		docker run --rm -v "${BATS_FILE_TMPDIR}:/t" "$IMAGE" \
			rm -rf /t/data >/dev/null 2>&1 || true
	fi
}

# Start with the given CA environment; report whether sshd came up. A container
# that exits is the refusal. Its log is left in $output_log for assertions.
starts_with() {
	local ca_enabled="$1" host_cert="${2:-}" user_ca="${3:-}"
	docker rm -f "$CNAME" >/dev/null 2>&1 || true
	docker run -d --name "$CNAME" \
		-e USERS=probe -e TOTP_ENABLED=no -e BANNER_ENABLED=no \
		-e "CA_ENABLED=${ca_enabled}" \
		-e "SSHD_HOST_CERT=${host_cert}" \
		-e "SSHD_USER_CA=${user_ca}" \
		-v "${DATA}/etc/passwd:/etc/passwd:ro" \
		-v "${DATA}/etc/shadow:/etc/shadow:ro" \
		-v "${DATA}/etc/group:/etc/group:ro" \
		-v "${DATA}/etc/ssh:/etc/ssh:ro" \
		-v "${DATA}/home:/home:ro" \
		"$IMAGE" >/dev/null 2>&1
	sleep 3
	if [ "$(docker inspect -f '{{.State.Running}}' "$CNAME" 2>/dev/null)" = 'true' ]; then
		echo started
	else
		echo refused
	fi
}

logs() { docker logs "$CNAME" 2>&1; }

# Put a file into the provisioned data as root - provision.sh owns it.
in_data() {
	docker run --rm -v "${DATA}:/data" "$IMAGE" bash -c "$1" >/dev/null 2>&1
}

@test "bastion CA: CA off starts, and says so" {
	run starts_with no
	[ "$output" = 'started' ]
	run logs
	[[ $output == *"SSH CA"*"disabled"* ]]
}

@test "bastion CA: CA on with no certificate at all is refused" {
	# The defect: this used to start and report success.
	run starts_with yes
	[ "$output" = 'refused' ]
	run logs
	[[ $output == *"neither a host certificate nor a user"* ]]
	[[ $output == *"Refusing to start"* ]]
}

@test "bastion CA: a path that does not exist is named, not silently replaced" {
	# The old code substituted the default here without a word, so a typo in
	# SSHD_HOST_CERT looked like it had worked.
	run starts_with yes /etc/ssh/typo-cert.pub
	[ "$output" = 'refused' ]
	run logs
	[[ $output == *"SSHD_HOST_CERT='/etc/ssh/typo-cert.pub' does not exist"* ]]
}

@test "bastion CA: a missing user CA path is named too" {
	run starts_with yes '' /etc/ssh/typo-ca.pub
	[ "$output" = 'refused' ]
	run logs
	[[ $output == *"SSHD_USER_CA='/etc/ssh/typo-ca.pub' does not exist"* ]]
}

@test "bastion CA: a user CA alone is a valid setup and still starts" {
	# The false positive to rule out. Only one half is configured, so the guard
	# must warn about the other and carry on - and the option has to reach sshd.
	in_data 'ssh-keygen -q -t ed25519 -N "" -f /tmp/uca </dev/null &&
	         cp /tmp/uca.pub /data/etc/ssh/user_ca.pub &&
	         chown root:root /data/etc/ssh/user_ca.pub &&
	         chmod 644 /data/etc/ssh/user_ca.pub'

	run starts_with yes
	[ "$output" = 'started' ]
	run logs
	[[ $output == *"TrustedUserCAKeys=/etc/ssh/user_ca.pub"* ]]
	[[ $output == *"no host certificate"* ]]
	[[ $output == *"SSH CA"*"enabled"* ]]

	in_data 'rm -f /data/etc/ssh/user_ca.pub'
}
