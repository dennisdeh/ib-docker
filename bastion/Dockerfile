ARG BASE_VERSION=resolute
FROM ubuntu:${BASE_VERSION}

ARG BASE_VERSION
ARG APT_PROXY
# The image's own version, independent of any IB Gateway release. This
# declaration is what `publish-bastion.yml` reads to tag the published image,
# the same way publish.yml reads ENV IB_GATEWAY_VERSION from a channel
# Dockerfile - so this line is the one place to bump it, and a push to master
# touching this directory publishes whatever it says. It was previously used by the LABEL below
# without ever being declared, which made every image report version
# "-resolute".
ARG IMAGE_VERSION=2604.03
SHELL ["/bin/bash", "-o", "pipefail", "-c"]
# apt is retried because ports.ubuntu.com - the aarch64 mirror, and only it -
# intermittently serves an index referencing a .deb its pool 404s on, which
# fails the emulated leg with apt's exit 100. This image is built for arm64 by
# build.yml and publish-bastion.yml, so it has the same exposure as the gateway
# and went without the mitigation until 2026-08-30. See docs/OPEN_ITEMS.md #24.
# hadolint ignore=DL3008,SC2028
RUN if [ -n "$APT_PROXY" ]; then \
      echo 'Acquire::http { Proxy "'$APT_PROXY'"; }'  \
      | tee /etc/apt/apt.conf.d/01proxy \
    ;fi && \
    for attempt in 1 2 3 4 5; do \
      apt-get update && \
      apt-get upgrade -yq && \
      DEBIAN_FRONTEND=noninteractive apt-get install --no-install-recommends -y \
      openssh-server libpam-google-authenticator qrencode util-linux && \
      break; \
      [ "$attempt" = 5 ] && exit 1; \
      echo ".> apt failed, dropping the index and retrying (attempt ${attempt})"; \
      rm -rf /var/lib/apt/lists/*; \
      sleep "$((attempt * 20))"; \
    done && \
    rm -rf /var/lib/apt/lists/* && \
    mkdir -p /run/sshd && \
    if id ubuntu >/dev/null 2>&1; then \
      userdel -rf ubuntu \
    ;fi && \
    if ! getent group ssh-bastion >/dev/null 2>&1; then \
      groupadd -g 59999 ssh-bastion; \
    fi && \
    cp /etc/ssh/sshd_config /etc/ssh/sshd_config-dist && \
    awk '$5 >= 3071' /etc/ssh/moduli > /etc/ssh/moduli.secure && \
    mv /etc/ssh/moduli.secure /etc/ssh/moduli && \
    cp /etc/pam.d/sshd /etc/pam.d/sshd.back && \
    grep -v "include common-auth" /etc/pam.d/sshd.back > /etc/pam.d/sshd && \
    echo -e "# TOTP\nauth required pam_google_authenticator.so \nauth"\
    "required pam_permit.so" >> /etc/pam.d/sshd && \
    rm -f /etc/ssh/ssh_host_*key*

COPY sshd_config /etc/ssh/
COPY entrypoint.sh /
COPY provision.sh /
COPY sshd_config_d.sh /
COPY bastion_banner.txt /

# The healthcheck needs bash's /dev/tcp redirection, which JSON exec form
# cannot express, so DL3025 does not apply here.
# hadolint ignore=DL3025
HEALTHCHECK --interval=30m --timeout=15s --start-period=10s \
  CMD timeout 1 bash -c '</dev/tcp/0.0.0.0/22 && echo "SSH Bastion running" || echo "Port is closed"' || echo "Connection timeout"

ENTRYPOINT ["/entrypoint.sh"]
CMD ["/usr/sbin/sshd", "-D", "-e"]

# ghcr.io links a package to a repository through this label, so it names the
# repository the image is built and published from - not the project it was
# forked from, which bastion/README.md credits.
LABEL org.opencontainers.image.source=https://github.com/dennisdeh/ib-docker
LABEL org.opencontainers.image.description="OpenSSH Bastion container"
LABEL org.opencontainers.image.licenses=Apache-2.0
LABEL org.opencontainers.image.version=${IMAGE_VERSION}-${BASE_VERSION}
