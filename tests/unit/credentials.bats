#!/usr/bin/env bats
#
# Credentials the image handles for the user: the VNC password must not reach
# the process list, and the TWS image's default RDP password must not be a
# public one nobody was told about.
#
# ---------------------------------------------------------------------------
# VNC
#
# `x11vnc -passwd "$VNC_SERVER_PASSWORD"` put it in argv, where anything able to
# read /proc could see it - x11vnc's own help says exactly that about -passwd,
# and recommends -passwdfile instead. The password is short-lived and the port
# is published on 127.0.0.1, which is why this was low severity rather than
# urgent, but there was no reason to keep it. See docs/OPEN_ITEMS.md #10.
#
# start_vnc() is lifted out of run.sh and run against a stub x11vnc, so this
# needs no X server, no image and no network.

setup() {
	ROOT="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"
	RUN_SH="${ROOT}/image-files/scripts/run.sh"
	TMP="$(mktemp -d)"
	export X11VNC_ARGS="${TMP}/argv"
	cat >"${TMP}/x11vnc" <<-'STUB'
		#!/bin/sh
		printf '%s\n' "$@" >"$X11VNC_ARGS"
	STUB
	chmod +x "${TMP}/x11vnc"
}

teardown() {
	rm -rf "$TMP"
}

# Run the real start_vnc with the helpers it calls stubbed out.
run_start_vnc() {
	{
		echo 'wait_x_socket() { :; }'
		echo 'file_env() { :; }'
		echo 'unset_env() { :; }'
		awk '/^start_vnc\(\) \{$/,/^}$/' "$RUN_SH"
		echo 'start_vnc'
		echo 'wait'
	} >"${TMP}/harness.sh"

	PATH="${TMP}:$PATH" DISPLAY=":1" VNC_SERVER_PASSWORD="$1" \
		timeout 10 bash "${TMP}/harness.sh" >/dev/null 2>&1
	sleep 0.3
}

@test "vnc: the password is not passed on the command line" {
	run_start_vnc 'hunter2-secret'
	[ -f "$X11VNC_ARGS" ] || {
		echo "x11vnc was never invoked; the extraction or the stub is wrong"
		return 1
	}
	run grep -F 'hunter2-secret' "$X11VNC_ARGS"
	[ "$status" -ne 0 ] || {
		echo "the password reached x11vnc's argv:"
		cat "$X11VNC_ARGS"
		return 1
	}
	run grep -F -- '-passwd' "$X11VNC_ARGS"
	[[ $output != '-passwd' ]] || {
		echo "-passwd is still used; -passwdfile keeps it out of the process list"
		return 1
	}
}

@test "vnc: the password is handed over in a file x11vnc then deletes" {
	run_start_vnc 'hunter2-secret'

	local arg file
	arg="$(grep -E '^rm:' "$X11VNC_ARGS" || true)"
	[ -n "$arg" ] || {
		echo "expected a -passwdfile argument prefixed rm:, got:"
		cat "$X11VNC_ARGS"
		return 1
	}
	# The rm: prefix is what makes x11vnc remove the file once it has read it,
	# so the password is not left behind either.
	file="${arg#rm:}"
	[ -f "$file" ] || {
		echo "the password file ${file} was not written"
		return 1
	}
	run cat "$file"
	[ "$output" = 'hunter2-secret' ]
	[ "$(stat -c '%a' "$file")" = '600' ] || {
		echo "password file is mode $(stat -c '%a' "$file"), expected 600"
		return 1
	}
}

@test "vnc: no server is started when no password is set" {
	run_start_vnc ''
	[ ! -f "$X11VNC_ARGS" ] || {
		echo "x11vnc was started without a password:"
		cat "$X11VNC_ARGS"
		return 1
	}
}

# ---------------------------------------------------------------------------
# RDP
#
# The TWS image inherits linuxserver's `abc` account, and PASSWD defaults to
# `abc` as well. That is safe only while 3389 is published on 127.0.0.1, which
# the sample docker-compose.yml does - anyone binding it more widely inherits a
# password that is written down in this repository. The image cannot see which
# interface the host published on, and changing the default would break every
# deployment relying on it, so it says so at every start instead.
# See docs/OPEN_ITEMS.md #11.

START_SESSION() { echo "${ROOT}/image-files/tws-scripts/start_session.sh"; }

# Run just the password block of start_session.sh, with what it calls stubbed.
run_set_password() {
	{
		echo 'file_env() { :; }'
		echo 'unset_env() { :; }'
		echo 'chpasswd() { cat >"'"${TMP}"'/chpasswd"; }'
		awk '/^# set user pass$/,/^unset_env .PASSWD.$/' "$(START_SESSION)"
	} >"${TMP}/pw.sh"

	if [ "$#" -eq 1 ]; then
		PASSWD="$1" bash "${TMP}/pw.sh" 2>&1
	else
		env -u PASSWD bash "${TMP}/pw.sh" 2>&1
	fi
}

@test "rdp: an unset PASSWD warns that the default is public" {
	run run_set_password
	[ "$status" -eq 0 ]
	[[ $output == *"WARNING"* ]] || {
		echo "no warning when falling back to the published default:"
		echo "$output"
		return 1
	}
	[[ $output == *"127.0.0.1"* ]]
	# and it still sets the documented default, so nothing breaks
	run cat "${TMP}/chpasswd"
	[ "$output" = 'abc:abc' ]
}

@test "rdp: a PASSWD that was set warns about nothing" {
	run run_set_password 'a-real-password'
	[ "$status" -eq 0 ]
	[[ $output != *"WARNING"* ]] || {
		echo "warned even though PASSWD was set:"
		echo "$output"
		return 1
	}
	run cat "${TMP}/chpasswd"
	[ "$output" = 'abc:a-real-password' ]
}

# Every file .gitignore treats as a real environment file - the same shape the
# `no-real-env-files` pre-commit hook matches - that actually exists in this
# tree. `.env-dist` is excluded: it is tracked, holds no values, and is the key
# list two compose files are read against.
real_env_files() {
	find "$ROOT" \
		-name .git -prune -o \
		-name .venv -prune -o \
		-name .claude -prune -o \
		-type f \( -name '.env' -o -name '.env.*' -o -name '*.env' \) \
		! -name '*.env-dist' -print 2>/dev/null || true
}

@test "credentials: a real env file is readable only by its owner" {
	# A file mode is not in git, so nothing carries it between machines and
	# nothing notices it changing back. `cp .env-dist .env` creates the file at
	# the umask default - 664 on this machine - and that is how four of the five
	# real env files here sat group- and world-readable for five days *after*
	# docs/OPEN_ITEMS.md #3 was marked FIXED, having only ever chmod'd one of
	# them. Two of the four were the files the live deployment reads.
	#
	# The property is "no group or other bits", not "exactly 600", so 400 and
	# 700 pass too.
	local f mode bad='' n=0
	while IFS= read -r f; do
		[ -n "$f" ] || continue
		n=$((n + 1))
		mode="$(stat -c '%a' "$f")"
		case "$mode" in
		*00) ;;
		*) bad="${bad}
  ${mode}  ${f#"${ROOT}/"}" ;;
		esac
	done < <(real_env_files)

	# A fresh clone and CI have none of these; there is nothing to assert there.
	[ "$n" -gt 0 ] || skip "no real env file in this tree"

	[ -z "$bad" ] || {
		echo "these hold credentials and are readable beyond their owner:${bad}"
		echo "chmod 600 them. A mode is not tracked, so this can only be caught here."
		return 1
	}
}
