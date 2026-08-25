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

### 4. IBC and the aarch64 JDK are installed without verification

`Dockerfile.template` verifies the IB Gateway installer
(`curl … .sha256 && sha256sum --check`) but downloads **`IBCLinux-${IBC_VERSION}.zip`
and the Zulu JDK tarball with no checksum and no signature**. A compromised IBC
release asset, or a MITM on the CDN, puts arbitrary code into a published image
that logs into a brokerage account. The same gap exists in
`Dockerfile.tws.template` by inheritance.

*Fix:* pin and verify a sha256 for both, the way the gateway installer already is.

### 5. GitHub Actions: no `permissions:` blocks, and untrusted input reaches `run:`

- **None of the five workflows declares `permissions:`**, so each job gets the
  repository default `GITHUB_TOKEN` scope. `detect-releases.yml` and
  `detect-ibc-release.yml` push branches, create releases and open PRs with it.
- Third-party strings are interpolated **unquoted into shell** in ~15 places:
  `steps.version.outputs.build_version` comes from
  `download2.interactivebrokers.com/.../version.json`, and
  `steps.ibc_version.outputs.IBC_LATEST` comes from `gh release list -R IbcAlpha/IBC`
  — i.e. from a release *tag name* in a repository we do not control. Both then
  land in `export LATEST_VERSION=${{ … }}`, `t_branch='update-…-${{ … }}'`,
  `git commit -m '… ${{ … }}'` and similar.

Likelihood is low (both sources are reputable and TLS-protected) but the impact
is a token with write access executing attacker-chosen shell.

*Fix:* add least-privilege `permissions:` to every workflow, and pass every
`${{ }}` through `env:` then reference `"$VAR"` quoted inside `run:`.

### 6. Root compose silently drops the bastion's security settings

`docker-compose.yml` gives the `bastion` service **only** `USERS`.
`bastion/entrypoint.sh` reads `TOTP_ENABLED`, `CA_ENABLED`, `BANNER_ENABLED`,
`SSHD_HOST_CERT` and `SSHD_USER_CA` **at runtime**; `bastion/docker-compose.yml`
passes all of them, the root file passes none. So `TOTP_ENABLED=yes` set in
`.env` and started from the repo root does nothing, with no warning.

Currently `TOTP_ENABLED=no` and `CA_ENABLED=no`, so nothing is exposed today —
the failure mode is "I turned on MFA and it silently didn't apply".

*Fix:* mirror the environment block from `bastion/docker-compose.yml`.

### 7. `SSH_REMOTE_PORT` does the opposite of what the documentation says

`template_README.md` documents it as *"Remote port for ssh tunnel"*. In
`image-files/scripts/run_ssh.sh` the tunnel is

```bash
ssh -TNR 127.0.0.1:${_LOCAL_PORT}:localhost:${_REMOTE_PORT}   # _LOCAL_PORT=$API_PORT, _REMOTE_PORT=$SSH_REMOTE_PORT
```

In `-R bind:port:host:hostport`, the **first** port is what is opened on the
remote server. So `API_PORT` is the remote port and `SSH_REMOTE_PORT` is the
*container-local* target. `start_ssh()` defaults `SSH_REMOTE_PORT` to `API_PORT`,
which makes the two readings identical and hides the bug — until someone sets a
custom value, at which point the tunnel binds the wrong port remotely and
forwards to a port nothing listens on, while reporting success.

*Fix:* decide which behaviour is intended, then correct either the code or the
documentation and the variable names (`_LOCAL_PORT`/`_REMOTE_PORT` are swapped
relative to ssh's own terminology). This is a good first `bats` regression test.

### 8. The documented onboarding path does not work

`CONTRIBUTING.md` says `cp .env-dist .env` then `docker-compose build`. Verified
2026-08-25:

```
$ docker compose --env-file .env-dist config -q
validating docker-compose.yml: services.bastion.container_name '' does not match pattern …
```

`.env-dist` is missing `CONTAINER_NAME`, `CONTAINER_NAME_BASTION`,
`SSH_LISTEN_PORT`, `PORT_HOST_TWS_LIVE/PAPER`, `PORT_HOST_VNC_SERVER`,
`PORT_HOST_RDP`, `APT_PROXY`, `BASE_VERSION`, `BASTION_USERS`, `USER_SHELL`,
`TOTP_*`, `CA_ENABLED`, `SSHD_*` — all of which the fork's `docker-compose.yml`
now requires. Separately, `container_name: ${CONTAINER_NAME:-}` can never be
valid with its own default: an empty container name fails Docker's name pattern,
so the variable is mandatory while looking optional.

*Fix:* extend `.env-dist` to cover every key the root compose file reads, and
either give `container_name` a real default or drop the `:-` .

## Low / accepted risk (record the decision if you accept it)

| # | item | note |
|---|---|---|
| 9 | `echo "ibgateway ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers` in `Dockerfile.template` | The unprivileged container user can become root at will. With `START_SCRIPTS`/`X_SCRIPTS`/`IBC_SCRIPTS` executing arbitrary mounted shell, there is no privilege boundary inside the container. Inherited from upstream. |
| 10 | `x11vnc … -passwd "$VNC_SERVER_PASSWORD"` in `run.sh` | Password visible in the container's process list; `-passwdfile`/`-rfbauth` avoid it. VNC auth is weak by design (8 effective chars). Mitigated by the `127.0.0.1` publish. |
| 11 | TWS image default RDP password is `abc` (`${PASSWD:-abc}` in `start_session.sh`) | Safe only because `tws-docker-compose.yml` binds RDP to `127.0.0.1`. Anyone publishing 3389 more widely inherits a known password. |
| 12 | `run_ssh.sh` runs `bash -c "ssh ${_OPTIONS} … ${_USER_TUNNEL}"` | Re-parses operator-supplied env values through a shell. Not a vulnerability (operator-controlled) but any metacharacter executes. |
| 13 | Dependabot watches `/stable` and `/latest` only | Those are *generated*; a base-image bump there is overwritten by the next `update.sh`. The real sources (`Dockerfile.template`, `Dockerfile.tws.template`) and `/bastion` are unwatched, as is the floating tag `lscr.io/linuxserver/rdesktop:ubuntu-xfce`. |
| 14 | `PWD` is defined inside `.env` | Renaming or moving the repository silently breaks every bind mount while compose still validates. |
| 15 | `PORT_HOST_SSH_BASTION=2222` in `.env` is referenced nowhere | The bastion actually publishes `SSH_LISTEN_PORT=22222` on **0.0.0.0** — every other port here is pinned to `127.0.0.1`. Reachability is the point of a bastion, but a firewall rule written for 2222 protects nothing. |
| 16 | `.pre-commit-config.yaml` revs are pinned to 2024 releases and no ecosystem updates them | e.g. `pre-commit-hooks v4.6.0`, `hadolint v2.12.1-beta`. Dependabot has no `pre-commit` entry. |
