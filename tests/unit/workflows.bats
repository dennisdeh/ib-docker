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
#
# `naming.bats` is excluded for the same reason `*.md` is: it asserts that the
# credit still names that project correctly, so it has to contain the string.
@test "decoupled: nothing that runs references the forked-from project" {
	local hits
	hits="$(find \
		"${ROOT}/.github" "${ROOT}/image-files" "${ROOT}/bastion" "${ROOT}/tests" \
		"${ROOT}/latest" "${ROOT}/stable" \
		"${ROOT}/Dockerfile.template" "${ROOT}/Dockerfile.tws.template" \
		"${ROOT}/docker-compose.yml" "${ROOT}/update.sh" \
		-type f ! -name '*.md' ! -name "$(basename "${BATS_TEST_FILENAME}")" \
		! -name 'naming.bats' \
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
	# Three declarations since publish-bastion.yml split out on 2026-08-30, and
	# all three have to agree - the bastion is built for both architectures too.
	local build_p f other
	build_p="$(sed -n 's/^  PLATFORMS: //p' "${WORKFLOWS}/build.yml")"
	[ -n "$build_p" ] || {
		echo "build.yml declares no PLATFORMS"
		return 1
	}
	for f in publish.yml publish-bastion.yml; do
		other="$(sed -n 's/^  PLATFORMS: //p' "${WORKFLOWS}/${f}")"
		[ "$build_p" = "$other" ] || {
			echo "build.yml and ${f} disagree on platforms"
			echo "build.yml: $build_p"
			echo "${f}: $other"
			return 1
		}
	done
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
	for f in "${WORKFLOWS}/build.yml" "${WORKFLOWS}/publish.yml" \
		"${WORKFLOWS}/publish-bastion.yml"; do
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

@test "publish: all three images are pushed to ghcr.io" {
	run cat "${WORKFLOWS}/publish.yml"
	[[ $output == *"ghcr.io/dennisdeh/ib-gateway"* ]]
	[[ $output == *"ghcr.io/dennisdeh/tws-rdesktop"* ]]
	run grep -c 'push: true' "${WORKFLOWS}/publish.yml"
	[ "$output" = "2" ]

	# The bastion too, so a host can be provisioned without a checkout to build
	# anything from - from its own workflow since 2026-08-30, which publish.yml
	# calls. See docs/DECISIONS.md #22.
	run cat "${WORKFLOWS}/publish-bastion.yml"
	[[ $output == *"ghcr.io/dennisdeh/bastion"* ]]
	run grep -c 'push: true' "${WORKFLOWS}/publish-bastion.yml"
	[ "$output" = "1" ]
	run grep -qF 'uses: ./.github/workflows/publish-bastion.yml' "${WORKFLOWS}/publish.yml"
	[ "$status" -eq 0 ] || {
		echo "publish.yml no longer calls publish-bastion.yml, so an IB release"
		echo "would stop refreshing the bastion against its Ubuntu base"
		return 1
	}
}

@test "publish-bastion: a change under bastion/ publishes it" {
	# The gap this closes: the bastion had no trigger of its own, so the CA fix
	# of 2026-08-29 sat unpublished until an unrelated IB Gateway release would
	# have carried it, and four bastion_ca.bats cases were red against the
	# published image meanwhile. See docs/OPEN_ITEMS.md #31.
	local f="${WORKFLOWS}/publish-bastion.yml"
	run grep -c '^  push:' "$f"
	[ "$output" = "1" ]
	run grep -qF "      - 'bastion/**'" "$f"
	[ "$status" -eq 0 ] || {
		echo "publish-bastion.yml does not watch bastion/**"
		return 1
	}
	# Without master here the trigger would fire on every branch and publish
	# unreviewed work over the tag.
	run grep -qE '^      - master$' "$f"
	[ "$status" -eq 0 ] || {
		echo "publish-bastion.yml's push trigger is not restricted to master"
		return 1
	}
	# The permission it needs, declared by the workflow itself rather than
	# borrowed from publish.yml, which is what let it stand alone.
	run grep -qE '^      packages: write' "$f"
	[ "$status" -eq 0 ]
}

@test "publish: the bastion is tagged with the version it declares" {
	# It carries no IB version, so its tag comes from its own Dockerfile - the
	# same shape as the channel version gate above.
	run grep -qF "sed -n 's/^ARG IMAGE_VERSION=//p' bastion/Dockerfile" "${WORKFLOWS}/publish-bastion.yml"
	[ "$status" -eq 0 ]
	run grep -c 'ARG IMAGE_VERSION=' "${ROOT}/bastion/Dockerfile"
	[ "$output" = "1" ]
	# It is used by a LABEL, and went undeclared for long enough that every
	# image reported its version as "-resolute".
	run grep -q 'org.opencontainers.image.version=${IMAGE_VERSION}' "${ROOT}/bastion/Dockerfile"
	[ "$status" -eq 0 ]
}

@test "publish: ghcr links the bastion package to this repository" {
	# ghcr.io reads org.opencontainers.image.source to attach a package to a
	# repository; pointing it elsewhere leaves the package orphaned. It named
	# dennisdeh/docker-bastion - which is not this repository - until
	# 2026-08-27, so match the whole value rather than just the owner.
	run grep -q 'org.opencontainers.image.source=https://github.com/dennisdeh/ib-docker$' \
		"${ROOT}/bastion/Dockerfile"
	[ "$status" -eq 0 ]
}

@test "publish: the bastion's licence label survives metadata-action" {
	# metadata-action emits org.opencontainers.image.licenses from the
	# *repository's* licence - MIT - and its labels are applied after the
	# Dockerfile's, so they win. That is fine for the gateway and TWS, which are
	# MIT, and wrong for the bastion, which is Apache-2.0: the published image
	# read MIT until 2026-08-30 whatever bastion/Dockerfile said. Naming it in
	# the step's own `labels:` is what overrides the derived default.
	run grep -q 'org.opencontainers.image.licenses=Apache-2.0' "${WORKFLOWS}/publish-bastion.yml"
	[ "$status" -eq 0 ] || {
		echo "the bastion meta step must pin org.opencontainers.image.licenses=Apache-2.0,"
		echo "or metadata-action labels the published image MIT from the repository licence"
		return 1
	}
}

@test "detect-ibc: the pinned IBC digest is verified every run" {
	# IBC ships no checksum file, so the digest is pinned by hand beside the
	# version. A bump that moves one and not the other breaks nothing until a
	# gateway release renders a channel from the template - which is exactly
	# what was merged on 2026-08-27. The check must not sit behind the
	# "is there an update / does the branch exist" conditions that let it
	# through, so it carries no `if:`.
	run step_block "${WORKFLOWS}/detect-ibc-release.yml" "Verify the pinned IBC digest"
	[ -n "$output" ]
	[[ $output != *"if:"* ]]
	[[ $output == *"sha256sum"* ]]
	[[ $output == *"ARG IBC_SHA256="* ]]
}

@test "workflows: CI builds the bastion it publishes" {
	# publish.yml pushes this image, so a break must fail the PR check rather
	# than a release.
	run grep -q 'context: ./bastion' "${WORKFLOWS}/build.yml"
	[ "$status" -eq 0 ]
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
	# version, major.minor, channel - for each of the two IB images, which is
	# why the expected count is 2 and not 3. The bastion has no IB version, so
	# it is tagged from its own ARG IMAGE_VERSION by a separate meta step.
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

# The README's Supported Tags table names an IBC version per channel. It used to
# read one IBC_VERSION from Dockerfile.template and print it on every row, so
# whenever the two channels differed - the normal state between an IBC release
# and the next gateway one, see docs/DECISIONS.md #2 - the table asserted
# something false about one of them. tests/unit/naming.bats reproduces the
# substitution and diffs the committed README; this pins the workflow that will
# regenerate it, which that check cannot see.
@test "detect-releases: the README takes IBC from each channel, not the template" {
	local step
	step="$(step_block "${WORKFLOWS}/detect-releases.yml" "Update README")"
	[ -n "$step" ]

	[[ $step == *'LATEST_IBC=$(grep '"'"'ENV IBC_VERSION'"'"' $_latest_dockerfile'* ]] || {
		echo "LATEST_IBC is not read from latest/Dockerfile:"
		echo "$step"
		return 1
	}
	[[ $step == *'STABLE_IBC=$(grep '"'"'ENV IBC_VERSION'"'"' $_stable_dockerfile'* ]] || {
		echo "STABLE_IBC is not read from stable/Dockerfile:"
		echo "$step"
		return 1
	}
	# Dockerfile.template holds what the *next* release ships. Reading it here
	# is the defect above.
	[[ $step != *"IBC_VERSION' Dockerfile.template"* ]] || {
		echo "the README still takes its IBC version from Dockerfile.template"
		return 1
	}
}

@test "detect-releases: envsubst substitutes exactly the documented variables" {
	# envsubst with an explicit list leaves anything unlisted as literal text,
	# so a template placeholder that is not named here reaches README.md
	# verbatim - and a name listed here but absent from the template silently
	# does nothing. Both are caught by keeping the list pinned.
	local step line
	step="$(step_block "${WORKFLOWS}/detect-releases.yml" "Update README")"
	line="$(grep -o "envsubst '[^']*'" <<<"$step")"
	[ "$line" = "envsubst '\$LATEST_VERSION,\$LATEST_MINOR,\$LATEST_IBC,\$STABLE_VERSION,\$STABLE_MINOR,\$STABLE_IBC,\$BASTION_VERSION'" ] || {
		echo "unexpected envsubst variable list: ${line}"
		echo "keep it in step with readme_vars() in tests/unit/naming.bats"
		return 1
	}
}

# Everything above reads the workflows as text. What follows runs the shell they
# contain. The version gate it covers is the one publishing mistake nothing
# downstream can detect - a correct image under a wrong tag - and a text match
# can show only that the code is present, never that it fires.

# The `run: |` body of a named step, dedented, so it can be executed here.
step_script() {
	awk -v step="$2" '
		$0 ~ "^      - name: " step "$" { in_step = 1; next }
		in_step && /^      - /         { exit }
		in_step && /^        run: \|/  { in_run = 1; next }
		in_run && /^          /        { sub(/^          /, ""); print; next }
		in_run && /^[[:space:]]*$/     { print ""; next }
		in_run                         { exit }
	' "$1"
}

declared_version() {
	grep 'ENV IB_GATEWAY_VERSION=' "${ROOT}/$1/Dockerfile" | head -1 | cut -d '=' -f 2
}

github_ref_for() {
	if [ "$1" = 'push' ]; then echo "refs/tags/$2"; else echo "refs/heads/$2"; fi
}

# publish.yml's first resolution step on its own, echoing "<exit status>
# <channel>". It is run apart from the version step because the version gate
# refuses an unknown channel too - by way of a `<channel>/Dockerfile` that
# cannot exist - and that redundancy hides the channel guard being deleted:
# removing it changes no outcome any whole-job assertion can see.
#
# publish.yml declares no `defaults.run.shell`, so its steps get GitHub's
# default of `bash -e {0}`.
#
#   resolve_channel <inputs.channel> <inputs.ref> <ref_name> <event>
resolve_channel() {
	local in_channel="$1" in_ref="$2" ref_name="$3" event="$4"
	local out status

	local script gref
	out="${BATS_TEST_TMPDIR}/gh_output"
	: >"$out"
	script="$(step_script "${WORKFLOWS}/publish.yml" 'Resolve channel and ref')"
	gref="$(github_ref_for "$event" "$ref_name")"

	status=0
	(
		cd "$ROOT" || exit 1
		IN_CHANNEL="$in_channel" IN_REF="$in_ref" REF_NAME="$ref_name" \
			GITHUB_REF="$gref" GITHUB_EVENT_NAME="$event" GITHUB_OUTPUT="$out" \
			bash -e -c "$script"
	) >/dev/null 2>&1 || status=$?

	echo "$status $(sed -n 's/^channel=//p' "$out")"
}

# Both resolution steps, as the runner runs them, echoing "<exit status>
# <channel> <version>".
#
#   resolve <inputs.channel> <inputs.version> <inputs.ref> <ref_name> <event>
resolve() {
	local in_channel="$1" in_version="$2" in_ref="$3" ref_name="$4" event="$5"
	local out first status channel version

	first="$(resolve_channel "$in_channel" "$in_ref" "$ref_name" "$event")"
	status="${first%% *}"
	channel="${first#* }"
	out="${BATS_TEST_TMPDIR}/gh_output"

	local script gref
	script="$(step_script "${WORKFLOWS}/publish.yml" 'Resolve version')"
	gref="$(github_ref_for "$event" "$ref_name")"

	version=''
	if [ "$status" -eq 0 ]; then
		(
			cd "$ROOT" || exit 1
			IN_VERSION="$in_version" REF_NAME="$ref_name" CHANNEL="$channel" \
				GITHUB_REF="$gref" GITHUB_EVENT_NAME="$event" GITHUB_OUTPUT="$out" \
				bash -e -c "$script"
		) >/dev/null 2>&1 || status=$?
		version="$(sed -n 's/^version=//p' "$out")"
	fi

	echo "$status $channel $version"
}

@test "publish: an unknown channel is refused before anything is built" {
	run resolve_channel latest deadbeef master workflow_call
	[ "$output" = "0 latest" ]
	run resolve_channel stable deadbeef master workflow_call
	[ "$output" = "0 stable" ]

	# The channel names the build context directory. Accepting anything else
	# would build an empty context, or the wrong channel, and say nothing.
	run resolve_channel nightly deadbeef master workflow_call
	[ "${output%% *}" = "1" ]
	run resolve_channel '' '' "v1.2.3-master" push
	[ "${output%% *}" = "1" ]
	run resolve_channel '' '' "v1.2.3" push
	[ "${output%% *}" = "1" ]
}

@test "publish: a call publishes the channel and version it was given" {
	local want
	want="$(declared_version latest)"
	run resolve latest "$want" deadbeef master workflow_call
	[ "$output" = "0 latest $want" ]

	want="$(declared_version stable)"
	run resolve stable "$want" deadbeef master workflow_call
	[ "$output" = "0 stable $want" ]
}

@test "publish: an image is never tagged with a version it does not contain" {
	# Publishing `stable`'s version out of the `latest` tree, or a version no
	# tree builds at all, must fail the job rather than push a mislabelled
	# image. Nothing downstream of here can tell the difference.
	run resolve latest "$(declared_version stable)" deadbeef master workflow_call
	[ "${output%% *}" = "1" ]

	run resolve latest 99.99.9z deadbeef master workflow_call
	[ "${output%% *}" = "1" ]
}

@test "publish: a v<version>-<channel> tag resolves both" {
	local want
	want="$(declared_version latest)"
	run resolve '' '' '' "v${want}-latest" push
	[ "$output" = "0 latest $want" ]

	want="$(declared_version stable)"
	run resolve '' '' '' "v${want}-stable" push
	[ "$output" = "0 stable $want" ]
}

@test "publish: a tag that does not name a channel publishes nothing" {
	local want
	want="$(declared_version latest)"
	# No channel field at all; a branch name where the channel belongs; and a
	# suffixed tag, which parses as a channel but whose version half no longer
	# matches the tree - `cut -f 2` is happy with all three.
	run resolve '' '' '' "v${want}" push
	[ "${output%% *}" = "1" ]
	run resolve '' '' '' "v${want}-master" push
	[ "${output%% *}" = "1" ]
	run resolve '' '' '' "v${want}-latest-rc1" push
	[ "${output%% *}" = "1" ]
}

@test "publish: a dispatch with no version reads it from the channel Dockerfile" {
	local want
	want="$(declared_version stable)"
	run resolve stable '' '' master workflow_dispatch
	[ "$output" = "0 stable $want" ]
}

@test "release: a detected IB Gateway version publishes all three images" {
	# The property the whole automation exists for, asserted end to end. Each
	# link has its own test above; this one fails when the *chain* breaks, which
	# is exactly what was wrong until 2026-08-30 - every link was present and the
	# bastion still only reached ghcr.io when Interactive Brokers happened to
	# release. See docs/OPEN_ITEMS.md #31.
	#
	# The permission and secret hops are half the point. A called workflow cannot
	# hold a permission its caller withheld, and secrets do not cross a
	# `workflow_call` without `secrets: inherit` - so either omission publishes
	# nothing while every file still looks right.
	local dr="${WORKFLOWS}/detect-releases.yml"
	local pub="${WORKFLOWS}/publish.yml"
	local bas="${WORKFLOWS}/publish-bastion.yml"
	local bad=''

	# hop 1: the daily poll reaches publish.yml, carrying push rights and secrets
	grep -qF 'uses: ./.github/workflows/publish.yml' "$dr" ||
		bad="${bad}
  detect-releases.yml no longer calls publish.yml"
	grep -qE '^      packages: write' "$dr" ||
		bad="${bad}
  detect-releases.yml's publish job cannot grant packages: write"
	grep -qE '^    secrets: inherit' "$dr" ||
		bad="${bad}
  detect-releases.yml does not pass secrets to publish.yml"

	# hop 2: publish.yml pushes the two channel images and reaches the bastion
	[ "$(grep -c 'push: true' "$pub")" = "2" ] ||
		bad="${bad}
  publish.yml no longer pushes exactly the gateway and tws images"
	grep -qF 'uses: ./.github/workflows/publish-bastion.yml' "$pub" ||
		bad="${bad}
  publish.yml no longer calls publish-bastion.yml, so an IB release skips it"
	grep -qE '^    secrets: inherit' "$pub" ||
		bad="${bad}
  publish.yml does not pass secrets on to publish-bastion.yml"

	# hop 3: the bastion is actually pushed, under its own permission
	[ "$(grep -c 'push: true' "$bas")" = "1" ] ||
		bad="${bad}
  publish-bastion.yml no longer pushes the bastion"
	grep -qE '^      packages: write' "$bas" ||
		bad="${bad}
  publish-bastion.yml does not declare the packages: write it needs"

	[ -z "$bad" ] || {
		echo "a new IB Gateway version would not reach all three images:${bad}"
		return 1
	}
}

@test "publish: two runs pushing the same tags queue rather than race" {
	# docs/OPEN_ITEMS.md #32. Both publishing workflows push to fixed tags, and
	# between them they have seven ways in, so overlap is a matter of timing
	# rather than of anyone doing something wrong.
	local f
	for f in publish.yml publish-bastion.yml; do
		run grep -qE '^concurrency:' "${WORKFLOWS}/${f}"
		[ "$status" -eq 0 ] || {
			echo "${f} declares no concurrency group; two runs can push the same tag at once"
			return 1
		}
		# The dangerous half. Cancelling a half-finished multi-architecture push
		# leaves the registry holding some manifests and not others; queueing
		# costs minutes and leaves it consistent.
		run grep -qE '^  cancel-in-progress: false' "${WORKFLOWS}/${f}"
		[ "$status" -eq 0 ] || {
			echo "${f} must set cancel-in-progress: false - a cancelled push is worse than a slow one"
			return 1
		}
	done

	# Keyed on the channel, or detect-releases.yml's two-channel matrix - which
	# sets fail-fast: false precisely so the legs are independent - would queue
	# behind itself and take twice as long for no reason.
	run grep -qE '^  group: publish-\$\{\{ inputs\.channel' "${WORKFLOWS}/publish.yml"
	[ "$status" -eq 0 ] || {
		echo "publish.yml's concurrency group must include the channel, or the"
		echo "stable and latest legs of a release serialise against each other"
		return 1
	}
}
