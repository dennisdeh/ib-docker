#!/usr/bin/env bats
#
# image-files/scripts/run_ssh.sh - which side of the tunnel each port is on.
#
# `ssh -R bind:port:host:hostport` opens `port` ON THE SERVER and forwards it to
# `host:hostport` reached from inside the container. The names in the README
# said the opposite for years, hidden by a default that makes both equal. These
# tests pin the real shape by running the script against a stub ssh.

setup() {
	RUN_SSH="${BATS_TEST_DIRNAME}/../../image-files/scripts/run_ssh.sh"
	TMP="$(mktemp -d)"
	# stub ssh: record the arguments and return, so the script's retry loop
	# runs exactly one iteration inside the timeout below
	cat >"$TMP/ssh" <<-'STUB'
		#!/bin/sh
		echo "$@" >>"$SSH_ARGS_FILE"
	STUB
	chmod +x "$TMP/ssh"
	export SSH_ARGS_FILE="$TMP/args"
	: >"$SSH_ARGS_FILE"
}

teardown() {
	rm -rf "$TMP"
}

# Run run_ssh.sh for one iteration with the given environment and return the
# ssh argument line it built.
tunnel_args() {
	PATH="$TMP:$PATH" \
		SSH_ALL_OPTIONS="-o ServerAliveInterval=20" \
		SSH_SCREEN="" \
		SSH_USER_TUNNEL="ibgateway@bastion" \
		SSH_RESTART=30 \
		API_PORT="$1" \
		SSH_REMOTE_PORT="$2" \
		timeout 5 bash "$RUN_SSH" >/dev/null 2>&1 || true
	cat "$SSH_ARGS_FILE"
}

@test "run_ssh: by default the same port is opened remotely and dialled locally" {
	run tunnel_args 4002 4002
	[[ $output == *"-TNR 127.0.0.1:4002:localhost:4002"* ]]
}

@test "run_ssh: the port opened on the server is API_PORT, not SSH_REMOTE_PORT" {
	# The trap: SSH_REMOTE_PORT looks like it selects the server-side port.
	# It does not - it selects the container-local target. If this ever starts
	# failing because the bind port became 9999, the documented meaning changed
	# and template_README.md must change with it.
	run tunnel_args 4002 9999
	[[ $output == *"-TNR 127.0.0.1:4002:localhost:9999"* ]]
	[[ $output != *"127.0.0.1:9999:"* ]]
}

@test "run_ssh: the ssh options and destination are passed through" {
	run tunnel_args 4001 4001
	[[ $output == *"-o ServerAliveInterval=20"* ]]
	[[ $output == *"ibgateway@bastion"* ]]
}

# Every value below reaches ssh from the environment, and the loop used to
# assemble them into one string and hand it to `bash -c`. That re-parsed all of
# them: a semicolon, a backtick or a $(...) in SSH_OPTIONS, SSH_SCREEN or
# SSH_USER_TUNNEL ran as a command. They are operator-controlled, so this was
# never a way in from outside - but a password with a backtick in it, pasted
# into SSH_USER_TUNNEL, would have executed rather than failed to connect.
# See docs/OPEN_ITEMS.md #12.

# Like tunnel_args, but records one argument per line so a value that should
# have stayed whole can be told from one that was split.
tunnel_argv() {
	cat >"$TMP/ssh" <<-'STUB'
		#!/bin/sh
		printf '%s\n' "$@" >>"$SSH_ARGS_FILE"
	STUB
	chmod +x "$TMP/ssh"
	PATH="$TMP:$PATH" \
		SSH_ALL_OPTIONS="${2:--o ServerAliveInterval=20}" \
		SSH_SCREEN="${3:-}" \
		SSH_USER_TUNNEL="$1" \
		SSH_RESTART=30 \
		API_PORT=4002 \
		SSH_REMOTE_PORT=4002 \
		timeout 5 bash "$RUN_SSH" >/dev/null 2>&1 || true
	cat "$SSH_ARGS_FILE"
}

@test "run_ssh: a metacharacter in the destination does not run" {
	local marker="$TMP/pwned"
	run tunnel_argv "ibgateway@bastion; touch ${marker}"
	[ ! -e "$marker" ] || {
		echo "the destination was re-parsed by a shell and executed"
		return 1
	}
	# and it reached ssh whole, as one argument
	[[ $output == *"ibgateway@bastion; touch ${marker}"* ]]
}

@test "run_ssh: a command substitution in the ssh options does not run" {
	local marker="$TMP/pwned_opts"
	run tunnel_argv "ibgateway@bastion" "-o ServerAliveInterval=20 \$(touch ${marker})"
	[ ! -e "$marker" ] || {
		echo "SSH_OPTIONS was re-parsed by a shell and executed"
		return 1
	}
}

@test "run_ssh: multi-word options and screen forwards still split into argv" {
	# The other half of the fix: these carry several arguments in one variable
	# and must still be split on whitespace, or every option would reach ssh as
	# a single unusable word.
	run tunnel_argv "ibgateway@bastion" \
		"-o ServerAliveInterval=20 -o ServerAliveCountMax=3" \
		"-R 127.0.0.1:5900:localhost:5900"
	[[ $output == *"-o"* ]]
	[[ $output == *"ServerAliveInterval=20"* ]]
	[[ $output == *"ServerAliveCountMax=3"* ]]
	[[ $output == *"127.0.0.1:5900:localhost:5900"* ]]
	# each on its own line - i.e. separate arguments, not one blob
	[ "$(grep -c '^-o$' <<<"$output")" -ge 2 ]
}
