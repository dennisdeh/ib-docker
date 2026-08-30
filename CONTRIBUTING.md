# Contributing to ib-docker

First off, thank you for considering contributing to this project!
Your help is appreciated.

This document provides guidelines for contributing to the project. Please feel
free to propose changes to this document in a pull request.

## How to Contribute

1. **Create an Issue:** Before starting any work, please open an issue to
   discuss the bug or feature request. This allows us to give you feedback
   and prevent duplicated work. There are templates for
   [bug reports](.github/ISSUE_TEMPLATE/bug_report.md) and
   [feature requests](.github/ISSUE_TEMPLATE/feature_request.md).

2. **Fork the Repository:** Fork the project to your own GitHub account.

3. **Create a Branch:** Use a descriptive name, like `fix/my-bug` or
   `feature/new-feature`. Avoid `update-*-to-*` and `IBC-update*` — those
   belong to the release bots and are **excluded from the CI build trigger**,
   so a branch named that way silently skips its checks.

## What is where

This repository builds three images — `ghcr.io/dennisdeh/ib-gateway`,
`ghcr.io/dennisdeh/tws-rdesktop` and `ghcr.io/dennisdeh/bastion` — and one
`docker-compose.yml` defines all three. `ib-gateway` and `tws` sit behind
Compose profiles that `IB_APP` selects between; the bastion has no profile and
always starts.

| path | what it is |
| --- | --- |
| `image-files/` | **the development directory.** All scripts and config templates live here. |
| `Dockerfile.template`, `Dockerfile.tws.template` | the two image definitions, one IB version per channel |
| `latest/`, `stable/` | **generated.** `update.sh` writes them; never edit them by hand. |
| `bastion/` | the ssh bastion image, with its own README and provisioning script |
| `deploy/provision.sh` | sets a host up from the published images; emits its own compose file |
| `template_README.md` | **the README source.** `README.md` is generated from it. |
| `tests/` | the `bats` suites, the runner image they use, and the link checker |
| `docs/` | `RUNBOOK.md`, `DECISIONS.md`, `OPEN_ITEMS.md` — see *Documentation* below |

Two of those are worth repeating, because both failure modes are silent:

- **`latest/` and `stable/` are build outputs.** An edit made in
  `latest/scripts/run.sh` is destroyed by the next release run, with no warning
  and no conflict.
- **`README.md` is generated** from `template_README.md` by
  `.github/workflows/detect-releases.yml`. A change written into `README.md`
  survives until the next IB Gateway release, then vanishes.

## Development Setup

You need Docker. Every lint hook uses a `*-docker` variant, so `pre-commit`
itself is the only other thing to install:

```bash
python3 -m venv .venv
.venv/bin/pip install pre-commit
.venv/bin/pre-commit install     # optional: run the hooks on every commit
```

## Making Changes

1. **Edit `image-files/`** (or a template, or `bastion/`) — not the channel
   directories.

2. **Regenerate both channels.** `update.sh` takes one channel at a time, so
   run it twice, reusing each channel's current version. Doing only one leaves
   the other running last month's scripts:

    ```bash
    grep 'ENV IB_GATEWAY_VERSION=' latest/Dockerfile   # read the versions first
    grep 'ENV IB_GATEWAY_VERSION=' stable/Dockerfile

    ./update.sh latest <latest-version>
    ./update.sh stable <stable-version>
    ```

    `update.sh` also regenerates the channel Dockerfiles from the templates, so
    it carries across whatever `IBC_VERSION` the template currently holds. If
    you only meant to change a script, check `git diff` for a version bump you
    did not intend — see `docs/DECISIONS.md` #2 and #10.

3. **Update the documentation in the same commit.** Changing a variable, a port
   or a default without changing `template_README.md` is an incomplete change;
   see *Documentation* below for which file a given fact belongs in.

4. **Build and test locally.**

    ```bash
    cp .env-dist .env     # once; then fill it in
    chmod 600 .env        # cp leaves it at your umask, usually world-readable
    nano .env

    # Name the service: docker-compose.yml holds both ib-gateway and tws
    # behind Compose profiles, and a bare `build` only builds the one IB_APP
    # selects.
    docker compose build --pull ib-gateway   # or: bastion
    docker compose build tws                 # no --pull here - see below
    ```

    `tws` builds `FROM` the gateway image, and `--pull` means "fetch the base
    from the registry every time". Since the packages went public that
    succeeds — and quietly builds against whatever the last release published
    instead of the gateway you just built. Build `ib-gateway` first, then `tws`
    without `--pull`. See `docs/DECISIONS.md` #30.

    A build on an x86 machine only proves `linux/amd64`. CI builds both, and
    the two take genuinely different paths — IB ships a separate installer per
    architecture. To reproduce the other leg, register the emulator once
    (`docker run --privileged --rm tonistiigi/binfmt --install arm64`) and pass
    `--platform linux/arm64`.

5. **Stage files by name.** Not `git add -A`, not `git add .`. Real credential
   files are gitignored *and* rejected by a pre-commit hook, but the cost of
   one mistake here is broker credentials in a public repository.

## Testing

Three checks, all runnable offline except the last:

```bash
.venv/bin/pre-commit run --all-files   # lint - what .github/workflows/lint.yml runs
tests/run.sh unit                      # the offline bats suite - what test.yml runs
python3 tests/links.py                 # every link and URL in every tracked file
```

`bats` is not needed on the host — `tests/run.sh` runs it as a container.
`tests/run.sh container` starts throwaway containers from images you have
already built; it needs no credentials and never contacts IB, and it is not run
in CI (`docs/DECISIONS.md` #11). `tests/run.sh all` runs both.

Two things about `pre-commit run --all-files` that have caught people out:

- **`--all-files` means all *tracked* files.** A file you have created but not
  yet `git add`ed is invisible to every hook, so a green run says nothing about
  it. Stage new files *before* the verification run.
- **Some hooks rewrite files** (`trailing-whitespace`, `end-of-file-fixer`).
  Check `git status` afterwards; a clean second run may only mean the first one
  edited your tree.

**A fix ships with a test that was demonstrated to fail without it.** Mutate the
thing the test covers — flip the port, delete the guard — watch it go red, then
revert the mutation. A test that has only ever been green proves the harness
runs, not that it measures anything.

## Documentation

`README.md` and `CONTRIBUTING.md` are the public story; `docs/` is the internal
one, and it is a fixed set of files rather than a folder to add to.

| the fact | the file |
| --- | --- |
| something is wrong and not yet fixed | `docs/OPEN_ITEMS.md` |
| examined, found correct or deliberate, not to be re-raised | `docs/DECISIONS.md` |
| how to run, provision, restart or recover a stack | `docs/RUNBOOK.md` |
| how a user configures the image | `template_README.md` |
| how the ssh bastion is built, provisioned and used | `bastion/README.md` |
| how a contributor changes the image | this file |

State a fact once and link to it from anywhere else that needs it — a fact
stated twice goes stale once. Anchor to symbol names (`set_ports()` in
`common.sh`) rather than line numbers, and date every measurement and version
claim, so a later reader can tell what is still checkable.

## Submitting a Pull Request

1. Push your branch to your fork.
2. Open a Pull Request against `master`.
3. Summarise the change and link the issue.
4. Make sure the lint and test checks are green — they run on every push and
   on every PR.

## How a Release Happens

You do not need to do anything to publish a new IB Gateway or TWS version, and
you should not tag one by hand.

A scheduled workflow asks Interactive Brokers every morning what the current
build is for each channel. When it has moved, that run attaches the installers
to a release here, regenerates the channel with `update.sh`, rewrites
`README.md` from `template_README.md`, opens the version-bump pull request, and
publishes the images to `ghcr.io/dennisdeh` — `ib-gateway` and `tws-rdesktop`
tagged with the version, the `major.minor` series and the channel name, and
`bastion` tagged with the `ARG IMAGE_VERSION` its own Dockerfile declares. The
bump PR is still reviewed and merged by a human; the images do not wait for it.

The bastion has no IB version of its own, so bumping it means editing that one
`ARG` — it is what both `.github/workflows/publish-bastion.yml` and
`deploy/provision.sh` read. That workflow also has its own trigger: a push to
`master` touching `bastion/**` publishes the image, so a bastion fix does not
wait for an IB Gateway release.

The same applies to `image-files/`: your change reaches the published images at
the next IB Gateway release, when `update.sh` regenerates the channels. To
publish it sooner, run `publish.yml` from the Actions tab and pick a channel.

A separate daily workflow watches [IBC](https://github.com/IbcAlpha/IBC) and
opens its own PR against the two templates. It deliberately does **not** run
`update.sh`, so the channels pick the new IBC up at their next gateway release
— which is why the two channels can show different IBC versions in the README's
Supported Tags table, and why that is not a defect.

If you are changing how a host is set up rather than what is in the image, the
deployment path is `deploy/provision.sh` and the *Deploying* section of
`template_README.md`. Both are covered by tests: `tests/unit/provision.bats`
offline, and `tests/container/bastion_hash.bats` against a real bastion.

Thank you for your contribution!
