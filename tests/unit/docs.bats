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

# This suite can be copied into a tree that deliberately does not take
# CLAUDE.md. The Investio deployment did exactly that until 2026-08-30, on the
# reasoning that Claude Code auto-loads a nested CLAUDE.md as binding
# instructions and this one's framing ("not the running deployment", "never run
# a compose lifecycle command here") is false there. It now vendors nothing at
# all - see docs/DECISIONS.md #38 - but the skip stays: the reasoning applies to
# any consumer, and a test that needs a file its tree does not have should say
# so rather than fail or, worse, pass.
#
# Skipping is the honest answer, and it has to be explicit: without it the
# version check below passes on a file that is not there, having found no
# versions to object to - green by construction, which is docs/OPEN_ITEMS.md #1
# in miniature.
need_claude_md() {
	[ -f "$CLAUDE" ] || skip "CLAUDE.md is not vendored into this tree"
}

@test "docs: CLAUDE.md's unit-test count is the number of tests there are" {
	need_claude_md
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
	need_claude_md
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

@test "docs: no item number is used twice in OPEN_ITEMS or DECISIONS" {
	# Both files number their items, and both are appended to by more than one
	# session at a time. That collided twice on 2026-08-30: two `| 35 |` rows in
	# DECISIONS.md when a rebase brought a branch's row alongside master's, and
	# again an hour later when four cross-references were written as #36 against
	# numbers already taken. Neither is something git can see - both sides merge
	# cleanly and the table simply has two rows with the same identifier, which
	# the files describe as an identifier other documents cite.
	#
	# An item is defined either as a table row `| N |` or as a heading `### N.`,
	# and the two forms are disjoint in both files - measured, not assumed. A
	# `| #N |` row is a *reference* to an item defined elsewhere, not a second
	# definition, so the leading hash keeps it out of this count.
	local f n dupes bad=''
	for f in "${ROOT}/docs/OPEN_ITEMS.md" "${ROOT}/docs/DECISIONS.md"; do
		dupes="$(
			{
				sed -n 's/^|[[:space:]]*\([0-9][0-9]*\)[[:space:]]*|.*/\1/p' "$f"
				sed -n 's/^###[[:space:]]\{1,\}\([0-9][0-9]*\)\..*/\1/p' "$f"
			} | sort -n | uniq -d
		)"
		for n in $dupes; do
			bad="${bad}
  ${f#"${ROOT}/"}: #${n} is defined more than once"
		done
	done
	[ -z "$bad" ] || {
		echo "an item number identifies an item, and other documents cite it:${bad}"
		echo "renumber the newer one and update anything pointing at it."
		return 1
	}
}
