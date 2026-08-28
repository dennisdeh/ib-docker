#!/bin/bash
set -Eo pipefail

# `ssh -R bind:port:host:hostport` opens `port` ON THE SERVER and forwards it to
# `host:hostport` reached from here, inside the container. So the port published
# on the remote host is always API_PORT, and SSH_REMOTE_PORT - despite its name -
# is the container-local port the tunnel dials. They are equal unless
# SSH_REMOTE_PORT is set explicitly; see the SSH tunnel section of the README.
_OPTIONS="$SSH_ALL_OPTIONS"
_REMOTE_BIND_PORT="$API_PORT"
_LOCAL_TARGET_PORT="$SSH_REMOTE_PORT"
_SCREEN="$SSH_SCREEN"
_USER_TUNNEL="$SSH_USER_TUNNEL"
_RESTART="$SSH_RESTART"

# SSH_OPTIONS and SSH_SCREEN each carry several arguments in one variable, so
# they still have to be split on whitespace - but only into words, not through
# a shell. This used to be `bash -c "ssh ${_OPTIONS} ... ${_USER_TUNNEL}"`,
# which re-parsed every one of those operator-supplied values: a semicolon or a
# backtick in any of them ran. `read -ra` splits and stops there, and the
# destination is passed as a single argument. See docs/OPEN_ITEMS.md #12.
read -ra _OPTS <<<"$_OPTIONS"
read -ra _SCREEN_ARGS <<<"${_SCREEN:-}"

while true; do
	echo ".> Starting ssh tunnel with ssh sock: $SSH_AUTH_SOCK"
	ssh ${_OPTS[@]+"${_OPTS[@]}"} \
		-TNR "127.0.0.1:${_REMOTE_BIND_PORT}:localhost:${_LOCAL_TARGET_PORT}" \
		${_SCREEN_ARGS[@]+"${_SCREEN_ARGS[@]}"} \
		"$_USER_TUNNEL"
	sleep "${_RESTART:-5}"
done
