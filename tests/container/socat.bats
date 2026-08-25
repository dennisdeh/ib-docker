#!/usr/bin/env bats
#
# Port topology inside a real container.
#
# IB Gateway binds the API port on the container's own loopback and socat
# republishes it on a different port - so the port compose publishes is the
# socat one, and a client aimed at the documented API port never connects.
# That is the single most confusing thing about this image, so it is pinned
# here against the actual image rather than against the scripts.
#
# No credentials and no contact with IB: the gateway is never started, only
# the port-forwarding half of run.sh.

IMAGE="${IB_GATEWAY_IMAGE:-ghcr.io/dennisdeh/ib-gateway:latest}"
# A constant name, deliberately: bats re-sources this file in a new process for
# every test, so anything derived from $$ would differ between setup_file and
# the tests that look the container up.
CNAME="ib-gateway-bats"

setup_file() {
	if ! docker image inspect "$IMAGE" >/dev/null 2>&1; then
		skip "image $IMAGE not present - build it or set IB_GATEWAY_IMAGE"
	fi
	docker rm -f "$CNAME" >/dev/null 2>&1 || true
	docker run -d --name "$CNAME" \
		-e GATEWAY_OR_TWS=gateway \
		-e TRADING_MODE=paper \
		--entrypoint bash "$IMAGE" -c \
		'source "${SCRIPT_PATH}/common.sh"; set_ports; start_socat; sleep 120' \
		>/dev/null
	# socat is backgrounded by start_socat; give it a moment to listen
	for _ in $(seq 1 20); do
		if docker exec "$CNAME" bash -c 'timeout 1 bash -c "</dev/tcp/127.0.0.1/4004"' 2>/dev/null; then
			break
		fi
		sleep 0.5
	done
}

teardown_file() {
	docker rm -f "$CNAME" >/dev/null 2>&1 || true
}

# Guard every test: `docker exec` against a container that never started also
# returns non-zero, which would let the negative test below pass for the wrong
# reason.
assert_container_running() {
	run docker inspect -f '{{.State.Running}}' "$CNAME"
	[ "$status" -eq 0 ]
	[ "$output" = "true" ]
}

@test "container: socat listens on the published port 4004" {
	assert_container_running
	run docker exec "$CNAME" bash -c 'timeout 2 bash -c "</dev/tcp/127.0.0.1/4004"'
	[ "$status" -eq 0 ]
}

@test "container: nothing listens on API port 4002 - that is the gateway's own" {
	# The gateway is not running here, so this proves 4002 is not what socat
	# publishes. Aiming a client at 4002 from outside can never work.
	assert_container_running
	run docker exec "$CNAME" bash -c 'timeout 2 bash -c "</dev/tcp/127.0.0.1/4002"'
	[ "$status" -ne 0 ]
}

@test "container: socat reports the forward it set up" {
	assert_container_running
	run docker logs "$CNAME"
	[[ $output == *"Forking :::4002 onto 0.0.0.0:4004"* ]]
}
