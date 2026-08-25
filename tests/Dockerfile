# Runner for tests/container: bats plus a docker client, so the tests can start
# sibling containers through the mounted docker socket. tests/unit needs none of
# this and runs on the stock bats image.

FROM bats/bats:1.14.0
# Alpine package versions are not stable enough to pin here, and this image is
# a local test runner rather than anything shipped.
# hadolint ignore=DL3018
RUN apk add --no-cache docker-cli
