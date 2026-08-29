#!/usr/bin/env bats
# shellcheck disable=SC2016  # ${IB_GATEWAY_BASE_IMAGE} is a build arg, matched literally
#
# The image inventory: what this repository produces, what it consumes, and
# that nothing has quietly appeared in between.
#
# Three images ship - ib-gateway, tws-rdesktop and bastion - and everything the
# stack runs is one of them. A fourth image arriving in a compose file, or a
# service pointing at somebody else's registry, would work perfectly well on the
# machine that added it and be unbuildable and unpublishable everywhere else.
# The base images are the deliberate exception and are listed by name below, so
# adding a new third-party base is a decision rather than a diff nobody reads.
#
# Reads files as text. No docker, no network.

setup() {
	ROOT="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"
}

# The three images this repository builds and publishes.
OURS='ghcr.io/dennisdeh/ib-gateway ghcr.io/dennisdeh/tws-rdesktop ghcr.io/dennisdeh/bastion'

# Every Dockerfile that is a source. latest/ and stable/ are generated copies -
# tests/unit/dockerfile.bats already holds them byte-for-byte to the templates,
# so a base image can only differ there if that check is red too.
source_dockerfiles() {
	echo "${ROOT}/Dockerfile.template"
	echo "${ROOT}/Dockerfile.tws.template"
	echo "${ROOT}/bastion/Dockerfile"
	echo "${ROOT}/tests/Dockerfile"
}

# Compose files this repository ships, as opposed to the one deploy/provision.sh
# emits at run time onto a host.
compose_files() {
	echo "${ROOT}/docker-compose.yml"
	echo "${ROOT}/bastion/docker-compose.yml"
}

# Every file in the tree. Same find + grep shape as the helper in naming.bats,
# for the same reasons: bats runs on BusyBox grep, which rejects --exclude-dir,
# and `.git` is a *file* in a worktree rather than a directory to prune by path.
tree_grep() {
	find "$ROOT" \
		-name .git -prune -o \
		-name .venv -prune -o \
		-name .claude -prune -o \
		-type f -exec grep -nE -- "$1" /dev/null {} + 2>/dev/null || true
}

@test "images: every compose service runs an image this repository builds" {
	# `image:` lines only - `tags:` entries are build outputs and name the same
	# references. A service pulling anything else would not be reproducible from
	# this checkout.
	local f line img bad=''
	for f in $(compose_files); do
		while IFS= read -r line; do
			img="${line#*image:}"
			img="${img%%:[a-zA-Z0-9._\$-]*}"
			img="$(echo "$img" | tr -d '[:space:]')"
			case " $OURS " in
			*" $img "*) ;;
			*) bad="${bad}
  ${f#"${ROOT}/"}: ${img}" ;;
			esac
		done < <(grep -E '^[[:space:]]*image:' "$f")
	done
	[ -z "$bad" ] || {
		echo "compose services must run an image built here (${OURS}):${bad}"
		return 1
	}
}

@test "images: every compose service that names one of our images also builds it" {
	# `image:` without `build:` is how a compose file stops being reproducible
	# from this checkout: the service would run whatever ghcr.io last published
	# instead of what the tree in front of you builds. The deployment story is
	# deploy/provision.sh, which emits a separate file.
	local f images builds
	for f in $(compose_files); do
		images="$(grep -cE '^[[:space:]]*image:' "$f")"
		builds="$(grep -cE '^[[:space:]]*build:' "$f")"
		[ "$images" = "$builds" ] || {
			echo "${f#"${ROOT}/"}: ${images} image: lines but ${builds} build: lines"
			echo "every service here must be buildable from this checkout"
			return 1
		}
	done
}

@test "images: every compose service pins pull_policy: build" {
	# Without it, compose prefers a registry copy of ghcr.io/dennisdeh/<x>:latest
	# over the one it just built - and since the packages are public it will
	# fetch it. Each service must be as many pull_policy lines as image lines.
	local f images policy
	for f in $(compose_files); do
		images="$(grep -cE '^[[:space:]]*image:' "$f")"
		policy="$(grep -cE '^[[:space:]]*pull_policy:[[:space:]]*build' "$f")"
		[ "$images" = "$policy" ] || {
			echo "${f#"${ROOT}/"}: ${images} services, ${policy} with pull_policy: build"
			return 1
		}
	done
}

@test "images: no Dockerfile builds on an unapproved third-party base" {
	# The allowlist, and why each is here:
	#   ubuntu                        - the gateway and the bastion
	#   lscr.io/linuxserver/rdesktop  - the xrdp/xfce desktop the TWS image adds
	#                                   TWS to; the one third-party image inside
	#                                   anything published
	#   bats/bats                     - the local test runner, never shipped
	#   ${IB_GATEWAY_BASE_IMAGE}      - ours, passed as a build arg so CI can
	#                                   point it at a job-local registry
	local allowed='ubuntu lscr.io/linuxserver/rdesktop bats/bats ${IB_GATEWAY_BASE_IMAGE}'
	local f base bad=''
	for f in $(source_dockerfiles); do
		while IFS= read -r base; do
			base="${base#*FROM }"
			base="${base%% *}"
			base="${base%%:*}" # strip the tag, keep ${VAR} whole
			case " $allowed " in
			*" $base "*) ;;
			*) bad="${bad}
  ${f#"${ROOT}/"}: ${base}" ;;
			esac
		done < <(grep -E '^[[:space:]]*FROM ' "$f")
	done
	[ -z "$bad" ] || {
		echo "unapproved base image - add it to the allowlist here, with the reason,"
		echo "or build it in this repository:${bad}"
		return 1
	}
}

@test "images: dependabot watches every directory that holds a Dockerfile" {
	# Dependabot matches a Dockerfile with /dockerfile|containerfile/i on the
	# file name, unanchored, so a directory is covered if it is listed at all.
	# An image whose directory is missing here has its base image frozen until
	# somebody notices, which is how the bastion sat on an unwatched base.
	local conf="${ROOT}/.github/dependabot.yml" f dir bad=''
	for f in $(source_dockerfiles); do
		dir="$(dirname "${f#"${ROOT}"}")"
		grep -qF "\"${dir}\"" "$conf" || bad="${bad} ${dir}"
	done
	[ -z "$bad" ] || {
		echo "dependabot.yml does not watch:${bad}"
		echo "add them under the docker ecosystem's 'directories:' list"
		return 1
	}
}

@test "images: dependabot does not watch the generated channel directories" {
	# /latest and /stable are written by update.sh. A base-image bump landed
	# there is overwritten by the next release, so watching them is churn that
	# reads as coverage. See docs/OPEN_ITEMS.md #13.
	local conf="${ROOT}/.github/dependabot.yml"
	run grep -nE '"/(latest|stable)"' "$conf"
	[ "$status" -ne 0 ] || {
		echo "dependabot watches a generated directory; watch the source instead:"
		echo "$output"
		return 1
	}
}

@test "images: the three published images are the three the compose file builds" {
	# publish.yml and docker-compose.yml must agree on the inventory. If a
	# fourth image is ever added, both have to learn about it, and this is where
	# the mismatch surfaces.
	local img
	for img in $OURS; do
		run grep -qF "$img" "${ROOT}/docker-compose.yml"
		[ "$status" -eq 0 ] || {
			echo "docker-compose.yml does not build ${img}"
			return 1
		}
		run grep -qF "$img" "${ROOT}/.github/workflows/publish.yml"
		[ "$status" -eq 0 ] || {
			echo "publish.yml does not publish ${img}"
			return 1
		}
	done
}

@test "images: each Dockerfile claims the licence its own directory carries" {
	# The two were swapped. The gateway and TWS templates labelled themselves
	# "Apache License Version 2.0" while the tree they are built from is MIT,
	# and bastion/Dockerfile labelled itself MIT while bastion/ carries its own
	# Apache-2.0 LICENSE.txt - it is a fork, as bastion/README.md says. Nothing
	# caught it because docker/metadata-action overwrites the label at publish
	# time with one derived from the repository,
	# so all three published images read MIT whatever the Dockerfile said -
	# measured on the published images, 2026-08-30. A local `docker compose
	# build` keeps the Dockerfile's value, so the two disagreed.
	#
	# SPDX identifiers, which is what the label is specified to hold and what
	# metadata-action emits.
	local f
	for f in Dockerfile.template Dockerfile.tws.template; do
		run grep -qxF 'LABEL org.opencontainers.image.licenses=MIT' "${ROOT}/${f}"
		[ "$status" -eq 0 ] || {
			echo "${f} must label MIT, the licence of the tree it is built from"
			return 1
		}
	done
	run grep -q '^MIT License' "${ROOT}/LICENSE"
	[ "$status" -eq 0 ]

	run grep -qxF 'LABEL org.opencontainers.image.licenses=Apache-2.0' "${ROOT}/bastion/Dockerfile"
	[ "$status" -eq 0 ] || {
		echo "bastion/Dockerfile must label Apache-2.0; bastion/LICENSE.txt is that licence"
		return 1
	}
	run grep -q 'Apache License' "${ROOT}/bastion/LICENSE.txt"
	[ "$status" -eq 0 ]
}

@test "images: the bastion build context excludes the files it must never ship" {
	# The context is a directory people keep real files in: bastion/.env holds
	# the bastion's own settings and /data holds the provisioned host keys,
	# shadow and authorized_keys. Neither is COPYd today - the Dockerfile names
	# five files - so nothing leaked; both were nonetheless uploaded to the
	# daemon on every build, and the first `COPY . .` anyone writes ships them.
	# .gitignore already refuses them; this is the same refusal for the build.
	local ignore="${ROOT}/bastion/.dockerignore" pat
	for pat in '/data' '.env' '.env.*' '*.env'; do
		run grep -qxF "$pat" "$ignore"
		[ "$status" -eq 0 ] || {
			echo "bastion/.dockerignore does not exclude '${pat}'"
			return 1
		}
	done
}

@test "images: nothing tells a reader to log in before pulling" {
	# All three packages are public - measured anonymously on 2026-08-29; see
	# docs/DECISIONS.md #32. They were private until then, and the instruction to
	# `docker login ghcr.io` outlived that in five places, both READMEs among
	# them, and in a warning deploy/provision.sh prints on a failed pull - where
	# it misdiagnoses whatever actually went wrong.
	#
	# This pins the instruction, not the reasoning. A comment explaining itself
	# with "the package is private" is prose no grep holds reliably, and it is
	# split across lines in two of the places it occurred; DECISIONS.md #32 is
	# the single home for that reasoning instead. Publishing logs in through
	# docker/login-action, never through this string, so there is no legitimate
	# occurrence of it. Should the packages ever go private again, that decision
	# rewrites #32 and deletes this test in the same commit.
	local hits
	hits="$(tree_grep 'docker login ghcr\.io' |
		grep -v "$(basename "${BATS_TEST_FILENAME}")" || true)"
	[ -z "$hits" ] || {
		echo "the ghcr.io packages are public; pulling them needs no login:"
		echo "$hits"
		return 1
	}
}
