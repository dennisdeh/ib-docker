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

while true; do
	echo ".> Starting ssh tunnel with ssh sock: $SSH_AUTH_SOCK"
	bash -c "ssh ${_OPTIONS} -TNR 127.0.0.1:${_REMOTE_BIND_PORT}:localhost:${_LOCAL_TARGET_PORT} ${_SCREEN:-} ${_USER_TUNNEL}"
	sleep "${_RESTART:-5}"
done
