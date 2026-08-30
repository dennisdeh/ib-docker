#!/usr/bin/env bats
#
# The TWS image's desktop user must not be able to become root.
#
# `abc` is the account the whole XFCE desktop, xrdp and TWS run as, and its
# password is the string `abc` unless PASSWD is set. The linuxserver base ships
# `%sudo ALL=(ALL:ALL) NOPASSWD: ALL` and used to put `abc` in gid 27, so both
# `sudo -n id` and `echo abc | sudo -S id` returned uid 0 - proven by execution
# on the published image, 2026-08-30. See docs/OPEN_ITEMS.md #43.
#
# This has to be a container test. tests/unit/dockerfile.bats' "no image grants
# its unprivileged user passwordless root" greps *source* Dockerfiles, and the
# grant is two layers down in a base nobody here writes; that test was
# mutation-checked and is simply blind to inheritance.
#
# No credentials, no IB contact, no s6 supervision tree: every check runs a
# throwaway container with the entrypoint overridden, so TWS never starts.

IMAGE="${TWS_IMAGE:-ghcr.io/dennisdeh/tws-rdesktop:latest}"

setup() {
	if ! docker image inspect "$IMAGE" >/dev/null 2>&1; then
		skip "image $IMAGE not present - build it or set TWS_IMAGE"
	fi
}

# One throwaway container, entrypoint overridden, running one script as root.
in_image() {
	docker run --rm --entrypoint bash "$IMAGE" -c "$1" 2>&1
}

@test "tws: abc is not in a group that sudoers grants root to" {
	run in_image 'id -nG abc'
	[ "$status" -eq 0 ]
	[[ $output != *sudo* ]] || {
		echo "abc is still in the sudo group, which /etc/sudoers grants NOPASSWD root:"
		echo "  $output"
		return 1
	}
}

@test "tws: abc cannot become root without a password" {
	run in_image 'su -s /bin/bash abc -c "sudo -n id"'
	[[ $output != *"uid=0"* ]] || {
		echo "abc escalated to root with no password: $output"
		return 1
	}
}

@test "tws: abc cannot become root with its own password either" {
	# The passwordless half is not the whole hole - the password is a known
	# constant, so an authenticated escalation is the same outcome by a
	# slightly longer route. Set it explicitly rather than relying on the
	# default, so the test states what it assumes.
	run in_image 'echo "abc:abc" | chpasswd; su -s /bin/bash abc -c "echo abc | sudo -S id"'
	[[ $output != *"uid=0"* ]] || {
		echo "abc escalated to root by supplying its password: $output"
		return 1
	}
}

@test "tws: s6's init-adduser does not restore the membership" {
	# The step that made this risky to fix blind. It renumbers abc's uid and
	# gid from PUID/PGID on every start; if it also re-added secondary groups,
	# a build-time removal would last until the first boot and no further.
	run in_image 'PUID=1000 PGID=1000 bash /etc/s6-overlay/s6-rc.d/init-adduser/run >/dev/null 2>&1; id -nG abc'
	[ "$status" -eq 0 ]
	[[ $output != *sudo* ]] || {
		echo "init-adduser put abc back in the sudo group: $output"
		return 1
	}
}

@test "tws: root can still drop privileges to abc" {
	# tws-scripts/start_session.sh runs `sudo -EH -u abc run_tws.sh` on every
	# start. Removing the *membership* rather than the sudoers rule is what
	# keeps this working - sudo does not authenticate root. If this breaks,
	# the container starts and TWS never does.
	run in_image 'sudo -EH -u abc id -un'
	[ "$status" -eq 0 ]
	[[ $output == *abc* ]] || {
		echo "root can no longer drop to abc; start_session.sh would fail: $output"
		return 1
	}
}
