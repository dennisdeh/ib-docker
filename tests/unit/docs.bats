#!/usr/bin/env bats
#
# Claims in CLAUDE.md that a machine can check.
#
# CLAUDE.md is written in the present tense about the tree as it is - unlike
# docs/, which keeps dated records and may legitimately name an old version.
# So a number in it is either current or wrong, and both of the checks below
# found a wrong one on 2026-08-30: the test count had been 106 since
# 2026-08-29 while the suite had grown, and the latest channel was named as
# 10.48.1e two releases after it moved.
#
# Reads files as text. No docker, no network.

setup() {
	ROOT="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"
	CLAUDE="${ROOT}/CLAUDE.md"
}

@test "docs: CLAUDE.md's unit-test count is the number of tests there are" {
	local claimed actual
	claimed="$(sed -n 's/.* \([0-9]\{2,\}\) tests as of [0-9-]*[.,].*/\1/p' "$CLAUDE" | head -1)"
	actual="$(grep -ch '^@test ' "${ROOT}"/tests/unit/*.bats | awk '{n += $1} END {print n}')"
	[ -n "$claimed" ] || {
		echo "CLAUDE.md no longer states a unit-test count in the form '<n> tests as of <date>'"
		return 1
	}
	[ "$claimed" = "$actual" ] || {
		echo "CLAUDE.md says ${claimed} unit tests; there are ${actual}."
		echo "Update the number and its date together - a bare count goes stale silently."
		return 1
	}
}

@test "docs: CLAUDE.md names only the gateway versions the tree builds" {
	# Every 10.x.y in CLAUDE.md has to be one of the two the channels are on.
	# docs/ is deliberately not checked: OPEN_ITEMS.md and DECISIONS.md are
	# dated records, and naming a superseded version is the point there.
	local latest stable v bad=''
	latest="$(sed -n 's/^ENV IB_GATEWAY_VERSION=//p' "${ROOT}/latest/Dockerfile" | head -1)"
	stable="$(sed -n 's/^ENV IB_GATEWAY_VERSION=//p' "${ROOT}/stable/Dockerfile" | head -1)"
	while IFS= read -r v; do
		[ "$v" = "$latest" ] || [ "$v" = "$stable" ] || bad="${bad} ${v}"
	done < <(grep -oE '\b10\.[0-9]+\.[0-9]+[a-z]?\b' "$CLAUDE" | sort -u)
	[ -z "$bad" ] || {
		echo "CLAUDE.md names IB Gateway versions this tree does not build:${bad}"
		echo "the channels are on ${latest} (latest) and ${stable} (stable)"
		return 1
	}
}
