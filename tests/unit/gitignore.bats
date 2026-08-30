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

# config.ini and jts.ini are rendered from the .tmpl files with the IB password
# substituted in, and both docker-compose.yml and template_README.md suggest
# bind-mounting them from the repository root. A bind-mounted *file* is written
# through in place, so following the documented customisation puts broker
# credentials at the root of the checkout. Neither the `.env` pattern in the
# pre-commit hook nor `detect-private-key` matches them, and `/config/` covers
# the directory the TWS image uses, not these. See docs/OPEN_ITEMS.md #41.
@test "gitignore: a rendered config.ini or jts.ini cannot be committed" {
	run grep -qxF '/config.ini' "$GITIGNORE"
	[ "$status" -eq 0 ] || {
		echo "config.ini holds the cleartext IB password once rendered;"
		echo "the documented bind mount writes it to the repository root."
		return 1
	}
	run grep -qxF '/jts.ini' "$GITIGNORE"
	[ "$status" -eq 0 ]
}

@test "gitignore: the pre-commit hook refuses them too, not just gitignore" {
	local root cfg
	root="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"
	cfg="${root}/.pre-commit-config.yaml"
	run grep -q 'no-rendered-ibc-config' "$cfg"
	[ "$status" -eq 0 ] || {
		echo ".gitignore alone is bypassed by 'git add -f';"
		echo "expected a no-rendered-ibc-config hook in .pre-commit-config.yaml"
		return 1
	}
	# and it must not swallow the templates, which are tracked on purpose
	run grep -qF '(config|jts)\.ini$' "$cfg"
	[ "$status" -eq 0 ] || {
		echo "the hook pattern must anchor on .ini so *.tmpl stays committable"
		return 1
	}
}
