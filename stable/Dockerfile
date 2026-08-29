##############################################################################
# Setup Stage: install apps
#
# This is a dedicated stage so that donwload archives don't end up on
# production image and consume unnecessary space.
##############################################################################

# hadolint global ignore=DL3008,DL4006
FROM ubuntu:24.04 AS setup

ENV IB_GATEWAY_VERSION=10.45.1j
ENV IB_GATEWAY_CHANNEL=stable
ENV IBC_VERSION=3.24.1
ARG DEBIAN_FRONTEND=noninteractive
ARG IB_GATEWAY_REPO="https://github.com/dennisdeh/ib-docker"
ARG IB_GATEWAY_RELEASE_URL="${IB_GATEWAY_REPO}/releases/download/ibgateway-${IB_GATEWAY_CHANNEL}%40${IB_GATEWAY_VERSION}"
ARG IBC_FILE="IBCLinux-${IBC_VERSION}.zip"
ARG IBC_REPO="https://github.com/IbcAlpha/IBC"
ARG IBC_URL="${IBC_REPO}/releases/download/${IBC_VERSION}/${IBC_FILE}"
# IBC publishes no checksum file, so the digest is pinned here and MUST be
# updated with IBC_VERSION - it is the digest of the IBCLinux-<IBC_VERSION>.zip
# named above, and of no other version. .github/workflows/detect-ibc-release.yml
# recomputes it when it opens a version-bump PR, and verifies it on every daily
# run; tests/unit/dockerfile.bats pins the version-to-digest pairing offline.
ARG IBC_SHA256=d99ee28cc3539e3843fb00d28dc484c255006b0063d38f0808ac3ef07dd88bb8

WORKDIR /tmp/setup

# Prepare system
#
# IB ships one installer per architecture, each carrying a JRE built for that
# architecture, so the x64 one cannot install on aarch64 - it unpacks an x86-64
# java and dies. Where that JRE lands varies by version; see docs/DECISIONS.md.
# `-f` matters: without it a 404 is saved as an HTML page and the failure
# surfaces later as an unreadable checksum mismatch.
#
# apt is retried because ports.ubuntu.com - the aarch64 mirror, and only it -
# intermittently serves an index referencing a .deb its pool 404s on, which
# fails the emulated leg with apt's exit 100. A fresh `apt-get update` on the
# next attempt re-resolves, usually against a different mirror node. See
# docs/OPEN_ITEMS.md #19.
RUN for attempt in 1 2 3; do \
    apt-get update -y && \
    apt-get install --no-install-recommends --yes curl ca-certificates unzip && \
    break; \
    [ "$attempt" = 3 ] && exit 1; \
    echo ".> apt failed, refreshing indices and retrying (attempt ${attempt})"; \
    sleep 15; \
  done && \
  apt-get clean && \
  rm -rf /var/lib/apt/lists/* && \
# Install IB Gateway
# Use this instead of "RUN curl .." to install a local file:
#COPY ibgateway-${IB_GATEWAY_VERSION}-standalone-linux-x64.sh .
  if [ "$(uname -m)" = "aarch64" ]; then ib_arch=arm; else ib_arch=x64; fi && \
  ib_file="ibgateway-${IB_GATEWAY_VERSION}-standalone-linux-${ib_arch}.sh" && \
  curl -sSOLf "${IB_GATEWAY_RELEASE_URL}/${ib_file}" && \
  curl -sSOLf "${IB_GATEWAY_RELEASE_URL}/${ib_file}.sha256" && \
  sha256sum --check "./${ib_file}.sha256" && \
  chmod a+x "./${ib_file}" && \
  "./${ib_file}" -q -dir "/root/Jts/ibgateway/${IB_GATEWAY_VERSION}" && \
  # Install IBC
  curl -sSOLf ${IBC_URL} && \
  echo "${IBC_SHA256}  ${IBC_FILE}" | sha256sum --check - && \
  mkdir /root/ibc && \
  unzip ./${IBC_FILE} -d /root/ibc && \
  chmod -R u+x /root/ibc/*.sh && \
  chmod -R u+x /root/ibc/scripts/*.sh

COPY ./config/ibgateway/jts.ini.tmpl /root/Jts/jts.ini.tmpl
COPY ./config/ibc/config.ini.tmpl /root/ibc/config.ini.tmpl

# Copy scripts
COPY ./scripts /root/scripts

##############################################################################
# Build Stage: build production image
##############################################################################

FROM ubuntu:24.04

ENV IB_GATEWAY_VERSION=10.45.1j
# IB Gateway user constants
ARG USER_ID="${USER_ID:-1000}"
ARG USER_GID="${USER_GID:-1000}"
# IBC env vars
ENV HOME=/home/ibgateway
ENV TWS_MAJOR_VRSN=${IB_GATEWAY_VERSION}
ENV TWS_PATH=${HOME}/Jts
ENV TWS_INI=jts.ini
ENV TWS_INI_TMPL=${TWS_INI}.tmpl
ENV IBC_PATH=${HOME}/ibc
ENV IBC_INI=${HOME}/ibc/config.ini
ENV IBC_INI_TMPL=${IBC_INI}.tmpl
ENV SCRIPT_PATH=${HOME}/scripts
ENV GATEWAY_OR_TWS=gateway
ARG DEBIAN_FRONTEND=noninteractive
# Copy files
# /usr/local carries the JRE. The IB installer puts it in
# /usr/local/i4j_jres/<id>/<version>-zulu and records that path in the install
# directory's .install4j/pref_jre.cfg, so dropping this copy leaves a launcher
# pointing at a JVM that is not in the image. See docs/DECISIONS.md.
COPY --from=setup /usr/local/ /usr/local/
COPY --chown=${USER_ID}:${USER_GID} --from=setup /root/ ${HOME}

# Prepare system
RUN for attempt in 1 2 3; do \
    apt-get update -y && \
    apt-get upgrade -y && \
    apt-get install --no-install-recommends --yes \
    gettext-base socat xvfb x11vnc sshpass openssh-client sudo telnet && \
    break; \
    [ "$attempt" = 3 ] && exit 1; \
    echo ".> apt failed, refreshing indices and retrying (attempt ${attempt})"; \
    sleep 15; \
  done && \
  apt-get clean && \
  rm -rf /var/lib/apt/lists/* && \
  if id ubuntu; then \
    userdel -rf ubuntu \
  ;fi && \
  groupadd --gid ${USER_GID} ibgateway && \
  useradd -ms /bin/bash --uid ${USER_ID} --gid ${USER_GID} ibgateway && \
  echo "ibgateway ALL=(ALL) NOPASSWD:ALL" | tee -a /etc/sudoers && \
  chmod a+x ${SCRIPT_PATH}/*.sh && \
  mkdir -p /tmp/.X11-unix && chmod 1777 /tmp/.X11-unix

# Fail the build if no JVM survived the copies above. IB puts the JRE either
# under /usr/local/i4j_jres or inside the install directory, depending on the
# version and the architecture, and a missing one is otherwise invisible until
# the container starts and IBC cannot launch.
RUN java_bin="$(find /usr/local/i4j_jres ${TWS_PATH} -name java -type f -print -quit 2>/dev/null || true)" && \
  [ -n "${java_bin}" ] && "${java_bin}" -version

USER ${USER_ID}:${USER_GID}
WORKDIR ${HOME}

# Start run script
CMD ["/home/ibgateway/scripts/run.sh"]

LABEL org.opencontainers.image.source=https://github.com/dennisdeh/ib-docker
LABEL org.opencontainers.image.url=https://github.com/dennisdeh/ib-docker/pkgs/container/ib-gateway
LABEL org.opencontainers.image.description="Docker image with IB Gateway and IBC "
LABEL org.opencontainers.image.licenses=MIT
LABEL org.opencontainers.image.version=${IB_GATEWAY_VERSION}-${IB_GATEWAY_RELEASE_CHANNEL}
