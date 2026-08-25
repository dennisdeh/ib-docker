#!/usr/bin/env bats
#
# Properties of the CI definition that only show up once a workflow has already
# run the wrong way. Reads .github/workflows as text; starts nothing.

setup() {
	ROOT="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"
	WORKFLOWS="${ROOT}/.github/workflows"
}

# `uses: owner/repo/.github/workflows/x.yml@master` resolves against master, not
# against the branch under test, so a change to the called workflow cannot be
# tested before it is merged - and the same commit can pass on a branch and fail
# on master. See docs/DECISIONS.md #16.
@test "workflows: reusable workflows are called by local path" {
	run grep -rn 'uses: [^./[:space:]][^/[:space:]]*/[^/[:space:]]*/\.github/workflows/' "$WORKFLOWS"
	[ "$status" -ne 0 ] || {
		echo "call these with ./.github/workflows/<file>:"
		echo "$output"
		return 1
	}
}

# The build job must stay able to fail. It reported success regardless for the
# whole of its history once. See docs/OPEN_ITEMS.md #1.
@test "workflows: no job tolerates its own failure" {
	# The key itself, not build.yml's comment warning against reintroducing it.
	run grep -rnE '^[[:space:]]*continue-on-error[[:space:]]*:' "$WORKFLOWS"
	[ "$status" -ne 0 ] || {
		echo "$output"
		return 1
	}
}

# The TWS image builds FROM the gateway image. CI must build that pair itself
# rather than reading a published one it has no credentials for.
@test "workflows: the build job needs no registry credentials" {
	run grep -n 'secrets\.' "${WORKFLOWS}/build.yml"
	[ "$status" -ne 0 ] || {
		echo "build.yml should not need a secret: $output"
		return 1
	}
	run grep -qF 'IB_GATEWAY_BASE_IMAGE=' "${WORKFLOWS}/build.yml"
	[ "$status" -eq 0 ]
}

# Credit for the project this was forked from belongs in LICENSE and the README.
# Nothing that runs - workflow, image, compose file, script or test - may depend
# on that repository. See docs/DECISIONS.md #17.
@test "decoupled: nothing that runs references the forked-from project" {
	local hits
	hits="$(find \
		"${ROOT}/.github" "${ROOT}/image-files" "${ROOT}/bastion" "${ROOT}/tests" \
		"${ROOT}/latest" "${ROOT}/stable" \
		"${ROOT}/Dockerfile.template" "${ROOT}/Dockerfile.tws.template" \
		"${ROOT}/docker-compose.yml" "${ROOT}/update.sh" \
		-type f ! -name '*.md' ! -name "$(basename "${BATS_TEST_FILENAME}")" \
		-exec grep -li 'gnzsnz' {} + 2>/dev/null || true)"
	[ -z "$hits" ] || {
		echo "credit belongs in LICENSE and the README, not in what runs:"
		echo "$hits"
		return 1
	}
}
