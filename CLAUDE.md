# CLAUDE.md

*How to work in this repository. What the code is, the code says; this file says
what the code cannot — which command to trust, what "done" means, and which
plausible-looking action is the wrong one.*

*Last updated: 2026-08-30*

---

## Project overview

Builds Docker images running Interactive Brokers Gateway (and TWS) headless,
driven by [IBC](https://github.com/IbcAlpha/IBC) under Xvfb, with `socat` and/or
an SSH tunnel exposing the IB API port outside the container. The published
images are `ghcr.io/dennisdeh/ib-gateway`, `ghcr.io/dennisdeh/tws-rdesktop` and
`ghcr.io/dennisdeh/bastion`.

**The repository is `ib-docker`.** It was `ib-gateway-docker` until 2026-08-27;
one `docker-compose.yml` now runs the gateway, TWS and the bastion behind
profiles, so a name that mentioned only the gateway had stopped being true.
**The rename was of the repository, not of the packages** — the three image
names above are unchanged, and `Dockerfile.tws` still opens `FROM
ghcr.io/dennisdeh/ib-gateway`. One string deliberately keeps the old spelling
and must survive any future sweep: `gnzsnz/ib-gateway-docker`, the project this
was forked from, which is not ours to rename. *(It was two until 2026-08-30;
the Investio vendored copy has since been renamed too — see below.)*
`tests/unit/naming.bats` fails on any further occurrence of the
**owner-qualified** form — this owner's name, a slash, the old repository name
— which is what a URL, a remote or a `uses:` is built from and the one that
breaks a build. It does not match the bare name, which still appears in prose
describing the rename; matching that would only train people to ignore the
check. (Spelling the qualified form out here would fail that very test, which
is how this sentence was first written and caught.)

**This project is independent, not a tracking fork.** It began as a fork of
`gnzsnz/ib-gateway-docker`, which `LICENSE` and the README credit, and that is
the whole of the relationship: no remote, no sync, no check, no schedule and no
decision here depends on that repository. Judge every question on this tree and
on the real upstreams the image actually consumes — Interactive Brokers'
installer servers, `IbcAlpha/IBC`, `lscr.io/linuxserver/rdesktop` and Azul.
*(Decoupled on the owner's instruction, 2026-08-25.)*

**This checkout is the source of the images, not the running deployment.**
`inv_gateway` and `inv_bastion` are started from a vendored copy of this project
inside the Investio repository, at
`/mnt/data/Documents/Investio/modules/p00_apps/ib-docker`. Investio is expected
to consume this repository later; until it does, a change merged here reaches
the running stack only when someone updates that copy. *(Stated by the owner and
confirmed from the containers' compose labels, 2026-08-25. **That copy has since
been renamed** — this file said `ib-gateway-docker` and described it as
deliberately keeping the old name until 2026-08-30, when the running containers'
`com.docker.compose.project.config_files` label was re-read and gave
`.../p00_apps/ib-docker/docker-compose.yml`; the old path no longer exists.)*

> **Compose commands run here still hit those live containers.** This
> repository's `docker-compose.yml` and the Investio copy both declare
> `name: inv_ibkr`, and Compose identifies a project by that name,
> not by directory — so `docker compose ps` in this repo lists the running
> `inv_gateway`/`inv_bastion` (verified 2026-08-25), and `down`, `restart` or
> `up -d` would act on them. **Never run a compose lifecycle command here.**
> `docker compose config` is safe; it starts nothing.

- **Primary language / runtime:** Bash + Dockerfile. No application code.
- **Entry point (build):** `./update.sh <channel> <version>` regenerates a channel.
- **Entry point (run):** `docker compose up -d` — but see the warning above; that
  is how the *consumer* of this repository starts it, not something to run here.
- **Central concept:** the **channel** — `stable` or `latest`, one IB Gateway
  version each. Every generated artefact is per-channel; `image-files/` is the
  single per-channel-agnostic source.

## Environment

No language runtime, no virtualenv. What you need is Docker and the repo root:

```bash
cd "/mnt/data/Documents/Coding/00_My GitHub Repositories/ib-gateway-docker"
docker compose config   # validates .env + compose wiring without starting anything
```

**The checkout directory is still named `ib-gateway-docker`**, though the
repository is `ib-docker`; renaming a clone is not part of renaming a
repository. This file said `ib-docker` here until 2026-08-30, so the first
command in it did not work. *(Checked against the filesystem that day.)*

- All scripts and compose files resolve paths relative to **the repo root**.
  The volume mounts are relative (`./ssh`), which compose resolves against the
  **project directory** — the compose file's own directory unless
  `--project-directory` says otherwise — so they no longer depend on where you
  run it from. They used `${PWD}` until 2026-08-30; that interpolates from the
  **shell**, not from `.env`, because compose gives the environment precedence
  and a shell always exports `PWD`. See `docs/OPEN_ITEMS.md` #14.
- **Not installed on this machine:** `gh`, `pre-commit`, `bats`, and none of the
  linter binaries. `tests/run.sh` runs `bats` as a container for you. The hook set is configured to need only Docker (every linter
  uses its `*-docker` variant), so `pre-commit` itself is the one thing to add:
  `python3 -m venv .venv && .venv/bin/pip install pre-commit`. **There is no
  `gh` — never plan a step around it.** PRs are opened in the browser, or the
  bot opens them from CI.
- The remote is `origin` → `git@github.com:dennisdeh/ib-docker.git`,
  and it is the only one. It was HTTPS until 2026-08-25; over HTTPS every push
  prompted for a username and failed in a non-interactive session. The machine's
  SSH key already authenticates to GitHub as `dennisdeh`, so pushes need no
  token and no `gh`. **Do not add the repository this was forked from as a
  remote and do not sync from it** — see *Project overview*.

### What a fresh clone does not have

Everything below is untracked or gitignored and must be supplied out-of-band:

| path | what it is | how to get it |
|---|---|---|
| `.env` | credentials + ports for **both** the gateway and the bastion service | `cp .env-dist .env`, then fill in; `.env-dist` records the key names |
| `ssh/` | keypair + `known_hosts`, bind-mounted to `/home/ibgateway/.ssh` | generated once; required whenever `SSH_TUNNEL=yes` |
| `data/` | bastion's read-only `/etc/passwd`, `/etc/shadow`, `/etc/ssh`, `/home` | `bastion/provision.sh`, run inside the bastion image (see `docs/RUNBOOK.md`) |
| `config/` | X/xrdp runtime state | created by the container |
| `key.pem`, `cert.pem`, `keylock` | TLS material | supplied out-of-band |

The bastion validates a hash of the provisioned `data/etc` at startup.
`check_provision()` runs `sha256sum -c` over
`data/etc/ssh/bastion_provisioned_hash`, the list of per-file digests;
`bastion_provisioned_hash.sum` beside it is a digest *of that list*, not the
file being checked. Editing any covered file by hand without re-provisioning
makes the container refuse to start — that is the feature, not a bug.

> Real credential files (`.env`, `.env.bak`, …) are covered by `.gitignore` and
> by the `no-real-env-files` pre-commit hook, which fails even on a `git add -f`
> *(both verified 2026-08-25)*. `.env-dist` stays tracked. Belt and braces are
> there because the cost of one mistake is broker credentials in a public repo —
> so still **stage files by name, never `git add -A` / `git add .`**. Neither
> `.idea/` nor `.claude/` has such a guard, but both are now ignored wholesale
> *(2026-08-26)*; `.idea/` used to name six specific files, so every new IDE file
> reappeared as untracked noise. `.claude/*` is written with the glob, not the
> bare directory, because git cannot re-include a file whose parent directory is
> excluded — which is what lets `!.claude/settings.json` work while
> `settings.local.json` and `worktrees/` stay ignored.

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
- **Three images, and everything that runs is one of them.**
  `ghcr.io/dennisdeh/ib-gateway`, `tws-rdesktop` and `bastion` are all built
  and published here; every compose file in the tree builds all three from this
  checkout, and `deploy/provision.sh` pulls only those three. The base images
  are the deliberate exception — `ubuntu`, `lscr.io/linuxserver/rdesktop` for
  the TWS desktop, and `bats/bats` for the test runner, which never ships.
  `tests/unit/images.bats` holds that inventory: a fourth image in a compose
  file, a service with no build context, or a new third-party base all fail it.
  See `docs/DECISIONS.md` #27.
- **`README.md` is generated from `template_README.md`** by
  `.github/workflows/detect-releases.yml`, an `envsubst` over exactly seven
  variables: `$LATEST_VERSION`, `$LATEST_MINOR`, `$LATEST_IBC`,
  `$STABLE_VERSION`, `$STABLE_MINOR`, `$STABLE_IBC` and `$BASTION_VERSION`.
  **Edit `template_README.md`.** A change written into `README.md` survives
  until the next IB Gateway release, then vanishes without a trace.
  `tests/unit/naming.bats` reproduces the substitution and diffs the result, so
  an edit made in the wrong file fails in the same commit. Anything else of the
  `${...}` form is left literal on purpose — the README documents
  `${IB_GATEWAY_VERSION}`, `${IB_APP}` and `${TWS_SETTINGS_PATH}` as text the
  reader types.
- **The IBC and bastion versions in that table are read per image**, from
  `latest/Dockerfile`, `stable/Dockerfile` and `bastion/Dockerfile` — not once
  from `Dockerfile.template`. One number across all rows was wrong for `stable`
  the moment the channels diverged, which is the normal state described in the
  next rule. See `docs/DECISIONS.md` #26.
- **The IBC version can legitimately differ between the templates and the
  channel Dockerfiles.** `detect-ibc-release.yml` bumps `IBC_VERSION` in the two
  templates only and deliberately does *not* run `update.sh`; the next gateway
  release propagates it. So a gap between `Dockerfile.template` and
  `latest/`/`stable/` is expected, not a defect — do not "fix" it by running
  `update.sh` unless a version bump is what you were actually asked for. As of
  2026-08-30 the templates and `latest/` read IBC `3.24.2` while `stable/` reads
  `3.24.1`, which is exactly that expected gap; the gateway versions are
  `10.50.1e` (latest) and `10.45.1j` (stable). `tests/unit/docs.bats` fails when
  a gateway version named here is not one the tree builds.
- **One compose file, two applications.** `docker-compose.yml` holds an
  `ib-gateway` service and a `tws` service behind Compose profiles of the same
  name; `IB_APP` in `.env` feeds `COMPOSE_PROFILES` and decides which one is
  created. `bastion` carries no profile, so it always starts. A bare
  `docker compose build` builds only the selected service — naming a service
  enables its profile for that command, so `docker compose build tws` works
  whatever `IB_APP` says *(verified 2026-08-25)*.
- **There are two compose stories, and only one of them is in this repository.**
  `docker-compose.yml` here *builds* from `latest/`/`stable/` and is how the
  image is developed. `deploy/provision.sh` *emits* a second compose file that
  *pulls* the published image, holds no build context and no `$PWD`, and lives
  outside the checkout with the keys and secrets it provisions — that is the
  deployment story. Do not merge the two: the in-repo file's `name: inv_ibkr`
  is the live project, which is exactly why the emitted one must never use it.
  `provision.sh` refuses that name and refuses to run while `inv_gateway` /
  `inv_bastion` are up. See `docs/RUNBOOK.md`.
- **In `authorized_keys`, `permitopen` and `permitlisten` do not constrain each
  other.** The first governs `-L`, the second `-R`, and `restrict` followed by
  `port-forwarding` re-enables *both* directions. A key that names only one of
  them leaves the other wide open — a client able to `-L` to the API could also
  bind ports on the bastion, and the gateway able to `-R` could also reach
  anything the bastion can see. Set both on every key, pinning the unused
  direction to `127.0.0.1:1`. Measured against a live bastion on 2026-08-27,
  after shipping it wrong in both directions; pinned by
  `tests/unit/provision.bats`.
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
- **`CUSTOM_CONFIG=yes` disables all templating** — `apply_settings()` in
  `common.sh` wraps its whole body in `if [ "$CUSTOM_CONFIG" != "yes" ]`, so
  neither `config.ini` nor `jts.ini` is regenerated from env vars. A
  bug report of "my env var is ignored" is usually this.
- **`jts.ini` is written only if absent.** An existing settings file is never
  rewritten, so `TIME_ZONE` changes do not take effect on a container with a
  persisted `TWS_SETTINGS_PATH` until that file is deleted.
- **`TRADING_MODE=both` starts two IBC instances** with `_live` / `_paper`
  suffixes appended to `IBC_INI` and `TWS_SETTINGS_PATH`, 15 s apart, and forces
  `SSH_VNC_PORT`/`SSH_REMOTE_PORT` empty for the second. Code that assumes one
  IBC process per container is wrong.
- `.env` here is a **superset** serving `docker-compose.yml` — all three of its
  services — and `bastion/docker-compose.yml`. A key that looks unused by the
  gateway is probably the bastion's or the TWS service's; the TWS host ports are
  `PORT_HOST_RDESKTOP_*` and `PORT_HOST_RDP`, the gateway's `PORT_HOST_TWS_*`
  and `PORT_HOST_VNC_SERVER`.

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
- **The two detection workflows dedupe differently, and only one of them looks
  at branches** *(re-read from the workflows 2026-08-27; the old blanket rule
  here said both did, which was wrong)*:
  - `detect-releases.yml` checks whether the **GitHub release** for that
    version exists — `gh release list | grep "<channel>@<version>"`. Branches
    are irrelevant to it, so an `update-*-to-*` branch may be deleted freely.
    The flip side is that once that release exists the branch is **never
    regenerated**, so a superseded one is dead weight and should go.
  - `detect-ibc-release.yml` checks for the **branch** and for an open PR. A
    live `IBC-update*` branch must therefore stay until its PR is merged or
    closed — but a merged one is free to delete, and deleting a stale one is
    the way to make the workflow reopen it correctly. Leaving one in place is
    what shipped IBC `3.24.2` with `3.24.1`'s digest; see `OPEN_ITEMS.md` #21.

## Testing

"Verified" means the checks below, run **in the foreground with a bounded
timeout**, and **reported with what actually ran**. "Tests pass" without counts,
or "lint passes" without naming what was checked, is not a report.

### 1. Lint — fast, offline, always

**The canonical command is `pre-commit run --all-files`.** It is what
`.github/workflows/lint.yml` runs on every push and PR, so a local pass and a
green check mean the same thing. Every linter hook uses its `*-docker` variant,
so Docker is the only prerequisite besides `pre-commit` itself.

```bash
python3 -m venv .venv && .venv/bin/pip install pre-commit   # once
.venv/bin/pre-commit run --all-files
```

Verified green tree-wide on 2026-08-29, at the revisions `pre-commit
autoupdate` set that day — all twelve hooks. If you cannot install
`pre-commit`, these equivalents were verified clean the same day:

```bash
docker run --rm -v "$PWD:/mnt" -w /mnt koalaman/shellcheck:stable \
  image-files/scripts/*.sh image-files/tws-scripts/*.sh update.sh
docker run --rm -v "$PWD:/work" -w /work mvdan/shfmt:latest -d image-files/ update.sh
docker run --rm -i hadolint/hadolint:v2.15.1 hadolint - < Dockerfile.template
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
  pinned hook. The file is grouped by service and by concern, which is what
  makes it readable as the key list for two compose files; alphabetical order
  would scatter each service's keys for no gain the pinned hook asks for.

### 2. Build — offline, slow

```bash
timeout 1800 docker compose build --pull ib-gateway   # builds ./latest
docker build -t ib-gateway:check ./stable             # the other channel

# tws builds FROM the gateway image; the compose defaults point it at the
# :latest tag the line above produces, so no registry access is needed
timeout 2400 docker compose build tws
```

Report the outcome. A build that was not run is not a build that passed.

**A build on this machine only proves `linux/amd64`.** CI builds both
architectures, and the two take genuinely different paths through
`Dockerfile.template` — IB ships a separate installer per architecture. To
reproduce the CI leg, register the emulator once
(`docker run --privileged --rm tonistiigi/binfmt --install arm64`, undo with
`--uninstall`), then:

```bash
timeout 2400 docker build --platform linux/arm64 -t ib-gateway:arm64 ./latest
```

Expect roughly 25 minutes under emulation, most of it the IB installer.

### 3. Runtime — the live containers are not ours to touch

**`inv_gateway` and `inv_bastion` belong to the Investio checkout** (see
*Project overview*), are running, and other `inv_*` services on this machine
depend on them — anything talking to `127.0.0.1:9898`. Ask `docker ps` rather
than trusting a list here: this file named `inv_visualisation` until 2026-08-30,
by which time no container of that name existed.

- **Never run `docker compose up/down/restart` in this repository.** The shared
  `name: inv_ibkr` means those commands reach the live containers even though
  this is a different directory. This is not a "confirm first" case; the owner
  has said the containers are managed elsewhere.
- An isolated check is the only runtime option from here: `-p` with a throwaway
  project name **and** different container names and ports, so nothing collides
  with the running stack.
- A real login consumes an IB session. `EXISTING_SESSION_DETECTED_ACTION` and
  IB's one-session-per-account rule mean a second login can **disconnect the
  running gateway mid-session**. Treat starting a second gateway against the
  same credentials as a production action.
- `.env` currently has `TRADING_MODE=paper` and `READ_ONLY_API=no` — orders
  would be accepted. Confirm the mode before anything that can place one.
- Non-code failure modes to check before assuming a bug: IB's nightly restart
  window (`AUTO_RESTART_TIME`), IB server maintenance, an expired 2FA prompt, a
  stale SSH tunnel, IB's weekend downtime.

### 4. The `bats` suite

```bash
tests/run.sh              # unit — offline, no credentials, seconds
tests/run.sh container    # needs a built gateway image; starts a throwaway one
tests/run.sh all
```

`bats` is not installed here either, so `tests/run.sh` runs it as a container.
**`tests/run.sh unit` is the fast offline selector** and the one CI runs
(`.github/workflows/test.yml`).

- `tests/unit/` sources the pure functions directly, plus `compose.bats`, which
  reads `docker-compose.yml` and `.env-dist` as text, and `workflows.bats`,
  which does the same for the release automation in `.github/workflows/` — no
  container, no network, no credentials. 117 tests as of 2026-08-30, a count
  `tests/unit/docs.bats` holds to the suite.
- **`workflows.bats` also *runs* the shell those workflows contain.** Its
  `step_script()` lifts a step's `run:` body out of the YAML and executes it
  under `bash -e`, which is the shell a step with no `defaults.run.shell` gets,
  so `publish.yml`'s channel and version resolution is exercised rather than
  pattern-matched. Add a case there when changing what a step's shell decides;
  a text assertion can show only that code is present, never that it fires.
- `tests/container/` starts throwaway containers from existing images.
  `socat.bats` runs **only** the port-forwarding half of `run.sh` — it never
  starts IBC, so it needs no credentials and never contacts IB, which also
  means it can never generate a failed login against the account.
  `bastion_hash.bats` provisions a throwaway `data/`, tampers with
  `sshd_config.d` and asserts the bastion refuses to start; set `BASTION_IMAGE`
  to test an image other than `ghcr.io/dennisdeh/bastion:latest` — `tests/run.sh`
  forwards that variable, which it did not until 2026-08-29, so setting it used
  to do nothing and the suite silently tested the published image. 13 tests as
  of 2026-08-29, and **not run in CI** — see `DECISIONS.md` #11.
- Nothing in the suite touches `inv_gateway`/`inv_bastion`.

### 5. Links in the documentation

```bash
python3 tests/links.py     # needs the network; not part of tests/run.sh
```

Resolves every anchor offline and fetches every URL in **every tracked file**,
in three passes: markdown links, the URLs **inside fenced code blocks** — where
a `git clone` of a repository that does not exist had been hiding — and, since
2026-08-28, the URLs in every other tracked text file, which is to say the ones
in code comments. A comment citing an issue or a manual page is documentation
too, and nothing else reads it: the rename rewrote an upstream issue link in
`run_tws.sh` into this project's own tracker, where it 404s, and only a
markdown checker could miss that. It skips URLs holding a `${...}` placeholder
(templates the reader substitutes) and `starchart.cc`, which answers 400 to any
automated request, `torvalds/linux` included; a trailing `$` is trimmed, since
in source it is a regex anchor rather than part of the URL.

Run it after anything that renames a repository or moves a heading: a rename
leaves links that still resolve to a **wrong** page rather than a 404, so
nothing else catches them.

Two traps, both of which cost a debugging round already:

- **bats re-sources a test file in a new process for every test**, so `$$` and
  anything derived from it differ between `setup_file` and the tests. Use a
  constant name for a shared container.
- **`docker exec` against a container that never started also fails**, so a
  negative assertion passes for the wrong reason. `assert_container_running`
  exists for that; call it in every container test.

When adding a test, mutate the code it covers and watch it go red before
trusting it — see *Debugging*.

## Debugging

- **State the root cause with evidence — a log line, a reproducing command, a
  failing check — before editing anything.** A patch without a stated cause is a
  guess with a diff attached.
- **Every fix ships a test demonstrated to FAIL against the unfixed code**, and
  a new test must be shown red before it is trusted. Mutate the thing it covers
  — flip the port, delete the guard — run the suite, paste the red line, revert
  the mutation with `git checkout --`. A test that has only ever been green
  proves the harness runs, not that it measures anything.
- Container-side logs first: `docker logs inv_gateway` (read-only, safe, no
  restart). IBC's own log is inside the container under the IBC path.
- **`pkill` in this repo is scoped, and must stay that way.** `stop_ibc()` in
  `run.sh` kills `Xvfb`, `socat`, `ssh` **inside the container**, where that is
  safe. On the **host** those same patterns match your own tooling and other
  containers' helper processes. Never run a bare `pkill socat` / `pkill -f ssh`
  on the host to clean up after a test.
- **A scoped grep answers a scoped question.** Version strings, port numbers and
  env-var names exist in `image-files/`, both channel directories,
  `template_README.md`, `README.md`, `docker-compose.yml`, `.env-dist` and the
  workflows. When correcting one, `rg -n "<value>"` over the **whole tree**
  before declaring it fixed — and remember `README.md` is generated, so fixing
  it there fixes nothing.
- Do not treat a prior session's notes or `docs/DECISIONS.md` as an exclusion
  list. They are point-in-time records. Judge every path on today's source.

## Deployment and CI

- CI does not run on `update-*-to-*` or `IBC-update*` branches (by design); it
  runs on every other branch and on PRs to `master`.
- **A new IB Gateway version publishes itself.** `detect-releases.yml` polls IB
  daily, and for a channel that moved it attaches the installers to a release
  here, runs `update.sh`, regenerates `README.md`, opens the bump PR — and then
  **calls `publish.yml`**, which pushes `ib-gateway` and `tws-rdesktop` to
  `ghcr.io/dennisdeh` tagged `<version>`, `<major.minor>` and `<channel>`.
  Nobody has to merge or tag for the images to appear. *(In effect 2026-08-26.)*
  - **`bastion` is published by `publish-bastion.yml`**, tagged with the
    `ARG IMAGE_VERSION` its own Dockerfile declares — it carries no IB version,
    so an IB tag on it would mean nothing. That is the one line to bump, and it
    is what that workflow and `deploy/provision.sh` both read. All three images
    are published so a host can be provisioned without a checkout to build from.
    **It has its own trigger**: a push to `master` touching `bastion/**`, so a
    fix there no longer waits for an unrelated IB release. `publish.yml` also
    calls it, which is what refreshes the image against its Ubuntu base. An
    unbumped `IMAGE_VERSION` overwrites its tag — right for a base refresh,
    wrong for a behaviour change. *(2026-08-27, own trigger 2026-08-30; see
    `DECISIONS.md` #22 and `OPEN_ITEMS.md` #31.)*
  - The images are built from the **bot's own commit**, not from `master` — see
    `docs/DECISIONS.md` #14 for why, and for why it is a `workflow_call` rather
    than a pushed `v*` tag.
  - One IB version drives **both** images: `update.sh` renders `Dockerfile.tws`
    from the same `$VERSION`, so there is no separate TWS version to detect.
  - IBC bumps do **not** publish, and that is deliberate — `detect-ibc-release.yml`
    touches only the templates, so no channel image changes. See `DECISIONS.md` #2.
- Publishing is *also* tag-driven, for a release by hand: pushing `v*` triggers
  `publish.yml`, which derives the channel from the **second dash-separated
  field of the tag name** and refuses anything that is not `stable`/`latest`.
  Tag as `v<version>-<channel>`. A `workflow_dispatch` on `publish.yml` is the
  third way in — pick a channel, leave the version blank to take it from
  `<channel>/Dockerfile`.
- **`publish.yml` refuses to tag an image with a version it does not contain.**
  It compares the version it is about to publish against
  `ENV IB_GATEWAY_VERSION=` in the channel Dockerfile it is building and fails
  on a mismatch. That is the one publishing mistake nothing downstream can see.
- Docker Hub is a mirror and is skipped when `DOCKERHUB_USERNAME` /
  `DOCKERHUB_TOKEN` are unset; ghcr.io is never optional.
- **All three packages are public** — measured anonymously on 2026-08-29, see
  `docs/DECISIONS.md` #32. Pulling them needs no ghcr.io login, and
  `tests/unit/images.bats` fails on any file that says otherwise. The
  workflows that build the TWS image keep their ghcr.io login and their
  `packages: read` (`packages: write` when publishing) — including the caller,
  since a called workflow cannot hold a permission its caller withheld —
  because `Dockerfile.tws` starts `FROM` the gateway image and a version that
  has **never been published** still cannot be built that way, which is why
  `publish.yml` pushes the gateway *before* it builds TWS. See
  `docs/DECISIONS.md` #30 for the local build.
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
- **IBC ships no checksum file, so its digest is pinned in
  `Dockerfile.template` as `IBC_SHA256`,** and it must move with `IBC_VERSION`
  — `detect-ibc-release.yml` recomputes it. Changing the version without the
  digest fails the build at verification, which is the intended behaviour.
  **That recompute lives inside the PR-creating step, which is skipped when the
  bot branch already exists**, so a branch opened by an older run is never
  regenerated — which is how IBC `3.24.2` reached `master` with `3.24.1`'s
  digest on 2026-08-27. A *Verify the pinned IBC digest* step now runs on every
  daily run outside every conditional, and `tests/unit/dockerfile.bats` pins the
  version↔digest pairing offline. If a bot branch is stale, **delete that one
  branch** and let the workflow reopen it — the rule against deleting
  `update-*`/`IBC-update*` branches is about not doing it as routine cleanup.
  See `docs/OPEN_ITEMS.md` #21.
- **Each channel needs a release asset per architecture.** The build picks
  `…-standalone-linux-arm.sh` on aarch64 and `…-x64.sh` elsewhere, so a channel
  pinned to a version whose GitHub release carries only the x64 asset cannot
  build `linux/arm64` at all. `detect-releases.yml` uploads both
  (`archs="x64 arm"`); a few releases from before that change carry the x64
  asset only. **`PLATFORMS` is declared three times and all three must agree** —
  in `build.yml`, `publish.yml` and `publish-bastion.yml`. If they drift, CI
  passes and the release then fails on the platform only one of them builds;
  `tests/unit/workflows.bats` fails on that, and on `linux/arm64` being dropped.
  Both channels are on versions whose releases carry both assets, re-checked
  against the releases API on 2026-08-30 (`10.50.1e` latest, `10.45.1j`
  stable). See `docs/OPEN_ITEMS.md` #18.

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
investigation from scratch — then check their vintage. Every bug found here is
ours to fix; do not go looking for it in the repository this was forked from,
and do not treat that repository's behaviour as evidence about ours. Its CI
carries `continue-on-error: true`, so a green badge there means nothing.

---

## Rules vs. checks — how to grow this file

In order of value:

1. **A mechanical check** — a `bats` test, a lint rule, a CI gate. Every check
   should exist because a defect got through.
2. **A rule in this file**, when a check is impossible or not yet worth writing.
3. **Nothing.** A rule nobody follows is worse than no rule: it trains the
   reader that this file is decoration.

Several rules above are candidates for promotion to checks — a test that
`image-files/` and both channel directories agree; a `.gitignore` test that no
`*.env*` variant is stageable. Write the check, then delete the rule.

*The README check on that list was written on 2026-08-27 and made exact on
2026-08-28 (`tests/unit/naming.bats`), so it is struck off rather than left
here as a standing wish.*

**Prune as well as add.** Delete a rule when its check exists, when the thing it
guards is gone, or when it has never once been the thing that went wrong.
