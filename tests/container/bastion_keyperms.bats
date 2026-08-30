#!/usr/bin/env bats
#
# Provisioning must not leave a private key world-readable.
#
# `set_sshd_config()` used to `chmod 644` every file in `data/etc/ssh` and then
# restore `600` for the `ssh_host*key` glob alone. Any other private key an
# operator put there kept 0644 - a user CA copied in as `user_ca` is the case
# that matters, because `CA_ENABLED=yes` is a documented feature and
# `bastion/README.md` tells you to place the file exactly there. Reproduced
# against the published image on 2026-08-30: `user_ca` came out `-rw-r--r--`.
# The host keys were also 644 between the two commands.
#
# The fix inverts the default - everything goes to 600, then a named list of
# genuinely public files is opened to 644 - so a key added in future is private
# without anyone having to remember to add it to a glob.
# See docs/OPEN_ITEMS.md #37.
#
# `set_checksum()` hashes these files, so the modes have to be settled before
# the digest is taken; this runs the real /provision.sh end to end rather than
# reimplementing it. No credentials, no network.

IMAGE="${BASTION_IMAGE:-ghcr.io/dennisdeh/bastion:latest}"

setup_file() {
	if ! docker image inspect "$IMAGE" >/dev/null 2>&1; then
		skip "image $IMAGE not present - build it or set BASTION_IMAGE"
	fi
	DATA="${BATS_FILE_TMPDIR}/data"
	mkdir -p "$DATA"
	export DATA
	# A user CA private key, placed the way bastion/README.md documents, before
	# provisioning runs - this is the file the old glob missed. The directory is
	# created inside the container: `$DATA` is a path in the bats runner, and the
	# daemon auto-creates the *host* side of the bind mount empty, so a mkdir
	# here would not be visible over there.
	docker run --rm --network none -v "${DATA}:/data" \
		--entrypoint /bin/bash "$IMAGE" -c \
		'mkdir -p /data/etc/ssh && ssh-keygen -q -t ed25519 -N "" -C user-ca -f /data/etc/ssh/user_ca' \
		>/dev/null 2>&1
	docker run --rm --network none \
		-e USERS=probe -e USER_SHELL=/usr/sbin/nologin \
		-e TOTP_ENABLED=no -e CA_ENABLED=no -e BANNER_ENABLED=no \
		-v "${DATA}:/data" "$IMAGE" /provision.sh >/dev/null 2>&1
}

teardown_file() {
	if [ -n "${DATA:-}" ]; then
		docker run --rm --network none -v "${BATS_FILE_TMPDIR}:/t" \
			--entrypoint /bin/bash "$IMAGE" -c 'rm -rf /t/data' \
			>/dev/null 2>&1 || true
	fi
}

# Mode of a provisioned file, read inside a container so the host's own
# ownership does not come into it.
mode_of() {
	docker run --rm --network none -v "${DATA}:/data" \
		--entrypoint /bin/bash "$IMAGE" -c "stat -c '%a' '/data/etc/ssh/$1' 2>/dev/null"
}

@test "keyperms: a user CA private key is not world-readable" {
	run mode_of user_ca
	[ "$status" -eq 0 ]
	[ "$output" = '600' ] || {
		echo "user_ca is mode ${output}, expected 600."
		echo "A private key matching no ssh_host*key glob used to keep 0644."
		return 1
	}
}

@test "keyperms: host private keys are not world-readable" {
	local key
	for key in ssh_host_ed25519_key ssh_host_rsa_key; do
		run mode_of "$key"
		[ "$status" -eq 0 ]
		[ "$output" = '600' ] || {
			echo "${key} is mode ${output}, expected 600"
			return 1
		}
	done
}

@test "keyperms: public material stays readable" {
	# sshd reads these as root, but they are not secret and the checksum list
	# names them; 644 is what they had before and must keep.
	local pub
	for pub in ssh_host_ed25519_key.pub user_ca.pub sshd_config; do
		run mode_of "$pub"
		[ "$status" -eq 0 ]
		[ "$output" = '644' ] || {
			echo "${pub} is mode ${output}, expected 644"
			return 1
		}
	done
}

@test "keyperms: no private key anywhere in data/etc/ssh is group- or world-readable" {
	# The general form of the rule, so a key added later is covered without a
	# test naming it. The header is assembled at runtime: spelled out, it would
	# trip the `detect-private-key` pre-commit hook on this file's own source.
	run docker run --rm --network none -v "${DATA}:/data" \
		--entrypoint /bin/bash "$IMAGE" -c '
			hdr="BEGIN OPENSSH PRIVATE"
			bad=0
			for f in /data/etc/ssh/*; do
				[ -f "$f" ] || continue
				head -c 40 "$f" 2>/dev/null | grep -q "${hdr} KEY" || continue
				mode="$(stat -c "%a" "$f")"
				case "$mode" in
					600|400) ;;
					*) echo "$f $mode"; bad=1 ;;
				esac
			done
			exit $bad'
	[ "$status" -eq 0 ] || {
		echo "these private keys are readable beyond their owner:"
		echo "$output"
		return 1
	}
}
