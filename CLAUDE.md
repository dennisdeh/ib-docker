# CLAUDE.md

*How to work in this repository. What the code is, the code says; this file says
what the code cannot — which command to trust, what "done" means, and which
plausible-looking action is the wrong one.*

*Last updated: 2026-08-25*

---

## Project overview

A fork of [gnzsnz/ib-gateway-docker](https://github.com/gnzsnz/ib-gateway-docker)
that builds Docker images running Interactive Brokers Gateway (and TWS) headless,
driven by [IBC](https://github.com/IbcAlpha/IBC) under Xvfb, with `socat` and/or
an SSH tunnel exposing the IB API port outside the container. The published
images are `ghcr.io/dennisdeh/ib-gateway` and `ghcr.io/dennisdeh/tws-rdesktop`.

This checkout is **both** the source of those images **and the live deployment**:
`docker-compose.yml` here runs `inv_gateway` + `inv_bastion` as part of a wider
trading stack. Two different meanings of "done" therefore apply — see *Testing*.

- **Primary language / runtime:** Bash + Dockerfile. No application code.
- **Entry point (build):** `./update.sh <channel> <version>` regenerates a channel.
- **Entry point (run):** `docker compose up -d` from the repo root, reading `.env`.
- **Central concept:** the **channel** — `stable` or `latest`, one IB Gateway
  version each. Every generated artefact is per-channel; `image-files/` is the
  single per-channel-agnostic source.

## Environment

No language runtime, no virtualenv. What you need is Docker and the repo root:

```bash
cd "/mnt/data/Documents/Coding/00_My GitHub Repositories/ib-gateway-docker"
docker compose config   # validates .env + compose wiring without starting anything
```

- All scripts and compose files resolve paths relative to **the repo root**, and
  several volume mounts use `$PWD` — which is read from `.env`, not from the
  shell. Running compose from a subdirectory silently mounts the wrong paths.
- **Not installed on this machine:** `gh`, `pre-commit`, `bats`, and none of the
  linter binaries. The hook set is configured to need only Docker (every linter
  uses its `*-docker` variant), so `pre-commit` itself is the one thing to add:
  `python3 -m venv .venv && .venv/bin/pip install pre-commit`. **There is no
  `gh` — never plan a step around it.** PRs are opened in the browser, or the
  bot opens them from CI.
- The remote is `origin` → `https://github.com/dennisdeh/ib-gateway-docker.git`.
  Upstream (`gnzsnz`) is **not** configured as a remote; add it explicitly if a
  sync is requested.

### What a fresh clone does not have

Everything below is untracked or gitignored and must be supplied out-of-band:

| path | what it is | how to get it |
|---|---|---|
| `.env` | credentials + ports for **both** the gateway and the bastion service | `cp .env-dist .env`, then fill in; `.env-dist` records the key names |
| `ssh/` | keypair + `known_hosts`, bind-mounted to `/home/ibgateway/.ssh` | generated once; required whenever `SSH_TUNNEL=yes` |
| `data/` | bastion's read-only `/etc/passwd`, `/etc/shadow`, `/etc/ssh`, `/home` | `bastion/provision.sh`, run inside the bastion image (see `docs/RUNBOOK.md`) |
| `config/` | X/xrdp runtime state | created by the container |
| `key.pem`, `cert.pem`, `keylock` | TLS material | supplied out-of-band |

The bastion validates a hash of the provisioned `data/etc` at startup
(`data/etc/ssh/bastion_provisioned_hash.sum`). Editing those files by hand
without re-provisioning makes the container refuse to start — that is the
feature, not a bug.

> Real credential files (`.env`, `.env.bak`, …) are covered by `.gitignore` and
> by the `no-real-env-files` pre-commit hook, which fails even on a `git add -f`
> *(both verified 2026-08-25)*. `.env-dist` stays tracked. Belt and braces are
> there because the cost of one mistake is broker credentials in a public repo —
> so still **stage files by name, never `git add -A` / `git add .`**. `.idea/`
> is only partially ignored and has no such guard.

## Key conventions

- **`image-files/` is the only place to edit scripts and configs.** `latest/`
  and `stable/` are *generated*: `update.sh` copies `image-files/.` into the
  channel directory and `envsubst`s `Dockerfile.template` /
  `Dockerfile.tws.template` into it. An edit made in `latest/scripts/run.sh` is
  destroyed by the next release run, silently.
- **`update.sh` updates ONE channel.** After changing anything in
  `image-files/`, run it for **both**: `./update.sh stable <stable-version>` and
  `./update.sh latest <latest-version>`, reusing each channel's current version
  (`grep 'ENV IB_GATEWAY_VERSION=' stable/Dockerfile`). Doing only one leaves
  the other channel running last month's scripts.
- **`README.md` is generated from `template_README.md`** by
  `.github/workflows/detect-releases.yml` (`envsubst` over `$LATEST_VERSION`,
  `$STABLE_VERSION`, `$IBC_VERSION`, …). **Edit `template_README.md`.** A change
  written into `README.md` survives until the next IB Gateway release, then
  vanishes without a trace.
- **The IBC version legitimately differs between the templates and the channel
  Dockerfiles.** `detect-ibc-release.yml` bumps `IBC_VERSION` in the two
  templates only and deliberately does *not* run `update.sh`; the next gateway
  release propagates it. As of 2026-08-25: templates `3.24.1`, `latest/`
  `3.24.0`, `stable/` `3.23.0`. This is by design — do not "fix" it by running
  `update.sh` unless a version bump is what you were actually asked for.
- **Ports: the number the host publishes is the socat port, not the API port.**
  `set_ports()` in `image-files/scripts/common.sh` binds IB Gateway's API to
  4002 (paper) / 4001 (live) on the container's own loopback, and socat forwards
  it to 4004 / 4003, which is what compose publishes. Locally that is
  `9898 → 4004` (paper) and `9899 → 4003` (live). A client pointed at container
  port 4002 will never connect; that is correct behaviour.
- **`SSH_REMOTE_PORT`, `SSH_VNC_PORT` and `SSH_RDP_PORT` name the port *inside
  the container*, not on the server.** In `ssh -R bind:port:host:hostport` the
  first port is the remote one, and `run_ssh.sh` always passes `API_PORT` (or
  5900 / 3389) there. Setting `SSH_REMOTE_PORT` to "the port I want on the
  bastion" silently forwards to a dead local port while reporting success. The
  default makes the two coincide, which is why this hides so well.
- **`file_env VAR`** lets `VAR_FILE` supply a secret from a file, and **errors
  out if both `VAR` and `VAR_FILE` are set**. `unset_env` then clears the value
  before IBC starts, so a password read from a file is not in the environment of
  child processes. Preserve that pairing when touching credential handling.
- **`CUSTOM_CONFIG=yes` disables all templating** — `apply_settings()` returns
  early and neither `config.ini` nor `jts.ini` is regenerated from env vars. A
  bug report of "my env var is ignored" is usually this.
- **`jts.ini` is written only if absent.** An existing settings file is never
  rewritten, so `TIME_ZONE` changes do not take effect on a container with a
  persisted `TWS_SETTINGS_PATH` until that file is deleted.
- **`TRADING_MODE=both` starts two IBC instances** with `_live` / `_paper`
  suffixes appended to `IBC_INI` and `TWS_SETTINGS_PATH`, 15 s apart, and forces
  `SSH_VNC_PORT`/`SSH_REMOTE_PORT` empty for the second. Code that assumes one
  IBC process per container is wrong.
- `.env` here is a **superset** serving both `docker-compose.yml` and
  `bastion/docker-compose.yml`. A key that looks unused by the gateway is
  probably the bastion's.

---

## Git workflow

- Feature work happens in **worktrees**:
  `git worktree add ../wt-<name> -b <name>`. When working in a worktree, edit
  files **in the worktree path only** — never the main checkout. The main
  checkout is the live deployment; a stray edit there changes what is running.
- Every task ends with the full flow unless told otherwise: commit, push,
  fast-forward merge into `master`, push, delete the local **and** remote
  branch, remove the worktree.
- **Never merge until the verification the task asked for has actually finished
  and reported PASS.** Not on an in-flight build, not on a backgrounded one.
- If a worktree command fails, run `git worktree list` and `git worktree prune`
  before retrying. Do not retry blindly.
- **Stage by name, never `-A`/`.`** — see the `.env.bak` warning above.
- Branch names matching `update-*-to-*` and `IBC-update*` belong to the release
  bots and are **excluded from the CI build trigger** in
  `.github/workflows/on-push-n-pr.yml`. Do not name a human branch that way — it
  will silently skip CI.
- Do not delete remote `update-*`/`IBC-update*` branches as cleanup: the
  detection workflows test for their existence to avoid opening duplicate PRs.

## Testing

There is no automated test suite yet. Building one is an open item — see
`docs/OPEN_ITEMS.md`. Until it exists, "verified" means the three checks below,
run **in the foreground with a bounded timeout**, and **reported with what
actually ran**. "Lint passes" without naming the files checked is not a report.

### 1. Lint — fast, offline, always

**The canonical command is `pre-commit run --all-files`.** It is what
`.github/workflows/lint.yml` runs on every push and PR, so a local pass and a
green check mean the same thing. Every linter hook uses its `*-docker` variant,
so Docker is the only prerequisite besides `pre-commit` itself.

```bash
python3 -m venv .venv && .venv/bin/pip install pre-commit   # once
.venv/bin/pre-commit run --all-files
```

Verified green tree-wide on 2026-08-25 — all twelve hooks. If you cannot install
`pre-commit`, these equivalents were verified clean the same day:

```bash
docker run --rm -v "$PWD:/mnt" -w /mnt koalaman/shellcheck:stable \
  image-files/scripts/*.sh image-files/tws-scripts/*.sh update.sh
docker run --rm -v "$PWD:/work" -w /work mvdan/shfmt:latest -d image-files/ update.sh
docker run --rm -i hadolint/hadolint:v2.12.1-beta hadolint - < Dockerfile.template
docker run --rm -v "$PWD:/workdir" -w /workdir davidanson/markdownlint-cli2:latest \
  CONTRIBUTING.md template_README.md
```

- Lint `image-files/`, not `latest/`/`stable/` — the copies will be regenerated.
- **`--all-files` means all *tracked* files.** A file you have created but not
  yet `git add`ed is invisible to every hook, so a green run says nothing about
  it. Stage new files *before* the verification run, or you will push work that
  fails its own lint job — which is exactly how `CLAUDE.md` and `docs/` first
  landed on `master` red.
- Some hooks **rewrite files** (`trailing-whitespace`, `end-of-file-fixer`).
  Check `git status` after a run; a "Passed" second run may only mean the first
  one already edited the tree.
- `MD013` (line length) is off in `.markdownlint.yaml` on purpose: `README.md` is
  generated and mostly wide option tables. Do not reflow it by hand.
- **Do not reorder `.env-dist`** to satisfy a stricter `dotenv-linter` than the
  pinned hook. It churns a file kept aligned with upstream for no gain.

### 2. Build — offline, slow

```bash
timeout 1800 docker compose build --pull ib-gateway   # builds ./latest
docker build -t ib-gateway:check ./stable             # the other channel
```

Report the outcome. A build that was not run is not a build that passed.

### 3. Runtime — requires the live stack, so **ask first**

**`inv_gateway` and `inv_bastion` are running and other services depend on
them** (`inv_visualisation`, and anything talking to `127.0.0.1:9898`).

- **Never `docker compose up/down/restart` the real services without explicit
  go-ahead in the current message.** Approval given for one change does not
  carry to the next.
- Prefer an isolated check: a separate compose project name and unused ports, so
  the running gateway is untouched.
- A real login consumes an IB session. `EXISTING_SESSION_DETECTED_ACTION` and
  IB's one-session-per-account rule mean a second login can **disconnect the
  running gateway mid-session**. Treat starting a second gateway against the
  same credentials as a production action.
- `.env` currently has `TRADING_MODE=paper` and `READ_ONLY_API=no` — orders
  would be accepted. Confirm the mode before anything that can place one.
- Non-code failure modes to check before assuming a bug: IB's nightly restart
  window (`AUTO_RESTART_TIME`), IB server maintenance, an expired 2FA prompt, a
  stale SSH tunnel, IB's weekend downtime.

### The suite to build

When the suite lands it should be **`bats-core` + Docker smoke tests**:

- Unit level: `bats` over the pure functions in `image-files/scripts/common.sh`
  (`set_ports`, `file_env`, `unset_env`, `set_java_heap`) — sourced directly, no
  container, no network, no credentials. This is the fast offline selector.
- Smoke level: build the image, start it under a **throwaway compose project on
  unused ports**, and assert the published socat port accepts a TCP connection
  and the log reaches a known IBC state. Credentials required; keep it opt-in
  and never pointed at the live account by default.
- Run `bats` itself as a container (`bats/bats:latest`) — it is not installed.

## Debugging

- **State the root cause with evidence — a log line, a reproducing command, a
  failing check — before editing anything.** A patch without a stated cause is a
  guess with a diff attached.
- **Every fix ships a test demonstrated to FAIL against the unfixed code.** Once
  `bats` exists, that means a red run pasted into the report. Until then, it
  means a reproduction command whose output changes across the fix, shown both
  ways.
- Container-side logs first: `docker logs inv_gateway` (read-only, safe, no
  restart). IBC's own log is inside the container under the IBC path.
- **`pkill` in this repo is scoped, and must stay that way.** `stop_ibc()` in
  `run.sh` kills `Xvfb`, `socat`, `ssh` **inside the container**, where that is
  safe. On the **host** those same patterns match your own tooling and other
  containers' helper processes. Never run a bare `pkill socat` / `pkill -f ssh`
  on the host to clean up after a test.
- **A scoped grep answers a scoped question.** Version strings, port numbers and
  env-var names exist in `image-files/`, both channel directories,
  `template_README.md`, `README.md`, both compose files, `.env-dist` and the
  workflows. When correcting one, `rg -n "<value>"` over the **whole tree**
  before declaring it fixed — and remember `README.md` is generated, so fixing
  it there fixes nothing.
- Do not treat a prior session's notes or `docs/DECISIONS.md` as an exclusion
  list. They are point-in-time records. Judge every path on today's source.

## Deployment and CI

- CI does not run on `update-*-to-*` or `IBC-update*` branches (by design); it
  runs on every other branch and on PRs to `master`.
- Publishing is tag-driven: pushing `v*` triggers `publish.yml`, which derives
  the channel from the **second dash-separated field of the tag name** and now
  refuses anything that is not `stable`/`latest`. Tag as `v<version>-<channel>`.
- Every workflow job declares least-privilege `permissions:`. If a step starts
  failing on a token scope, widen *that job*, not the repository default.
- `detect-releases.yml` and `detect-ibc-release.yml` run daily at 06:00 UTC and
  open their own PRs. Before hand-bumping a version, check whether a bot branch
  or open PR already does it — that duplicate-avoidance check is what
  `verify_branch` in `detect-ibc-release.yml` exists for.
- Release artefacts (the IB installers) are attached to **this fork's** GitHub
  releases and downloaded by `Dockerfile.template` from `dennisdeh/…`, with a
  `sha256sum --check`. A build failing at the checksum step usually means the
  release asset is missing, not that the Dockerfile is wrong.
- **IBC and the aarch64 Zulu JDK ship no checksum file, so their digests are
  pinned in `Dockerfile.template` as `IBC_SHA256` / `ZULU_SHA256`.** `IBC_SHA256`
  must move with `IBC_VERSION` — `detect-ibc-release.yml` recomputes it — and
  `ZULU_SHA256` must move with `ZULU_NAME`. Changing either version without its
  digest fails the build at verification, which is the intended behaviour.

---

## Documentation

Two locations, and the split is strict:

- **`docs/`** — the small fixed set of standing documents listed below. Do not
  add a file here without asking.
- **`README.md` / `template_README.md` / `CONTRIBUTING.md`** — the public,
  user-facing story. Remember `README.md` is generated.

### Where a fact goes

| the fact | the file |
|---|---|
| something is wrong and not yet fixed | `docs/OPEN_ITEMS.md` |
| examined, found correct or deliberate, not to be re-raised | `docs/DECISIONS.md` |
| how to run, provision, restart or recover the local stack | `docs/RUNBOOK.md` |
| how a user configures the image | `template_README.md` |
| how a contributor changes the image | `CONTRIBUTING.md` |

`OPEN_ITEMS` vs `DECISIONS` is *"is something wrong?"*, not *"is something worth
doing?"*. A finding that turns out to be by design moves to `DECISIONS.md`
**with its reasoning**, so the next session does not reopen it.

### Rules

- **Update the existing file; do not create a parallel one.**
- **State a fact once.** If it belongs in two places, put it where the question
  is answered and link from the other — a fact stated twice goes stale once.
- **Anchor to symbol names, never line numbers** — `set_ports()` in
  `common.sh`, not `common.sh:112`. This applies to code comments too.
- **Date every measurement and every version claim.** "as of 2026-08-25:
  templates 3.24.1, latest/ 3.24.0" stays checkable; a bare number does not.
- **Never write branch, worktree or merge state as present tense.** Write "at
  the time of writing, nothing was merged", or give the date.
- **Every section carries `*Last updated: YYYY-MM-DD*`**, refreshed when *its*
  content changes — not when the file is touched for something else.
- **Changing behaviour in `image-files/` means updating every document that
  describes it, in the same commit** — `template_README.md` first, then anything
  else that names the variable or the port.
- **Prose lives in docs, not in code comments.** A comment says *what* and
  points; the docs say *why*, with the evidence. Keep the one-sentence trap at
  the line being edited; move measurements, incidents and reasoning to `docs/`.
  **Never delete such a comment — relocating is the only way to shorten it.**
- Do not number steps in comments and do not restate the next line.

## Before investigating, check the docs

Read `docs/OPEN_ITEMS.md` and `docs/DECISIONS.md` before starting any
investigation from scratch — then check their vintage. Also check upstream
(`gnzsnz/ib-gateway-docker`) issues before concluding a bug is ours; most of
this code is inherited.

---

## Rules vs. checks — how to grow this file

In order of value:

1. **A mechanical check** — a `bats` test, a lint rule, a CI gate. Every check
   should exist because a defect got through.
2. **A rule in this file**, when a check is impossible or not yet worth writing.
3. **Nothing.** A rule nobody follows is worse than no rule: it trains the
   reader that this file is decoration.

Several rules above are candidates for promotion to checks — a test that
`image-files/` and both channel directories agree; a check that `README.md` is
byte-identical to `envsubst` over `template_README.md`; a `.gitignore` test that
no `*.env*` variant is stageable. Write the check, then delete the rule.

**Prune as well as add.** Delete a rule when its check exists, when the thing it
guards is gone, or when it has never once been the thing that went wrong.
