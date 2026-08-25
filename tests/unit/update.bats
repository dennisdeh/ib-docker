#!/usr/bin/env bats
#
# update.sh - argument handling only.
#
# A successful run rewrites latest/ or stable/, so only the paths that refuse
# to do anything are exercised here. Both checks happen before the first `cp`.

setup() {
	UPDATE="${BATS_TEST_DIRNAME}/../../update.sh"
}

@test "update.sh: refuses a channel that is neither stable nor latest" {
	run bash "$UPDATE" nightly 10.48.1e
	[ "$status" -eq 1 ]
	[[ $output == *"must be 'stable' or 'latest'"* ]]
}

@test "update.sh: refuses a missing version" {
	run bash "$UPDATE" latest
	[ "$status" -eq 1 ]
	[[ $output == *"Usage:"* ]]
}

@test "update.sh: refuses no arguments at all" {
	run bash "$UPDATE"
	[ "$status" -eq 1 ]
	[[ $output == *"Usage:"* ]]
}
