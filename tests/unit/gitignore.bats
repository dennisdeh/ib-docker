#!/usr/bin/env bats
#
# One trap in .gitignore, pinned as text.
#
# git cannot re-include a file whose parent directory is excluded, so
# `.claude/` together with `!.claude/settings.json` ignores settings.json
# anyway - silently, with no error and nothing in the file's wording to say so.
# Only the `.claude/*` form makes the negation work.
#
# This asks the file, not git: `git` is not installed in the bats image, and
# reimplementing gitignore matching in bash would only test the reimplementation.
# The behaviour itself was verified with `git check-ignore` on 2026-08-26.

setup() {
	ROOT="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"
	GITIGNORE="${ROOT}/.gitignore"
}

@test "gitignore: .claude uses the glob form so the negation can work" {
	run grep -qxF '.claude/*' "$GITIGNORE"
	[ "$status" -eq 0 ] || {
		echo "expected a literal '.claude/*' line in .gitignore"
		return 1
	}

	# The bare directory form would silently defeat the negation below it.
	run grep -qxF '.claude/' "$GITIGNORE"
	[ "$status" -ne 0 ] || {
		echo ".gitignore excludes '.claude/' as a directory;"
		echo "that makes '!.claude/settings.json' a no-op. Use '.claude/*'."
		return 1
	}
}

@test "gitignore: a shared .claude/settings.json is re-included" {
	run grep -qxF '!.claude/settings.json' "$GITIGNORE"
	[ "$status" -eq 0 ]
}

# .idea/ named six individual files once, so every file the IDE added later
# reappeared as untracked noise. The whole directory is ignored now.
@test "gitignore: .idea is ignored as a directory, not file by file" {
	run grep -qxF '.idea/' "$GITIGNORE"
	[ "$status" -eq 0 ] || {
		echo "expected a literal '.idea/' line in .gitignore"
		return 1
	}

	run grep -nE '^/?\.idea/.+' "$GITIGNORE"
	[ "$status" -ne 0 ] || {
		echo "individual .idea files are listed again; '.idea/' already covers them:"
		echo "$output"
		return 1
	}
}
