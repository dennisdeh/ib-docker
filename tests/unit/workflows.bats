#!/usr/bin/env bats
# shellcheck disable=SC2016  # ${{ ... }} is GitHub Actions syntax, matched literally
#
# Properties of the CI definition that only show up once a workflow has already
# run the wrong way. Reads .github/workflows as text; starts nothing.
#
# The release automation is asserted here too: detect a new IB Gateway version,
# build it, push it to ghcr.io. None of that can be exercised offline, and its
# failure modes are silent - a workflow that publishes nothing still reports
# success - so what is checked is the wiring, read out of the YAML as text.

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

# build.yml and publish.yml must build the same platforms, or CI passes and the
# release then fails on whatever the extra platform cannot do. A channel can
# only build linux/arm64 for a version whose release carries the arm installer.
# See docs/OPEN_ITEMS.md #18.
@test "workflows: build and publish declare the same platforms, including arm64" {
	local build_p publish_p
	build_p="$(sed -n 's/^  PLATFORMS: //p' "${WORKFLOWS}/build.yml")"
	publish_p="$(sed -n 's/^  PLATFORMS: //p' "${WORKFLOWS}/publish.yml")"
	[ -n "$build_p" ] || {
		echo "build.yml declares no PLATFORMS"
		return 1
	}
	[ "$build_p" = "$publish_p" ] || {
		echo "build.yml and publish.yml disagree on platforms"
		echo "build.yml:   $build_p"
		echo "publish.yml: $publish_p"
		return 1
	}
	case "$build_p" in
	*linux/arm64*) ;;
	*)
		echo "linux/arm64 is no longer built: $build_p"
		return 1
		;;
	esac
}

@test "workflows: no build step hard-codes its platform list" {
	local f
	for f in "${WORKFLOWS}/build.yml" "${WORKFLOWS}/publish.yml"; do
		run grep -n 'platforms: linux/' "$f"
		[ "$status" -ne 0 ] || {
			echo "$(basename "$f") pins platforms inline; drive them from the channel: $output"
			return 1
		}
	done
}

# Everything indented under `  <name>:` in a workflow's jobs map. Comments in
# these files are indented past their key, so `#` is excluded from the column
# that would otherwise end the block.
job_block() {
	awk -v job="$2" '
		/^jobs:/                     { in_jobs = 1; next }
		in_jobs && /^[^[:space:]#]/  { in_jobs = 0 }
		in_jobs && $0 ~ "^  " job ":[[:space:]]*$" { in_job = 1; next }
		in_job && /^  [^[:space:]#]/ { in_job = 0 }
		in_job                       { print }
	' "$1"
}

job_names() {
	awk '
		/^jobs:/ { in_jobs = 1; next }
		in_jobs && /^[^[:space:]#]/ { in_jobs = 0 }
		in_jobs && /^  [a-z][a-z0-9_-]*:[[:space:]]*$/ {
			gsub(/[[:space:]:]/, ""); print
		}
	' "$1"
}

# Everything belonging to one `      - name: <step>` entry, up to the next step.
step_block() {
	awk -v step="$2" '
		$0 ~ "^      - name: " step "$" { in_step = 1; next }
		in_step && /^      - /          { in_step = 0 }
		in_step                         { print }
	' "$1"
}

# First line number a fixed string appears on, so step order can be asserted.
line_of() {
	grep -nF -- "$2" "$1" | head -1 | cut -d : -f 1
}

@test "publish: the workflow can be called by another workflow" {
	# The release bot cannot publish by pushing a `v*` tag: a tag pushed with
	# GITHUB_TOKEN starts no workflow run. `workflow_call` is the only path
	# that does not silently publish nothing.
	run grep -c '^  workflow_call:' "${WORKFLOWS}/publish.yml"
	[ "$output" = "1" ]
}

@test "publish: the tag push and manual paths are still there" {
	run grep -c '^  workflow_dispatch:' "${WORKFLOWS}/publish.yml"
	[ "$output" = "1" ]
	run grep -c '^  push:' "${WORKFLOWS}/publish.yml"
	[ "$output" = "1" ]
}

@test "publish: both images are pushed to ghcr.io" {
	run cat "${WORKFLOWS}/publish.yml"
	[[ $output == *"ghcr.io/dennisdeh/ib-gateway"* ]]
	[[ $output == *"ghcr.io/dennisdeh/tws-rdesktop"* ]]

	run grep -c 'push: true' "${WORKFLOWS}/publish.yml"
	[ "$output" = "2" ]
}

@test "publish: the job may write packages" {
	run job_block "${WORKFLOWS}/publish.yml" publish-docker
	[[ $output == *"packages: write"* ]]
}

@test "publish: the gateway is pushed before TWS is built" {
	# Dockerfile.tws opens FROM ghcr.io/dennisdeh/ib-gateway:<version>. For a
	# version being published for the first time that tag exists only because
	# the step above pushed it, so this order is the whole reason a brand new
	# version can be built at all.
	gateway="$(line_of "${WORKFLOWS}/publish.yml" 'name: Build and push ibgateway')"
	tws="$(line_of "${WORKFLOWS}/publish.yml" 'name: Build and push TWS')"
	[ -n "$gateway" ]
	[ -n "$tws" ]
	[ "$gateway" -lt "$tws" ]
}

@test "publish: emits the three tags template_README.md documents" {
	# version, major.minor, channel - for each of the two images.
	run grep -c 'type=raw,value=${{ steps.version.outputs.version }}' "${WORKFLOWS}/publish.yml"
	[ "$output" = "2" ]
	run grep -c 'type=raw,value=${{ steps.version.outputs.minor }}' "${WORKFLOWS}/publish.yml"
	[ "$output" = "2" ]
	run grep -c 'type=raw,value=${{ steps.target.outputs.channel }}' "${WORKFLOWS}/publish.yml"
	[ "$output" = "2" ]
}

@test "publish: Docker Hub is optional, ghcr.io is not" {
	# Docker Hub needs secrets that a fork has no way to hold. Logging in to it
	# unconditionally fails the whole publish over a mirror.
	run job_block "${WORKFLOWS}/publish.yml" publish-docker
	[[ $output == *"steps.dockerhub.outputs.configured == 'true'"* ]]
}

@test "detect-releases: a publish job calls the publish workflow" {
	run job_names "${WORKFLOWS}/detect-releases.yml"
	[[ $output == *"publish"* ]]

	run job_block "${WORKFLOWS}/detect-releases.yml" publish
	[[ $output == *"uses: ./.github/workflows/publish.yml"* ]]
	[[ $output == *"secrets: inherit"* ]]
}

@test "detect-releases: the workflow it calls exists" {
	called="$(job_block "${WORKFLOWS}/detect-releases.yml" publish |
		grep -o 'uses: \./[^[:space:]]*' | cut -d ' ' -f 2)"
	[ -n "$called" ]
	[ -f "${ROOT}/${called#./}" ]
}

@test "detect-releases: publish is told the channel, version and commit" {
	run job_block "${WORKFLOWS}/detect-releases.yml" publish
	[[ $output == *"channel: \${{ matrix.target.channel }}"* ]]
	[[ $output == *"version: \${{ matrix.target.version }}"* ]]
	# The commit, not the branch name: a later push to the bot branch must not
	# change what was published under this version.
	[[ $output == *"ref: \${{ matrix.target.ref }}"* ]]
}

@test "detect-releases: the per-channel decision is not carried in job outputs" {
	# Both matrix legs would write the same `outputs:` name and the last one to
	# finish would win, so `stable` and `latest` overwrote each other's version.
	# The legs hand over files instead; the collect job reassembles them.
	job_block "${WORKFLOWS}/detect-releases.yml" detect-release >"${BATS_TEST_TMPDIR}/job"
	run grep -c '^    outputs:' "${BATS_TEST_TMPDIR}/job"
	[ "$output" = "0" ]

	run job_block "${WORKFLOWS}/detect-releases.yml" publish
	[[ $output == *"fromJSON(needs.collect.outputs.targets)"* ]]
}

@test "detect-releases: nothing detected means nothing is published" {
	run job_block "${WORKFLOWS}/detect-releases.yml" publish
	[[ $output == *"needs.collect.outputs.targets != '[]'"* ]]
}

@test "detect-releases: both legs record a plan, updated or not" {
	# The collect job globs pending/*.json; a leg that skipped writing its file
	# would make that glob fail rather than publish nothing.
	run step_block "${WORKFLOWS}/detect-releases.yml" "Record what to publish"
	[ -n "$output" ]
	[[ $output != *"if:"* ]]
}
