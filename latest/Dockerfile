##############################################################################
# Setup Stage: install apps
#
# This is a dedicated stage so that donwload archives don't end up on
# production image and consume unnecessary space.
##############################################################################

# hadolint global ignore=DL3008,DL4006
FROM ubuntu:24.04 AS setup

ENV IB_GATEWAY_VERSION=10.48.1e
ENV IB_GATEWAY_CHANNEL=latest
ENV IBC_VERSION=3.24.1
ARG DEBIAN_FRONTEND=noninteractive
ARG IB_GATEWAY_FILE="ibgateway-${IB_GATEWAY_VERSION}-standalone-linux-x64.sh"
ARG IB_GATEWAY_REPO="https://github.com/dennisdeh/ib-gateway-docker"
ARG IB_GATEWAY_URL="${IB_GATEWAY_REPO}/releases/download/ibgateway-${IB_GATEWAY_CHANNEL}%40${IB_GATEWAY_VERSION}/${IB_GATEWAY_FILE}"
ARG IBC_FILE="IBCLinux-${IBC_VERSION}.zip"
ARG IBC_REPO="https://github.com/IbcAlpha/IBC"
ARG IBC_URL="${IBC_REPO}/releases/download/${IBC_VERSION}/${IBC_FILE}"
# IBC publishes no checksum file, so the digest is pinned here and MUST be
# updated with IBC_VERSION. .github/workflows/detect-ibc-release.yml recomputes
# it when it opens a version-bump PR. Measured 2026-08-25 for 3.24.1.
ARG IBC_SHA256=d99ee28cc3539e3843fb00d28dc484c255006b0063d38f0808ac3ef07dd88bb8
ARG ZULU_NAME=zulu17.60.17-ca-fx-jre17.0.16-linux_aarch64
ARG ZULU_FILE=${ZULU_NAME}.tar.gz
ARG ZULU_URL=https://cdn.azul.com/zulu/bin/${ZULU_FILE}
# Azul publishes no checksum file either. Pinned for ZULU_NAME above; update
# both together. Measured 2026-08-25.
ARG ZULU_SHA256=e74bcc2df2cd070eb0325fe599a9c102e9728e7d266862048634bc1e7043b5d0

WORKDIR /tmp/setup

# Prepare system
RUN apt-get update -y && \
  apt-get install --no-install-recommends --yes \
  curl ca-certificates unzip && \
  apt-get clean && \
  rm -rf /var/lib/apt/lists/* && \
  if [ "$(uname -m)" = "aarch64" ]; then \
    curl -sSLO ${ZULU_URL} && \
    echo "${ZULU_SHA256}  ${ZULU_FILE}" | sha256sum --check - && \
    tar -xzf ${ZULU_FILE} -C /usr/local/ && \
    ln -s /usr/local/${ZULU_NAME} /usr/local/zulu17 ; \
  fi && \
# Install IB Gateway
# Use this instead of "RUN curl .." to install a local file:
#COPY ibgateway-${IB_GATEWAY_VERSION}-standalone-linux-x64.sh .
  curl -sSOL ${IB_GATEWAY_URL} && \
  curl -sSOL ${IB_GATEWAY_URL}.sha256 && \
  sha256sum --check ./${IB_GATEWAY_FILE}.sha256 &&\
  chmod a+x ./${IB_GATEWAY_FILE} && \
  if [ "$(uname -m)" = "aarch64" ]; then \
    app_java_home=/usr/local/zulu17 ./${IB_GATEWAY_FILE} -q -dir /root/Jts/ibgateway/${IB_GATEWAY_VERSION} ; \
  else \
    ./${IB_GATEWAY_FILE} -q -dir /root/Jts/ibgateway/${IB_GATEWAY_VERSION} ; \
  fi && \
  # Install IBC
  curl -sSOL ${IBC_URL} && \
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

ENV IB_GATEWAY_VERSION=10.48.1e
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
COPY --from=setup /usr/local/ /usr/local/
COPY --chown=${USER_ID}:${USER_GID} --from=setup /root/ ${HOME}

# Prepare system
RUN apt-get update -y && \
  apt-get upgrade -y && \
  apt-get install --no-install-recommends --yes \
  gettext-base socat xvfb x11vnc sshpass openssh-client sudo telnet && \
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

USER ${USER_ID}:${USER_GID}
WORKDIR ${HOME}

# Start run script
CMD ["/home/ibgateway/scripts/run.sh"]

LABEL org.opencontainers.image.source=https://github.com/dennisdeh/ib-gateway-docker
LABEL org.opencontainers.image.url=https://github.com/dennisdeh/ib-gateway-docker/pkgs/container/ib-gateway
LABEL org.opencontainers.image.description="Docker image with IB Gateway and IBC "
LABEL org.opencontainers.image.licenses="Apache License Version 2.0"
LABEL org.opencontainers.image.version=${IB_GATEWAY_VERSION}-${IB_GATEWAY_RELEASE_CHANNEL}
