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
