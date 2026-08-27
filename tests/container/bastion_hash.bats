#!/usr/bin/env bats
#
# The bastion refuses to start when its provisioned configuration changed.
#
# `sshd_config` opens with `Include /etc/ssh/sshd_config.d/*.conf`, so anything
# in that directory is part of the running configuration - it can turn on
# PermitRootLogin or widen AllowTcpForwarding. Until 2026-08-27 the provisioning
# checksum covered `sshd_config` and the host keys but nothing in that
# directory, so a drop-in could be added, edited or removed and the container
# still reported a valid checksum and started. Verified against the unfixed
# image: all three cases started normally.
#
# Hashing the files catches an edit. It cannot catch an addition or a removal -
# every recorded line still checks out - which is why the sorted listing is
# recorded as a file of its own and compared before sshd starts.
#
# No credentials and no network: the container only ever fails or runs sshd.

IMAGE="${BASTION_IMAGE:-ghcr.io/dennisdeh/bastion:latest}"
# A constant name: bats re-sources this file in a new process per test.
CNAME="bastion-hash-bats"

setup_file() {
	if ! docker image inspect "$IMAGE" >/dev/null 2>&1; then
		skip "image $IMAGE not present - build it or set BASTION_IMAGE"
	fi
	DATA="${BATS_FILE_TMPDIR}/data"
	mkdir -p "$DATA"
	export DATA
	provision
}

teardown_file() {
	docker rm -f "$CNAME" >/dev/null 2>&1 || true
	# provision.sh chowns data/ to root, so remove it from a container.
	if [ -n "${DATA:-}" ]; then
		docker run --rm -v "${BATS_FILE_TMPDIR}:/t" "$IMAGE" \
			rm -rf /t/data >/dev/null 2>&1 || true
	fi
}

provision() {
	docker run --rm \
		-e USERS=probe -e USER_SHELL=/usr/sbin/nologin \
		-e TOTP_ENABLED=no -e CA_ENABLED=no -e BANNER_ENABLED=no \
		-v "${DATA}:/data" "$IMAGE" /provision.sh >/dev/null 2>&1
}

# Start the bastion the way compose does and say whether sshd came up or the
# entrypoint refused. A container that exits is the refusal.
starts() {
	docker rm -f "$CNAME" >/dev/null 2>&1 || true
	docker run -d --name "$CNAME" \
		-e USERS=probe -e TOTP_ENABLED=no -e CA_ENABLED=no -e BANNER_ENABLED=no \
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

# Mutate data/ as root, since provision.sh owns it.
in_data() {
	docker run --rm -v "${DATA}:/data" "$IMAGE" bash -c "$1" >/dev/null 2>&1
}

drop_in() { echo "${DATA}/etc/ssh/sshd_config.d"; }

@test "bastion: a freshly provisioned data dir starts" {
	[ "$(starts)" = 'started' ]
}

@test "bastion: a drop-in added after provisioning stops it" {
	# The case no per-file hash can see: every recorded line still checks out.
	in_data 'echo "AllowTcpForwarding yes" > /data/etc/ssh/sshd_config.d/99-rogue.conf'
	run starts
	[ "$output" = 'refused' ]

	in_data 'rm -f /data/etc/ssh/sshd_config.d/99-rogue.conf'
	run starts
	[ "$output" = 'started' ]
}

@test "bastion: a drop-in edited after provisioning stops it" {
	in_data 'echo "# baseline" > /data/etc/ssh/sshd_config.d/50-base.conf'
	provision
	run starts
	[ "$output" = 'started' ]

	in_data 'echo "PermitRootLogin yes" >> /data/etc/ssh/sshd_config.d/50-base.conf'
	run starts
	[ "$output" = 'refused' ]

	in_data 'echo "# baseline" > /data/etc/ssh/sshd_config.d/50-base.conf'
	run starts
	[ "$output" = 'started' ]
}

@test "bastion: a drop-in removed after provisioning stops it" {
	in_data 'rm -f /data/etc/ssh/sshd_config.d/50-base.conf'
	run starts
	[ "$output" = 'refused' ]
	provision
	run starts
	[ "$output" = 'started' ]
}

@test "bastion: data provisioned before drop-ins were covered is refused" {
	# Upgrading the image without re-provisioning must fail loudly rather than
	# silently skip the new check.
	in_data 'rm -f /data/etc/ssh/sshd_config.d.list'
	in_data "sed -i '/sshd_config.d.list/d' /data/etc/ssh/bastion_provisioned_hash"
	run starts
	[ "$output" = 'refused' ]

	provision
	run starts
	[ "$output" = 'started' ]
}
