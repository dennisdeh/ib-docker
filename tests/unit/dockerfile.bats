#!/usr/bin/env bats
#
# The generated channel directories, and the two properties of the image build
# that a build on an amd64 machine cannot demonstrate: the installer is chosen
# per architecture, and the tws base image is overridable.
#
# All of this reads files as text. No Docker, no network, no credentials.

setup() {
	ROOT="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"
	CHANNELS="stable latest"
}

# The version update.sh was last run with for a channel.
channel_version() {
	sed -n 's/^ENV IB_GATEWAY_VERSION=//p' "${ROOT}/$1/Dockerfile" | head -1
}

# update.sh runs `envsubst '$VERSION,$CHANNEL'` over the template. Both
# templates use the bare $VERSION / $CHANNEL form only, so sed reproduces it.
expand_template() {
	sed -e "s/\$VERSION/$2/g" -e "s/\$CHANNEL/$1/g" "$3"
}

@test "channels: Dockerfile is exactly update.sh's output for the template" {
	local channel version
	for channel in $CHANNELS; do
		version="$(channel_version "$channel")"
		[ -n "$version" ]
		run diff -u \
			<(expand_template "$channel" "$version" "${ROOT}/Dockerfile.template") \
			"${ROOT}/${channel}/Dockerfile"
		[ "$status" -eq 0 ] || {
			echo "${channel}/Dockerfile is stale - run ./update.sh ${channel} ${version}"
			echo "$output"
			return 1
		}
	done
}

@test "channels: Dockerfile.tws is exactly update.sh's output for the template" {
	local channel version
	for channel in $CHANNELS; do
		version="$(channel_version "$channel")"
		run diff -u \
			<(expand_template "$channel" "$version" "${ROOT}/Dockerfile.tws.template") \
			"${ROOT}/${channel}/Dockerfile.tws"
		[ "$status" -eq 0 ] || {
			echo "${channel}/Dockerfile.tws is stale - run ./update.sh ${channel} ${version}"
			echo "$output"
			return 1
		}
	done
}

@test "channels: image-files is copied verbatim into both channels" {
	local channel sub
	for channel in $CHANNELS; do
		for sub in config scripts tws-scripts; do
			run diff -r "${ROOT}/image-files/${sub}" "${ROOT}/${channel}/${sub}"
			[ "$status" -eq 0 ] || {
				echo "${channel}/${sub} differs from image-files/${sub}"
				echo "$output"
				return 1
			}
		done
	done
}

# The x64 installer bundles an x86-64 JRE and runs it, so on aarch64 it dies
# with "jre/bin/java: not found". See docs/OPEN_ITEMS.md #17.
@test "build: the IB Gateway installer is chosen by architecture" {
	local channel
	for channel in $CHANNELS; do
		# shellcheck disable=SC2016  # literal Dockerfile text, not a shell expansion
		run grep -qF 'standalone-linux-${ib_arch}.sh' "${ROOT}/${channel}/Dockerfile"
		[ "$status" -eq 0 ] || {
			echo "${channel}/Dockerfile does not select the installer by architecture"
			return 1
		}
		run grep -qF 'ib_arch=arm' "${ROOT}/${channel}/Dockerfile"
		[ "$status" -eq 0 ]
	done
}

@test "build: no uncommented line pins the installer to x64" {
	local channel
	for channel in $CHANNELS; do
		run grep -n 'standalone-linux-x64' "${ROOT}/${channel}/Dockerfile"
		# The only permitted mention is the commented COPY hint.
		while IFS= read -r line; do
			[ -z "$line" ] && continue
			case "${line#*:}" in
			\#*) ;;
			*)
				echo "${channel}/Dockerfile pins the x64 installer: $line"
				return 1
				;;
			esac
		done <<<"$output"
	done
}

# The installer downloads must fail on a 404 rather than saving the error page
# and failing later at the checksum with a misleading message.
@test "build: installer downloads use curl -f" {
	local channel
	for channel in $CHANNELS; do
		run grep -c 'curl -sSOLf' "${ROOT}/${channel}/Dockerfile"
		[ "$status" -eq 0 ]
		[ "$output" -ge 3 ]
	done
}

# The build used to download an aarch64 Zulu JRE and pass app_java_home to the
# installer, which does not honour it - so the JRE was fetched, verified,
# shipped and never used. The installer supplies its own; see OPEN_ITEMS #17.
# Matches the download's identifiers, not the word "zulu", which legitimately
# appears in comments and in the JRE path the installer records.
@test "build: no separate JRE is downloaded any more" {
	local channel marker
	for channel in $CHANNELS; do
		for marker in 'cdn\.azul\.com' 'ZULU_SHA256' 'ZULU_URL' 'ZULU_NAME' 'app_java_home'; do
			run grep -nE "$marker" "${ROOT}/${channel}/Dockerfile"
			[ "$status" -ne 0 ] || {
				echo "${channel}/Dockerfile still fetches a JRE the installer ignores ($marker): $output"
				return 1
			}
		done
	done
}

# Both Dockerfiles must prove a JVM survived into the runtime stage. Where the
# installer leaves it varies by version and architecture - latest@10.48.1e keeps
# one inside the install directory, stable@10.45.1j only under /usr/local - so a
# missing copy breaks one channel and not the other. See DECISIONS.md #18.
@test "build: the runtime stage proves it has a JVM" {
	local channel f
	for channel in $CHANNELS; do
		for f in Dockerfile Dockerfile.tws; do
			run grep -qF 'COPY --from=setup /usr/local/ /usr/local/' "${ROOT}/${channel}/${f}"
			[ "$status" -eq 0 ] || {
				echo "${channel}/${f} does not copy /usr/local, which carries the JRE"
				return 1
			}
			# shellcheck disable=SC2016  # literal Dockerfile text, not a shell expansion
			run grep -qF '"${java_bin}" -version' "${ROOT}/${channel}/${f}"
			[ "$status" -eq 0 ] || {
				echo "${channel}/${f} does not check that a JVM is present"
				return 1
			}
		done
	done
}

@test "tws: the gateway base image is a build arg, not a fixed ghcr reference" {
	local channel
	for channel in $CHANNELS; do
		run grep -qF 'ARG IB_GATEWAY_BASE_IMAGE=' "${ROOT}/${channel}/Dockerfile.tws"
		[ "$status" -eq 0 ]
		# shellcheck disable=SC2016  # literal Dockerfile text, not a shell expansion
		run grep -qF 'FROM ${IB_GATEWAY_BASE_IMAGE}:${IB_VERSION}' "${ROOT}/${channel}/Dockerfile.tws"
		[ "$status" -eq 0 ] || {
			echo "${channel}/Dockerfile.tws does not take its base image from the build arg"
			return 1
		}
	done
}
