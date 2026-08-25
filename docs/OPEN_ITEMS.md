# OPEN ITEMS

Things that are wrong and not yet fixed. Something examined and found correct or
deliberate belongs in `DECISIONS.md` instead.

*Last updated: 2026-08-25 — from the QA / adversarial QA sweep of that date.*

Verified clean in the same sweep, so nobody re-checks: **no secret has ever been
committed** on any branch (`.env`, `.env.bak`, `*.pem`, `ssh/`, `data/`, `keylock`
— 0 commits each, all refs); the full `pre-commit`
hook set is green tree-wide (after the repairs recorded under *High* below); the IB API
ports are bound to `127.0.0.1`; PR builds run with `push: false` and receive no
registry credentials; `bastion/sshd_config` is genuinely hardened (publickey-only,
`ForceCommand /usr/sbin/nologin`, `MaxSessions 0`, modern KEX/cipher/MAC lists).

## High

*All three high-severity findings from the 2026-08-25 sweep were fixed the same
day on branch `qa-high-fixes`. Kept here as a record of what changed and how it
was verified; delete once it has been on `master` for a while.*

### 1. CI proves nothing — the build check cannot fail — **FIXED**

`continue-on-error: true` on the `build` job in `.github/workflows/build.yml`
made the job report success whatever the build did. Removed, with a comment
saying why it must not come back, plus `timeout-minutes` and a least-privilege
`permissions:` block.

Nothing ran lint either, and the hook set turned out to be unrunnable:
`markdownlint` failed on ~200 `MD013` line-length violations in the generated
`README.md`, `dotenv-linter 0.5.0` crashed on Python 3.13 (`from typing.re
import Pattern`), and the `shellcheck`/`shfmt`/`hadolint` hooks needed binaries
nobody had installed. So the config was repaired first:

- `.markdownlint.yaml` disables `MD013` (generated, table-heavy README) and
  `MD033` (the logo needs an `<img>` with an explicit height);
- `bastion/README.md` fixed (fence/list spacing, a broken `#setup` anchor, two
  fences missing a language) — it had never been linted;
- `bastion/Dockerfile` gets an inline `hadolint ignore=DL3025`: the healthcheck
  needs bash `/dev/tcp` redirection, which JSON exec form cannot express;
- `dotenv-linter` bumped `0.5.0` → `0.9.0`;
- `shellcheck`, `shfmt` and `hadolint` switched to their `*-docker` variants, so
  the hooks need only Docker — which everyone here already has.

`.github/workflows/lint.yml` now runs `pre-commit run --all-files` on every push
and PR. **Verified 2026-08-25: all twelve hooks green tree-wide** — the first
time the declared hook set has passed on the whole repository.

### 2. `.env.bak` holds live credentials and is not gitignored — **FIXED**

`.gitignore` now covers `.env`, `.env.*`, `*.env` with `!.env-dist` /
`!*.env-dist`, and a `no-real-env-files` pre-commit hook (`language: fail`)
rejects any real env file even when force-added past `.gitignore`.

Verified 2026-08-25, both directions: `.env.bak` is ignored, and after
`git add -f .env.bak` the hook fails with an explanatory message; `.env-dist`
passes untouched.

### 3. Credential files are world-readable — **FIXED**

`chmod 600 .env .env.bak` in the deployment checkout (they are untracked, so
this is host state, not a commit). `cert.pem` is a public certificate and stays
`0644`; `key.pem` and `ssh/id_ed25519` were already `0600`.

## Medium

*Four of the five were fixed on 2026-08-25 (branch `qa-medium-fixes`). Only
item 7 is still open, because it needs a decision rather than a patch.*

### 4. IBC and the aarch64 JDK installed without verification — **FIXED**

`Dockerfile.template` now pins `ARG IBC_SHA256` and `ARG ZULU_SHA256` and checks
both before use, matching the treatment the IB Gateway installer already got.
Neither vendor publishes a checksum file (both probed 2026-08-25: 404), so the
digests are measured and pinned:

- `IBCLinux-3.24.1.zip` → `d99ee28c…88bb8`
- `zulu17.60.17-ca-fx-jre17.0.16-linux_aarch64.tar.gz` → `e74bcc2d…3b5d0`

The JDK branch also had `;` separators, so a failed download or extraction did
not stop the build; it is `&&`-chained now.

A pinned digest must move with `IBC_VERSION`, so
`.github/workflows/detect-ibc-release.yml` recomputes it when it opens a bump
PR. Verified 2026-08-25 by running that logic against the real 3.24.2 release:
it downloads, hashes, rewrites the `ARG` line and greps to confirm the rewrite.
The `sha256sum --check` form was proved both ways — `OK` on the genuine archive,
exit 1 on a byte-appended copy.

**In effect since 2026-08-25.** Both channels were regenerated on request the
same day (`./update.sh latest 10.48.1e`, `./update.sh stable 10.45.1g`), so the
verification is in `latest/Dockerfile` and `stable/Dockerfile` rather than
waiting for the next release. Both images were then built locally end to end,
each reporting `ibgateway-<version>-standalone-linux-x64.sh: OK` and
`IBCLinux-3.24.1.zip: OK`. This moved `stable` to IBC `3.24.1` — see
`DECISIONS.md` #12.

### 5. Workflows: no `permissions:`, untrusted input reaching `run:` — **FIXED**

Every job now declares least privilege: `contents: read` for the build and lint
jobs, `contents: write` + `pull-requests: write` for the two bots that push
branches and open PRs, `contents: read` + `packages: write` for publishing.

Every `${{ … }}` was moved out of `run:` bodies into `env:` and is referenced
quoted — audited to **zero** remaining interpolations inside any `run:` block.
Two boundary validations were added, which is the actual fix rather than
quoting alone:

- IB's `buildVersion` must match `^[0-9]+\.[0-9]+\.[0-9a-z]+$` or the run
  fails. It reaches shell, filenames and a branch name, so nothing else may
  enter.
- `publish.yml` refuses a tag whose second field is not `stable`/`latest`. That
  value selects the Docker build context, so a malformed tag previously
  published the wrong channel — or an empty context — silently.

### 6. Root compose silently dropped the bastion's security settings — **FIXED**

`docker-compose.yml` now passes `USER_SHELL`, `TOTP_ENABLED`, `TOTP_ISSUER`,
`TOTP_QR_ENCODE`, `CA_ENABLED`, `SSHD_HOST_CERT`, `SSHD_USER_CA` and
`BANNER_ENABLED` through to the bastion, mirroring `bastion/docker-compose.yml`.
Verified 2026-08-25 with `docker compose config`: the values now appear in the
service definition.

**The running `inv_bastion` is unaffected, and deliberately so.** It is started
from the Investio copy of this project (see `CLAUDE.md`), whose
`docker-compose.yml` still passes only `USERS` — checked 2026-08-25. The fix
here reaches it when Investio adopts this repository, or if the same change is
made there. The owner has asked that the container not be recreated.

### 7. `SSH_REMOTE_PORT` did the opposite of what the documentation said — **FIXED (documentation)**

`template_README.md` documented it as *"Remote port for ssh tunnel"*. In
`ssh -R bind:port:host:hostport` the **first** port is the one opened on the
server, and `run_ssh.sh` passes `API_PORT` there — so `SSH_REMOTE_PORT` is
really the *container-local* port the tunnel dials. `start_ssh()` defaults it to
`API_PORT`, which made the two readings coincide and hid the discrepancy.
`SSH_VNC_PORT` and `SSH_RDP_PORT` had the same inverted description.

Repaired on the documentation side by decision (2026-08-25), because the code
path is live here (`SSH_TUNNEL=yes`) and changing tunnel semantics to satisfy a
doc string risks the gateway's connectivity for no functional gain:

- all three table rows in `template_README.md` now say which side each port is
  on, and that setting `SSH_REMOTE_PORT` to "the port I want on the server"
  does not work;
- `run_ssh.sh` renames `_LOCAL_PORT`/`_REMOTE_PORT` to `_REMOTE_BIND_PORT`/
  `_LOCAL_TARGET_PORT`, matching ssh's own terminology, with the explanation at
  the line;
- `common.sh` comments corrected for the same three variables.

**Behaviour is unchanged, and that was verified rather than assumed:** the ssh
command string produced by the old and new scripts is byte-identical, both with
the default and with a custom `SSH_REMOTE_PORT=9999`:

```text
ssh -o ServerAliveInterval=20 -TNR 127.0.0.1:4002:localhost:9999  ibgateway@bastion
```

That line is also the clearest statement of the trap: the remote bind stays
`4002`; only the local target moved.

The scripts were copied into `latest/` and `stable/` directly rather than via
`update.sh`, to keep the deliberate version drift of `DECISIONS.md` #2 — see
`DECISIONS.md` #10.

### 8. The documented onboarding path did not work — **FIXED**

`.env-dist` gained every key `docker-compose.yml` reads (`CONTAINER_NAME`,
`CONTAINER_NAME_BASTION`, `PORT_HOST_*`, `SSH_LISTEN_PORT`, `BASTION_USERS`,
the bastion's TOTP/CA settings, `APT_PROXY`, `BASE_VERSION`, `IMAGE_VERSION`),
and `container_name` no longer defaults to the empty string Docker rejects.

Verified 2026-08-25 — the exact command that used to fail:

```text
$ docker compose --env-file .env-dist config -q
$ echo $?
0
```

The live deployment is unaffected: with the real `.env` the same file still
resolves to `inv_gateway`/`inv_bastion` on ports 9899/9898/9897 and bastion
22222, confirmed by `docker compose config`.

### 16. `docker compose build --pull tws` cannot work on a clean machine

*Found 2026-08-25, while verifying the merged compose file. Not caused by that
merge — it predates it.*

`Dockerfile.tws` starts `FROM ghcr.io/dennisdeh/ib-gateway:${IB_VERSION}` with
`IB_VERSION` defaulting to the channel's gateway version, so the TWS build needs
that **exact tag** present. `ghcr.io/dennisdeh/ib-gateway` is not anonymously
pullable — `docker pull ghcr.io/dennisdeh/ib-gateway:10.48.1e` and `:10.47.1c`
both returned `error from registry: denied` on 2026-08-25 — so `--pull` fails at
the first stage with `403 Forbidden` from the ghcr token endpoint.

Building the gateway first is not enough either: `docker compose build
ib-gateway` tags it `:latest`, not `:10.48.1e`. The workaround used to verify
the merge was

```bash
docker compose build --pull ib-gateway
docker tag ghcr.io/dennisdeh/ib-gateway:latest ghcr.io/dennisdeh/ib-gateway:10.48.1e
docker compose build tws          # no --pull
```

after which the TWS build completed. A real fix is either making the package
public, or giving the `tws` service a `build.args` entry so `IB_VERSION` can be
pointed at a locally built tag.

## Low / accepted risk (record the decision if you accept it)

| # | item | note |
|---|---|---|
| 9 | `echo "ibgateway ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers` in `Dockerfile.template` | The unprivileged container user can become root at will. With `START_SCRIPTS`/`X_SCRIPTS`/`IBC_SCRIPTS` executing arbitrary mounted shell, there is no privilege boundary inside the container. Inherited from upstream. |
| 10 | `x11vnc … -passwd "$VNC_SERVER_PASSWORD"` in `run.sh` | Password visible in the container's process list; `-passwdfile`/`-rfbauth` avoid it. VNC auth is weak by design (8 effective chars). Mitigated by the `127.0.0.1` publish. |
| 11 | TWS image default RDP password is `abc` (`${PASSWD:-abc}` in `start_session.sh`) | Safe only because the `tws` service in `docker-compose.yml` binds RDP to `127.0.0.1`. Anyone publishing 3389 more widely inherits a known password. |
| 12 | `run_ssh.sh` runs `bash -c "ssh ${_OPTIONS} … ${_USER_TUNNEL}"` | Re-parses operator-supplied env values through a shell. Not a vulnerability (operator-controlled) but any metacharacter executes. |
| 13 | Dependabot watches `/stable` and `/latest` only | Those are *generated*; a base-image bump there is overwritten by the next `update.sh`. The real sources (`Dockerfile.template`, `Dockerfile.tws.template`) and `/bastion` are unwatched, as is the floating tag `lscr.io/linuxserver/rdesktop:ubuntu-xfce`. |
| 14 | `PWD` is defined inside `.env` | Renaming or moving the repository silently breaks every bind mount while compose still validates. |
| 15 | `PORT_HOST_SSH_BASTION=2222` in `.env` is referenced nowhere | The bastion actually publishes `SSH_LISTEN_PORT=22222` on **0.0.0.0** — every other port here is pinned to `127.0.0.1`. Reachability is the point of a bastion, but a firewall rule written for 2222 protects nothing. |
| 16 | `.pre-commit-config.yaml` revs are pinned to 2024 releases and no ecosystem updates them | e.g. `pre-commit-hooks v4.6.0`, `hadolint v2.12.1-beta`. Dependabot has no `pre-commit` entry. |
