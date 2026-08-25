#!/usr/bin/env bats
#
# shellcheck disable=SC2034  # tests set variables that the sourced functions read
# shellcheck disable=SC2030,SC2031  # bats runs every @test in its own subshell
#
# image-files/scripts/common.sh - the pure functions.
#
# common.sh is function definitions only, so sourcing it has no side effects.
# Nothing here needs a container, a network or credentials.

setup() {
	COMMON="${BATS_TEST_DIRNAME}/../../image-files/scripts/common.sh"
	# shellcheck source=/dev/null
	source "$COMMON"
	TMP="$(mktemp -d)"
}

teardown() {
	rm -rf "$TMP"
}

#
# set_ports - the API port is bound inside the container, socat publishes it.
# The published port is NOT the API port; that surprise is the reason these
# four cases are pinned.
#

@test "set_ports: gateway paper serves API 4002 behind socat 4004" {
	GATEWAY_OR_TWS=gateway TRADING_MODE=paper
	set_ports
	[ "$API_PORT" = "4002" ]
	[ "$SOCAT_PORT" = "4004" ]
}

@test "set_ports: gateway live serves API 4001 behind socat 4003" {
	GATEWAY_OR_TWS=gateway TRADING_MODE=live
	set_ports
	[ "$API_PORT" = "4001" ]
	[ "$SOCAT_PORT" = "4003" ]
}

@test "set_ports: tws paper serves API 7497 behind socat 7499" {
	GATEWAY_OR_TWS=tws TRADING_MODE=paper
	set_ports
	[ "$API_PORT" = "7497" ]
	[ "$SOCAT_PORT" = "7499" ]
}

@test "set_ports: tws live serves API 7496 behind socat 7498" {
	GATEWAY_OR_TWS=tws TRADING_MODE=live
	set_ports
	[ "$API_PORT" = "7496" ]
	[ "$SOCAT_PORT" = "7498" ]
}

@test "set_ports: an unknown trading mode is refused, not defaulted" {
	run bash -c "source '$COMMON'; GATEWAY_OR_TWS=gateway TRADING_MODE=margin set_ports"
	[ "$status" -eq 1 ]
	[[ $output == *"Invalid TRADING_MODE"* ]]
}

#
# file_env - VAR or VAR_FILE, never both.
#

@test "file_env: keeps a value passed directly" {
	TWS_PASSWORD=direct
	file_env TWS_PASSWORD
	[ "$TWS_PASSWORD" = "direct" ]
}

@test "file_env: reads the value out of VAR_FILE" {
	printf 'from-a-file' >"$TMP/pw"
	unset TWS_PASSWORD
	TWS_PASSWORD_FILE="$TMP/pw"
	file_env TWS_PASSWORD
	[ "$TWS_PASSWORD" = "from-a-file" ]
}

@test "file_env: refuses VAR and VAR_FILE together instead of picking one" {
	run bash -c "source '$COMMON'; TWS_PASSWORD=a TWS_PASSWORD_FILE=$TMP/pw file_env TWS_PASSWORD"
	[ "$status" -eq 1 ]
	[[ $output == *"exclusive"* ]]
}

@test "file_env: falls back to the default when neither is set" {
	unset TWS_PASSWORD TWS_PASSWORD_FILE
	file_env TWS_PASSWORD 'fallback'
	[ "$TWS_PASSWORD" = "fallback" ]
}

#
# unset_env - a secret that came from a file must not stay in the environment
# of the processes started afterwards.
#

@test "unset_env: clears the value when it came from a file" {
	printf 'secret' >"$TMP/pw"
	unset TWS_PASSWORD
	TWS_PASSWORD_FILE="$TMP/pw"
	file_env TWS_PASSWORD
	[ "$TWS_PASSWORD" = "secret" ]
	unset_env TWS_PASSWORD
	[ -z "${TWS_PASSWORD+set}" ]
}

@test "unset_env: leaves a directly-passed value alone" {
	TWS_PASSWORD=direct
	unset TWS_PASSWORD_FILE
	unset_env TWS_PASSWORD
	[ "$TWS_PASSWORD" = "direct" ]
}

#
# set_java_heap - rewrites the shipped vmoptions file in place.
#

@test "set_java_heap: replaces the default heap size" {
	TWS_PATH="$TMP" IB_GATEWAY_VERSION=10.48.1e
	mkdir -p "$TMP/ibgateway/10.48.1e"
	printf -- '-Xmx768m\n' >"$TMP/ibgateway/10.48.1e/ibgateway.vmoptions"
	JAVA_HEAP_SIZE=2048
	set_java_heap
	grep -qx -- '-Xmx2048m' "$TMP/ibgateway/10.48.1e/ibgateway.vmoptions"
}

@test "set_java_heap: leaves the file untouched when unset" {
	TWS_PATH="$TMP" IB_GATEWAY_VERSION=10.48.1e
	mkdir -p "$TMP/ibgateway/10.48.1e"
	printf -- '-Xmx768m\n' >"$TMP/ibgateway/10.48.1e/ibgateway.vmoptions"
	JAVA_HEAP_SIZE=
	set_java_heap
	grep -qx -- '-Xmx768m' "$TMP/ibgateway/10.48.1e/ibgateway.vmoptions"
}
