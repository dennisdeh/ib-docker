#!/usr/bin/env bash
#
# Run the test suite.
#
#   tests/run.sh              unit tests - offline, no credentials, seconds
#   tests/run.sh container    starts a throwaway container; needs the image
#   tests/run.sh all          both
#
# bats is not installed on machines here, so it runs as a container, the same
# way the linters do. Nothing in this suite touches a running deployment or
# contacts Interactive Brokers.
set -Eeuo pipefail

cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/.."

BATS_IMAGE=bats/bats:1.14.0
RUNNER_IMAGE=ib-gateway-bats:local

run_unit() {
	echo ".> unit tests"
	docker run --rm -v "$PWD:/code" -w /code "$BATS_IMAGE" tests/unit
}

run_container() {
	echo ".> container tests"
	docker build -q -t "$RUNNER_IMAGE" tests/ >/dev/null
	docker run --rm \
		-v "$PWD:/code" -w /code \
		-v /var/run/docker.sock:/var/run/docker.sock \
		-e IB_GATEWAY_IMAGE \
		"$RUNNER_IMAGE" tests/container
}

case "${1:-unit}" in
unit) run_unit ;;
container) run_container ;;
all)
	run_unit
	run_container
	;;
*)
	echo "Usage: tests/run.sh [unit|container|all]" >&2
	exit 1
	;;
esac
