# OPEN ITEMS

Things that are wrong and not yet fixed. Something examined and found correct or
deliberate belongs in `DECISIONS.md` instead.

*Last updated: 2026-08-30 — items 28, 29 and 30 added and fixed the same day,
30 in a second pass after it was found while verifying the first, and item 9
closed on the owner's decision. On
2026-08-29: item 16 and the fork-PR limit below rewritten once
the ghcr.io packages turned out to be public (`DECISIONS.md` #32). Before that,
on 2026-08-28: the summary and renumbering, then items 13 and 25
fixed, item 26 found, and item 27 fixed by merging the
`claude/github-actions-issues` branch, over the course of that day. Items 1-16 come from the QA / adversarial QA sweep of
2026-08-25; item 22 from wiring release detection to publication on 2026-08-26;
items 19-21 from 2026-08-27, while writing `deploy/provision.sh` and bumping
IBC. Reorganised on 2026-08-28: the summary below was added, and three item
numbers that had been used twice were made unique.*

**Numbers are identifiers, not an ordering.** They are cited from `CLAUDE.md`,
from three workflows and from the test suite, so a fixed item keeps its number
where it is rather than being renumbered or deleted. Most of what follows is
therefore a record of something already repaired; the table below is what is
actually outstanding.

## Still open, as of 2026-08-30

| # | item | where | why it is still here |
|---|---|---|---|
| 14 | `PWD` is defined inside `.env` | Low | Compose reads `.env` from the project directory but does not set `PWD` from it, so the bind mounts need the value written down. Removing it means changing every mount to a relative path, which changes behaviour for anyone running compose from elsewhere. Worth doing deliberately, not as a drive-by. |
| 24 | the `linux/arm64` `apt-get` leg fails while Ubuntu is mid-publication — mitigated, not cured | Medium | The cause is upstream: Canonical publishes an index before the `ports.ubuntu.com` pool has the package. The retry loop already turns it from a failed release into a slower one. Curing it means pinning or mirroring the archive, which is a much larger change than the fault deserves. |

Fixed on 2026-08-29, each with a test shown red against the unfixed code:
**#10** (VNC password out of the process list), **#11** (the public RDP default
is now announced), **#12** (no shell re-parse of operator values), **#15** (the
dead `.env` key, and a check that no key is dead), **#23** (hook revisions),
**#26** (`CA_ENABLED` refuses to be a no-op). **#16** moved to
`DECISIONS.md` #30 — the part that remains is by design.

Fixed on 2026-08-30, each with a test shown red first: **#28** (the two licence
labels, which had each other's licence), **#29** (`bastion/.env` inside the
bastion build context) and **#30** (the gateway's version label, which named no
channel). **#9** was closed the same day, but by a decision rather than a
finding: it had been waiting on one since 2026-08-25. **#31** was found while
verifying #9 and closed after it.

Everything else below is marked **FIXED** or **MITIGATED** and is kept as the
record of what changed and how it was verified.

Verified clean in the same sweep, so nobody re-checks: **no secret has ever been
committed** on any branch (`.env`, `.env.bak`, `*.pem`, `ssh/`, `data/`, `keylock`
— 0 commits each, all refs); the full `pre-commit`
hook set is green tree-wide (after the repairs recorded under *High* below); the IB API
ports are bound to `127.0.0.1`; PR builds still run with `push: false` — since
2026-08-26 they hold a `packages: read` ghcr.io login, which pulls the base image
and cannot push anything (item 16); `bastion/sshd_config` is genuinely hardened (publickey-only,
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

*Items 4-8 came from the 2026-08-25 sweep; four of the five were fixed the same
day on branch `qa-medium-fixes`. Item 16 is closed: it wanted one of two
decisions — make the package public, or add a `build.args` entry — and both
were taken, the build args on 2026-08-25 and the visibility on 2026-08-29. What
is left of it is `DECISIONS.md` #30. Item 17 was found and fixed on
2026-08-26.*

### 4. IBC and the aarch64 JDK installed without verification — **FIXED**

`Dockerfile.template` now pins `ARG IBC_SHA256` and `ARG ZULU_SHA256` and checks
both before use, matching the treatment the IB Gateway installer already got.
Neither vendor publishes a checksum file (both probed 2026-08-25: 404), so the
digests are measured and pinned:

- `IBCLinux-3.24.1.zip` → `d99ee28c…88bb8`
- `zulu17.60.17-ca-fx-jre17.0.16-linux_aarch64.tar.gz` → `e74bcc2d…3b5d0`

The JDK branch also had `;` separators, so a failed download or extraction did
not stop the build; it is `&&`-chained now.

> *Superseded in part, 2026-08-25.* The Zulu JDK is no longer downloaded at all
> — it was never used, see #17 — so `ZULU_SHA256` is gone with it. `IBC_SHA256`
> is unchanged and still checked. The IB installer keeps its published
> `.sha256`, and its download now uses `curl -f`, so a missing asset fails as a
> 404 instead of saving an HTML error page and failing the checksum with a
> misleading message.

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

### 16. `docker compose build --pull tws` cannot work on a clean machine — **FIXED**

*Found 2026-08-25, while verifying the merged compose file. Not caused by that
merge — it predates it. **CI half fixed 2026-08-26**; the local build was fixed
the day before that, and re-verified on 2026-08-29 by building the tws `setup`
stage on its own — it resolved against the image `docker compose build
ib-gateway` had just produced, with no `docker tag` and no registry access.*

*`--pull` on the tws build is still the wrong command, but no longer an
impossible one: since the packages went public on 2026-08-29 it succeeds, and
quietly builds against the registry's gateway image rather than the one just
built here. Use `docker compose build ib-gateway` then `docker compose build
tws`, without `--pull` on the second. Moved to `DECISIONS.md` #30 so it stops
reading as outstanding work.*

`Dockerfile.tws` starts `FROM ghcr.io/dennisdeh/ib-gateway:${IB_VERSION}` with
`IB_VERSION` defaulting to the channel's gateway version, so the TWS build needs
that **exact tag** present. `ghcr.io/dennisdeh/ib-gateway` was not anonymously
pullable then — `docker pull ghcr.io/dennisdeh/ib-gateway:10.48.1e` and
`:10.47.1c` both returned `error from registry: denied` on 2026-08-25 — so
`--pull` failed at the first stage with `403 Forbidden` from the ghcr token
endpoint. It has been public since 2026-08-29; see `DECISIONS.md` #32.

Building the gateway first is not enough either: `docker compose build
ib-gateway` tags it `:latest`, not `:10.48.1e`. The workaround used to verify
the merge was

```bash
docker compose build --pull ib-gateway
docker tag ghcr.io/dennisdeh/ib-gateway:latest ghcr.io/dennisdeh/ib-gateway:10.48.1e
docker compose build tws          # no --pull
```

after which the TWS build completed. **FIXED 2026-08-25.** `Dockerfile.tws.template` now takes the base image as two
build args, `IB_GATEWAY_IMAGE` and `IB_VERSION`, defaulting to the ghcr
reference so a published build is unchanged. The `tws` compose service passes
`${IB_GATEWAY_IMAGE:-ghcr.io/dennisdeh/ib-gateway}` and `${IB_GATEWAY_TAG:-latest}`,
and `latest` is the tag the `ib-gateway` service's own build produces — so

```bash
docker compose build ib-gateway
docker compose build tws
```

works on a clean machine with no registry access and no manual `docker tag`.
CI points the same two args at a job-local registry; see `DECISIONS.md` #15.

### 17. The `linux/arm64` image could never have been built — **FIXED**

*Found 2026-08-25, from the CI failures on `master`.*

Every `Docker Image CI` run since `continue-on-error` was removed failed, always
on the same step and always on the `arm64` leg:

```text
process "/dev/.buildkit_qemu_emulator /bin/sh -c apt-get update -y && …"
  did not complete successfully: exit code: 255
```

Reproduced locally with `docker build --platform linux/arm64 ./latest`, which
gives the readable form of the same failure:

```text
Starting Installer ...
./ibgateway-10.48.1e-standalone-linux-x64.sh: 813:
  /tmp/setup/ibgateway-…-x64.sh.6577.dir/jre/bin/java: not found
```

The installer bundles its own JRE and runs it. The x64 installer's JRE is an
x86-64 binary, which cannot execute in an `aarch64` container — `sh` reports
"not found", exit 127, which QEMU surfaces to BuildKit as 255.

`app_java_home=/usr/local/zulu17` was meant to point the installer at the
aarch64 Zulu JRE the build downloads for exactly this purpose. **It is not
honoured**: the installer had already reached its own `jre/bin/java` by the time
the message appeared. So the Zulu tarball was fetched, checksum-verified, copied
into the runtime image and never used, on every build, on both architectures.

The failure predates the reporting. `continue-on-error: true` (item #1) meant
the job reported success regardless, so the last genuinely-green `arm64` build,
if there ever was one, is not identifiable from the run history.

**QEMU words the same fault two ways**, depending on how it declines the binary:
`jre/bin/java: not found` and `Invalid ELF image for this architecture`. Both
mean a wrong-architecture executable, both exit 255, and both are this bug — the
second was seen on 2026-08-26 on branch `worktree-auto-publish-images`, which
still carries the pre-fix Dockerfile. That log also shows the mechanism plainly:
`zulu…tar.gz: OK` immediately before the installer reaches for its *own* bundled
`jre/bin/java` anyway, which is the proof that `app_java_home` is ignored.

**The fix** is to install the architecture's own installer —
`…-standalone-linux-arm.sh` on `aarch64`, `…-x64.sh` elsewhere. IB publishes
both and `detect-releases.yml` already attaches both to each release
(`archs="x64 arm"`). The Zulu download and `ZULU_SHA256` are removed with it.

`COPY --from=setup /usr/local/` was removed at the same time and **that was a
mistake** — it does not carry Zulu, it carries the JVM the IB installer unpacks
to `/usr/local/i4j_jres`. Two JVM-less images were built before it was caught
while bumping `stable`. It is restored, and both runtime stages now end with a
`find … -name java` + `java -version` step so the build fails rather than
shipping an image whose launcher points at a JVM that is not there. See
`DECISIONS.md` #18.

Verified 2026-08-25 by building `./latest` for `linux/arm64` under QEMU, before
and after: before, `jre/bin/java: not found`; after, the installer runs to
completion and the image builds.

### 18. `stable` was pinned to a version with no `arm` release asset — **FIXED**

*Found 2026-08-25, while fixing #17.*

The per-architecture download in #17 needs `…-standalone-linux-arm.sh` to exist
in the channel's GitHub release. It does for `latest` (`10.48.1e`, HTTP 200) but
**not** for `stable` as then pinned (`10.45.1g`, HTTP 404) — that release carries only the x64
installer and its `.sha256`. So `stable` cannot build `linux/arm64` at any
version it is currently pinned to, and its `arm64` leg fails on a missing file
rather than on a broken JRE.

This is a legacy gap, not an ongoing one: `detect-releases.yml` attaches both
architectures, and every `stable` release from `10.45.1h` onward has the `arm`
asset. `stable` is four releases behind because the bot's
`update-stable-to-10.45.1j` branch (opened 2026-08-06) has never been merged.

**Resolved by bumping `stable`, on the owner's instruction, 2026-08-25.**
`./update.sh stable 10.45.1j` — that release carries both installers and both
`.sha256` files (probed the same day: `arm` and `arm.sha256` HTTP 200). `stable`
therefore builds `linux/arm64` again, and the interim restriction that had
limited it to `linux/amd64` is gone from both workflows.

`PLATFORMS` is now a plain `linux/amd64,linux/arm64` declared once in
`build.yml` and once in `publish.yml`. The two must stay identical — if they
drift, CI passes and the release then fails on the platform only one of them
builds — and `tests/unit/workflows.bats` fails both on a mismatch and on
`linux/arm64` being dropped altogether.

This also moved `stable` four releases forward, from `10.45.1g`. The bot's
`update-stable-to-10.45.1j` branch (opened 2026-08-06, never merged) is now
redundant; its PR can be closed. `detect-releases.yml` will not reopen one,
because it keys off the existence of the `ibgateway-stable@10.45.1j` release,
which already exists.

### 24. `apt-get` fails on the `linux/arm64` leg when Ubuntu is mid-publication — **MITIGATED**

*Numbered 19 until 2026-08-28; that number belongs to the bastion publishing
item in the Low table.*

*Diagnosed 2026-08-25, from a local reproduction and the CI log of run
`32901651857`, which agree exactly — same package, same mirror node.*

```text
Ign:1 http://ports.ubuntu.com/ubuntu-ports noble-updates/main arm64 libssl3t64 3.0.13-0ubuntu3.15
Err:1 ... 404  Not Found [IP: 91.189.92.20 80]
E: Failed to fetch .../libssl3t64_3.0.13-0ubuntu3.15_arm64.deb  404  Not Found
E: Unable to fetch some archives
```

Canonical had published `libssl3t64 3.0.13-0ubuntu3.15` into the `noble-updates`
**index** before the `arm64` **pool** carried it. `apt-get upgrade` resolved to
that version and got a 404; apt exits **100**. The `amd64` leg installed the
same version from `archive.ubuntu.com` seconds earlier in the same build, which
is why only the emulated leg died.

Nothing in this repository causes it and nothing here can prevent it — it breaks
any build of this tree, `master` included, during the publication window. The
window closed on its own: a rebuild of the identical tree a short while later
fetched the package with no error and no retry.

**Mitigation, not a cure.** Each `apt-get` block in `Dockerfile.template` and
`Dockerfile.tws.template` now retries up to three times, running `apt-get
update` again between attempts so the index is re-read and DNS re-resolves,
usually onto a different mirror node, and `exit 1` if all three fail rather than
falling out of the loop silently. A sustained pool outage will still fail the
build, correctly.

**Reading a red `arm64` leg.** Three quite different causes, told apart by the
exit code and how far it got:

| symptom | cause |
|---|---|
| exit 255, `jre/bin/java: not found` **or** `Invalid ELF image for this architecture` | the x64-installer-on-aarch64 bug — fixed, see #17 |
| exit 1 at the `java -version` step | no JVM survived into the runtime stage, see #18 and `DECISIONS.md` #18 |
| exit 100, `404 Not Found` from `ports.ubuntu.com` | this item; retry, and if it persists check whether Ubuntu is mid-publication |

**In CI this is now handled, on 2026-08-26**, and it had to be for the release
automation to work at all. `build.yml` logs in to `ghcr.io` with the run's own
`GITHUB_TOKEN` and carries `packages: read`, so the TWS leg can pull the gateway
image of the version the channel already publishes; `on-push-n-pr.yml` and
`detect-ibc-release.yml` grant the same scope, because a called workflow cannot
hold a permission its caller withheld. Two limits remain, both by construction:

- a version that has **never** been published cannot be built this way. That is
  why `publish.yml` pushes the gateway before it builds TWS, and why the release
  path goes through `publish.yml` rather than `build.yml`;
- a pull request **from a fork** got a read-only `GITHUB_TOKEN` with no access
  to this repository's packages, so its TWS leg failed. Making the package
  public was named here as the fix, and that is what happened on 2026-08-29
  (`DECISIONS.md` #32): an anonymous pull of a published tag now succeeds.

The local build stopped needing the `docker tag` workaround above when the build
args landed on 2026-08-25 — `docker compose build ib-gateway` then `docker
compose build tws` resolves the base from the image just built.

### 22. Detecting a new IB Gateway version published nothing — **FIXED**

*Numbered 17 until 2026-08-28; that number was already taken by the `arm64`
JRE bug above, which `tests/unit/dockerfile.bats` cites.*

*Found and fixed 2026-08-26, on branch `worktree-auto-publish-images`, while
wiring detection to publication as asked.*

`detect-releases.yml` created the GitHub release, regenerated the channel and
opened the bump PR, then called `build.yml` — which builds with `push: false`.
Reaching `ghcr.io` needed a human to merge the PR and push a
`v<version>-<channel>` tag. Two further defects sat underneath that:

- **The matrix job's outputs could not carry a per-channel answer.** Both legs
  of `strategy.matrix.channel` wrote the same `outputs.update` and
  `outputs.channel`, and a matrix job keeps only the last leg to finish, so the
  downstream `build` job received one arbitrary channel — the wrong one roughly
  half the time, and *neither* leg's version. The legs now hand over a small
  JSON file each; a `collect` job reassembles them into the publish matrix.
- **Tagging would not have worked either.** A `v*` tag pushed with
  `GITHUB_TOKEN` starts no workflow run, so the obvious repair — have the bot
  push the tag and let `publish.yml` notice — publishes nothing while reporting
  success. `publish.yml` gained `workflow_call` and is invoked directly. See
  `DECISIONS.md` #14.

`publish.yml` also refuses to tag an image with a version it does not contain:
it compares against `ENV IB_GATEWAY_VERSION=` in the channel Dockerfile it is
building. Sixteen assertions in `tests/unit/workflows.bats` pin the wiring;
thirteen of them were shown red against the pre-fix workflows on 2026-08-26.

**Not verified end to end**, and it cannot be from here: the flow needs a real
IB release, GitHub-hosted runners and push credentials for `ghcr.io`. The first
live proof will be the next IB Gateway version, or a `workflow_dispatch` of
`publish.yml` against a channel.

### 21. An IBC bump shipped the previous version's digest — **FIXED**

*2026-08-27.* `IBC-update-3.24.2` was merged (PR #17) carrying
`ENV IBC_VERSION=3.24.2` in both templates and `ARG IBC_SHA256` still on
3.24.1's digest. Verified against the real releases:

```text
IBC 3.24.1  d99ee28cc3539e3843fb00d28dc484c255006b0063d38f0808ac3ef07dd88bb8
IBC 3.24.2  cc097ca1dfa75413a5fbe02e4743050af15f3308eb6a97c769b3cff9850c80c5
```

Nothing failed at the time, which is what makes it worth recording: both
channels still pinned 3.24.1 with its matching digest, so every build kept
working. The next gateway release runs `update.sh`, which renders the channel
from the template — and that build dies at `sha256sum --check`, in a release
job, on a bot commit.

**Why the workflow's own safeguard did not fire.** `detect-ibc-release.yml`
*does* recompute the digest, and even asserts the rewrite took. But that whole
step lives inside *Create Pull Request*, which is skipped when
`verify_branch` finds the branch already there — and `IBC-update-3.24.2` had
been opened by a run from before the recompute existed. The duplicate-avoidance
that `CLAUDE.md` warns against defeating is exactly what preserved the stale
branch.

Fixed three ways: the digest was corrected on `master`; a *Verify the pinned
IBC digest* step now runs on every daily run, outside every conditional, and
fails loudly with the digest to paste in; and `tests/unit/dockerfile.bats`
pins the version↔digest pairing offline — two files pinning the same IBC
version must pin the same digest, and two pinning different versions must not,
which is precisely the shape of this bug. Shown red against the merged state.

### 25. The `stable` channel had never been published — **FIXED**

*Found 2026-08-28, while auditing that every image the project needs is one it
produces.*

`README.md` documents six gateway/TWS tags. Three of them do not exist.
Measured against the registry on 2026-08-28 with `docker manifest inspect`:

```text
present  ghcr.io/dennisdeh/ib-gateway:latest      [amd64 arm64]
present  ghcr.io/dennisdeh/ib-gateway:10.50
present  ghcr.io/dennisdeh/ib-gateway:10.50.1e
MISSING  ghcr.io/dennisdeh/ib-gateway:stable
MISSING  ghcr.io/dennisdeh/ib-gateway:10.45
MISSING  ghcr.io/dennisdeh/ib-gateway:10.45.1j
```

`tws-rdesktop` is identical - every `latest` tag present, every `stable` tag
missing. `bastion:latest` and `bastion:2604.01` are both present, for both
architectures.

**Nothing is miswired.** Publication is driven by `detect-releases.yml`, which
calls `publish.yml` only for a channel that has *moved*. That went into effect
on 2026-08-26; `latest` moved to `10.50.1e` on 2026-08-27 and published
correctly. `stable` has been on `10.45.1j` throughout, so it has never had an
occasion to publish, and there was no back-fill for the versions already pinned
when the automation landed. It will publish by itself at stable's next IB
release.

Until then the gap is user-visible, not cosmetic:

- the *Supported Tags* table promises tags that 404;
- `deploy/provision.sh --channel stable` writes `IB_GATEWAY_IMAGE=...:10.45.1j`
  into the emitted `.env`, and `docker compose up -d` on that host cannot pull
  it;
- `Dockerfile.tws` opens `FROM ghcr.io/dennisdeh/ib-gateway:<version>`, so the
  TWS image for `stable` cannot be built from the registry either.

**FIXED 2026-08-28** by pushing `v10.45.1j-stable`, the by-hand release path
`publish.yml` already accepts. Before pushing, that workflow's own channel and
version resolution was run against the tag offline - channel `stable`, version
`10.45.1j`, minor `10.45`, and the guard that refuses to tag an image with a
version it does not contain agreed with `stable/Dockerfile` - and all four
installer assets plus `IBCLinux-3.24.1.zip` were confirmed to return 200, so
the `arm64` leg could not 404 half an hour in.

Measured after the run:

```text
ib-gateway   :stable = :10.45.1j = :10.45   sha256:c3b06296...  [amd64 arm64]
tws-rdesktop :stable = :10.45.1j = :10.45   sha256:b3e8eeb3...  [amd64 arm64]
bastion      :latest = :2604.01             sha256:f26cd50e...  [amd64 arm64]
```

The channel tag and both version tags resolve to one image in each case. The
images carry `ENV IB_GATEWAY_VERSION=10.45.1j`, so the tags describe what is
inside them, and `org.opencontainers.image.revision` records `9747d604`, the
commit they were built from. `tws-rdesktop:stable` carries
`ENV IBC_VERSION=3.24.1`, which independently confirms the per-channel IBC
reporting added the same day (`DECISIONS.md` #26): stable does ship 3.24.1
while latest ships 3.24.2, and the README now says so. The `latest` channel was
untouched - `ib-gateway:latest` still resolves to `10.50.1e`'s digest.

**Not automated further, deliberately.** A back-fill is a one-off; making
detection publish channels that have not moved would re-push both channels
every day. The next `stable` release publishes itself.

### 26. `CA_ENABLED=yes` with no certificate files reports success and does nothing — **FIXED 2026-08-29**

*Found 2026-08-28, while rewriting the bastion's TOTP and CA documentation.
Measured against `ghcr.io/dennisdeh/bastion:latest`.*

`set_CA()` in `bastion/entrypoint.sh` resolves the two paths like this:

```bash
[ ! -f "$SSHD_HOST_CERT" ] && SSHD_HOST_CERT='/etc/ssh/ssh_host_ed25519_key-cert.pub'
[ ! -f "$SSHD_USER_CA" ]   && SSHD_USER_CA='/etc/ssh/user_ca.pub'
```

Both substitutions are silent, and neither the fallback path is then checked.
Started with `CA_ENABLED=yes` against a `data/` that has no certificate in it,
the container prints `> SSH CA 🔏 enabled` and sshd listens normally:

```text
> SSH CA 🔏 enabled
> Starting /usr/sbin/sshd -D -e ... -o HostCertificate=/etc/ssh/ssh_host_ed25519_key-cert.pub -o TrustedUserCAKeys=/etc/ssh/user_ca.pub
Server listening on 0.0.0.0 port 22.
```

OpenSSH is content with that. `sshd -t` with both paths absent **exits 0**,
warning only about the host certificate and saying nothing whatever about the
missing `TrustedUserCAKeys`:

```text
Could not load host certificate "/etc/ssh/ssh_host_ed25519_key-cert.pub": No such file or directory
sshd -t exit=0
```

So an operator who sets `CA_ENABLED=yes`, forgets to copy the files in — or
mistypes `SSHD_HOST_CERT` — gets a bastion that presents no host certificate
and trusts no user CA, with a log line saying CA is enabled. Nothing fails.
Clients still authenticate from `authorized_keys` exactly as before, which is
why it can go unnoticed: the bastion works, just not the way it says.

**Severity is "reports success", not "lets someone in".** No access is granted
that was not granted before; the risk is an operator believing certificate
authentication is in force — and, if they then remove `authorized_keys` entries
because "the CA handles it", locking everyone out, or leaving a `known_hosts`
fingerprint check they think is redundant.

**FIXED 2026-08-29 with that guard**, shaped like `check_totp_users()`.
`set_CA()` now refuses to start when a path the operator *named* does not
exist — a typo is no longer swallowed by the fallback — and when `CA_ENABLED`
is on but neither a host certificate nor a user CA is present anywhere, since
enabling it would then change nothing.

The two halves stay independent, which is the false positive that had to be
avoided: a host certificate frees clients from `known_hosts` and a user CA
frees this host from `authorized_keys`, so either **alone** is a valid setup
and still starts, with a warning naming the half that is absent.
`tests/container/bastion_ca.bats` covers all five cases, including that
last one, and every one of them was run against both the fixed and the
published (unfixed) image — the four new assertions fail against the latter.

### 27. `detect-ibc-release.yml` could not see its own bump branch — **FIXED**

*2026-08-28, merging the `claude/github-actions-issues` branch.* Four defects in
the daily IBC check, each of which fails silently:

- **`verify_branch` never matched.** It tested `git branch -r --list | grep
  origin/<branch>`, but `actions/checkout` fetches a single branch at a shallow
  depth, so no `origin/IBC-update-*` ref exists locally however many times one
  has been pushed. The step reported `BRANCH_EXISTS=false` every day and
  `gh pr create` then failed on the pull request that was already open. It now
  asks the remote with `git ls-remote --exit-code --heads`, and still falls back
  to the open-PR check for a branch deleted with its PR left open. This is the
  same stale-branch mechanism as #21, from the other side.
- **The upstream version came from a human-facing table.** `gh release list |
  grep 'Latest' | cut -f1` matches the word `Latest` in any column, a release
  title included, and takes a positional field. Replaced with `gh api
  repos/<repo>/releases/latest --jq .tag_name`, which is defined as the latest
  published non-draft, non-prerelease.
- **An empty or unexpected value was used rather than refused.** A transient API
  failure read as "there is a new version called nothing" and reached a branch
  name `IBC-update-` and `IBC_VERSION=` in both templates. Both the pinned and
  the upstream version are now checked against `VERSION_PATTERN` before use —
  the same treatment IB's `buildVersion` already gets in `detect-releases.yml`,
  and for the same reason: the value reaches a branch name, two `sed` patterns,
  a download URL and a `git push`.
- **A downgrade would have opened a PR.** A plain `!=` also fires when upstream's
  latest resolves to something *older* — a re-tag, or a newer release un-marked
  as latest. The comparison is now `sort -V`, which also orders `3.9` before
  `3.10` where a string compare does not.

Two smaller ones with it: the `sed` rewrites of both templates are now confirmed
with `grep -q` (`sed` exits 0 whether or not it matched, so a bump could land in
one template and silently skip the other, which is also now checked up front),
and the branch push dropped `--force`, which was only ever masking the broken
existence check.

The `build` job below them is gated on a branch having actually been created and
passes `ref:` so it builds the bump rather than `master` — building `master`
validated the code *without* the change. `build.yml` gained that optional `ref`
input, defaulting to empty, which is what the CI callers want.

**Not verified end to end**, and it cannot be from here: it needs GitHub-hosted
runners, `gh` and a real IBC release. `tests/unit/workflows.bats` covers the
wiring offline.

## Low / accepted risk (record the decision if you accept it)

| # | item | note |
|---|---|---|
| 9 | `echo "ibgateway ALL=(ALL) NOPASSWD:ALL" \| tee -a /etc/sudoers` in `Dockerfile.template` — **FIXED 2026-08-30** | Anything able to run code as `ibgateway` — the IB Gateway process itself included — was container-root. Inherited from upstream, and **nothing in the image ever used it**: `run_scripts()` in `common.sh` runs each operator script with a plain `bash`. It existed only so a `START_SCRIPTS` script could install packages, which `template_README.md` promised in the words "or install additional tools". Both the grant and the `sudo` package are gone, and that section now points at a derived image (`FROM ghcr.io/dennisdeh/ib-gateway` … `USER root` … `USER 1000:1000`) — the supported way to add packages, and the only way they survive the container being recreated. **This is a breaking change** for anyone whose start-up scripts called `sudo`, and a quiet one: `run_scripts()` reports a failing script as "File … not found" and carries on. Nothing here used the hooks — all three keys are commented out in `.env` and the `init-scripts` mount in `docker-compose.yml`. Narrowing the grant to `apt` was offered and rejected as theatre: `sudo apt-get install ./x.deb` runs a maintainer script as root, and `-o APT::Update::Pre-Invoke::` runs anything. Decided by the owner, 2026-08-30, on that reasoning. `tests/unit/dockerfile.bats` fails on `NOPASSWD` or a write to `/etc/sudoers` in any source Dockerfile; shown red against the unfixed template, where it named that file and no other. |
| 10 | `x11vnc … -passwd "$VNC_SERVER_PASSWORD"` in `run.sh` — **FIXED 2026-08-29** | The password was in argv, where anything able to read `/proc` could see it; x11vnc's own `-help` says exactly that about `-passwd` and points at `-passwdfile`. `start_vnc()` now writes it to a `0600` file and passes `-passwdfile rm:<file>`, the `rm:` prefix making x11vnc delete the file once it has read it — so it is neither in the process list nor left on disk. Confirmed the flag and the prefix against the published image before relying on them. `tests/unit/credentials.bats` runs the real `start_vnc` against a stub `x11vnc` and fails if the password appears in argv; shown red against `-passwd`. |
| 11 | TWS image default RDP password is `abc` (`${PASSWD:-abc}` in `start_session.sh`) — **FIXED 2026-08-29, by saying so** | Still `abc`: changing the default breaks every deployment relying on it, and the image cannot see which interface the host published 3389 on. It now prints a five-line warning at every start when `PASSWD` is unset, naming the risk and the `127.0.0.1` assumption that makes it tolerable. `tests/unit/credentials.bats` asserts the warning appears without `PASSWD`, does not appear with it, and that the password actually set is unchanged either way. |
| 12 | `run_ssh.sh` runs `bash -c "ssh ${_OPTIONS} … ${_USER_TUNNEL}"` — **FIXED 2026-08-29** | `SSH_OPTIONS` and `SSH_SCREEN` each carry several arguments in one variable and still have to be split, but only into words: `read -ra` does that and stops there, and the destination is passed as a single argument. Never a way in from outside — the values are operator-controlled — but a password with a backtick in it would have executed rather than failed to connect. `tests/unit/run_ssh.bats` gained three tests: a metacharacter in the destination does not run, a `$(...)` in the options does not run, and multi-word options still split into separate argv entries. The first two were shown red against the `bash -c` line. |
| 13 | Dependabot watched `/stable` and `/latest` only — **FIXED 2026-08-28** | Those are *generated*: a base-image bump landed there is overwritten by the next `update.sh`, so it looked like coverage and was churn, while the real sources went unwatched. The docker ecosystem now uses `directories:` and names `/` (which reaches `Dockerfile.template` and `Dockerfile.tws.template` — Dependabot matches any file name containing `dockerfile` or `containerfile`, case-insensitively and unanchored), `/bastion` and `/tests`. `tests/unit/images.bats` fails if a directory holding a Dockerfile is missing from that list, or if a generated one reappears in it. The floating tag `lscr.io/linuxserver/rdesktop:ubuntu-xfce` is now watched with the rest. |
| 14 | `PWD` is defined inside `.env` | Renaming or moving the repository silently breaks every bind mount while compose still validates. |
| 15 | `PORT_HOST_SSH_BASTION=2222` in `.env` is referenced nowhere — **FIXED** | The key is gone, and `.env-dist` now says in the bastion block that `SSH_LISTEN_PORT` is published on **all** host interfaces — unlike every other port here, which is pinned to `127.0.0.1` — and that this is the point of a bastion but should still be firewalled deliberately. `tests/unit/compose.bats` now fails on any key in `.env-dist` that nothing reads, so a dead knob cannot come back: a key here is a promise that setting it does something. Shown red by re-adding this exact key. |
| 23 | `.pre-commit-config.yaml` revs are pinned to 2024 releases and no ecosystem updates them — **FIXED 2026-08-29** (numbered 18 until 2026-08-28, which the `arm` release-asset item already used) | `pre-commit autoupdate` moved five of the six: `pre-commit-hooks` v4.6.0→v6.0.0, `shellcheck` v0.10.0→v0.11.0, `shfmt` v3.12.0-1→v3.13.1-1, `hadolint` v2.12.1-beta→v2.15.1, `markdownlint-cli` v0.39.0→v0.49.1; `dotenv-linter` was current. Every hook passes at the new revisions, with one rule turned off: `MD060` arrived in markdownlint 0.49 and fires 228 times on table-pipe padding in the generated README — see `DECISIONS.md` #31. Dependabot still has no `pre-commit` ecosystem, so this stays a manual `autoupdate`; the point of the item was that the revisions had gone stale, not that a bot must do it. |
| 19 | The bastion image is published nowhere — **FIXED 2026-08-27** | It was built from `bastion/` and tagged `dennisdeh/bastion:local-resolute`, so `deploy/provision.sh` needed a checkout to build one of the three images. `publish.yml` then pushed `ghcr.io/dennisdeh/bastion` — `publish-bastion.yml` does since 2026-08-30, see #31 — tagged with the `ARG IMAGE_VERSION` the bastion's own Dockerfile declares, and `provision.sh` pulls it and only falls back to building. `build.yml` builds it too, so a break fails the PR check rather than a release. |
| 20 | `sshd_config.d/*.conf` is included but not covered by the provisioning hash — **FIXED 2026-08-27** | `bastion/sshd_config` opens with `Include /etc/ssh/sshd_config.d/*.conf`, and `set_checksum()` hashed `sshd_config` and the host keys but nothing from that directory, so a drop-in could set `PermitRootLogin` or widen `AllowTcpForwarding` while `check_provision()` still reported a valid checksum. Confirmed against the unfixed image: adding, editing **and** removing a drop-in all started normally. `set_checksum()` now hashes those files *and* a recorded listing of the directory — the files alone cannot catch an addition or a removal, since every recorded line still checks out — and `check_sshd_config_d()` in `entrypoint.sh` compares the listing before sshd starts. Pinned by `tests/container/bastion_hash.bats`. **Upgrading the image requires re-provisioning `data/`**: the container refuses to start on data provisioned before this, rather than skipping the check. |
| 28 | The gateway and TWS images labelled themselves `"Apache License Version 2.0"` and the bastion labelled itself `MIT` — each the other's licence — **FIXED 2026-08-30** | The tree the gateway and TWS are built from is MIT (`LICENSE`); `bastion/` is a fork carrying its own Apache-2.0 `LICENSE.txt`. Both templates and all four generated channel Dockerfiles now say `MIT`, and `bastion/Dockerfile` says `Apache-2.0`, as SPDX identifiers. Nothing had caught it because `docker/metadata-action` derives this label from the repository and applies it over the Dockerfile's, so every published image read `MIT` whatever its own Dockerfile said — measured on all three published images, 2026-08-30 — while a local `docker compose build` kept the Dockerfile's value, and the two therefore disagreed. That same override is why fixing the bastion also needed its meta step to name `Apache-2.0` in its own `labels:` (in `publish.yml` that day, in `publish-bastion.yml` since #31); the derived `MIT` would otherwise have won again. `tests/unit/images.bats` now pins each Dockerfile to the licence file its directory carries, and `tests/unit/workflows.bats` pins the publish-time override. See `DECISIONS.md` #33. |
| 29 | `bastion/.env` sat inside the bastion build context — **FIXED 2026-08-30** | `bastion/.dockerignore` excluded `/data` and editor droppings but not the env file beside them, so a real credentials file was uploaded to the daemon on every build of that image. Nothing ever leaked: `bastion/Dockerfile` `COPY`s five files by name and never took it — but the first `COPY . .` anyone writes would ship it, and `.gitignore` had been refusing the same file since 2026-08-25. The dockerignore now carries the `.env`, `.env.*`, `*.env` trio `.gitignore` uses (`.env-dist` matches none of them and stays), and `tests/unit/images.bats` fails if one of them or `/data` goes missing. `latest/` and `stable/` need no equivalent: `update.sh` generates them wholesale and they hold nothing untracked. |
| 30 | `LABEL org.opencontainers.image.version=${IB_GATEWAY_VERSION}-${IB_GATEWAY_RELEASE_CHANNEL}` in `Dockerfile.template`, whose second variable was defined nowhere in that file — **FIXED 2026-08-30** | The setup stage declares `ENV IB_GATEWAY_CHANNEL`; the runtime stage that carries this `LABEL` declares neither name, so the label expands to the version and a trailing dash. Measured 2026-08-30 by building the same three lines: the value is `"10.50.1e-"`. `docker build --check` reports it as `UndefinedVar` on `latest/Dockerfile:145` and `stable/Dockerfile:145`. Only local builds are affected — `docker/metadata-action` overwrites this label at publish time with `<version>-<channel>`, which is what all three published images carry (measured the same day), the same override that hid #28. `Dockerfile.tws.template` never had the bug: its runtime stage declares `IB_GATEWAY_RELEASE_CHANNEL` itself, and the fix is that same line, in the same position, in the gateway's runtime stage — declaring the name again rather than renaming anything, since renaming an `ENV` a published image already carries would break anyone reading it. Verified both ways on 2026-08-30: `docker build --check` on `latest/Dockerfile` and `stable/Dockerfile` drops from three warnings to two, the `IB_GATEWAY_RELEASE_CHANNEL` one gone, and the same three lines built again now label `"10.50.1e-latest"`. `tests/unit/images.bats` fails if any `LABEL` in a final stage uses a variable that stage does not declare — the general form of this and of the bastion's `-resolute` bug, shown red against the unfixed template, where it named that file and only that file. The other two `UndefinedVar` warnings on those files are the self-referencing `ARG USER_ID="${USER_ID:-1000}"` / `USER_GID` defaults, which resolve to `1000` as intended — noise, not a defect, and left alone. |
| 31 | a bastion-only fix reached the published image only at the next IB Gateway release, and `tests/run.sh container` was red until it did — **FIXED 2026-08-30** | Found while verifying #9, and not part of it. `publish.yml` pushed the bastion but only ever ran on an IB Gateway release or by hand, so `bastion/entrypoint.sh`'s #26 CA fix of 2026-08-29 was not in `ghcr.io/dennisdeh/bastion:latest`, which was built 2026-08-27. Measured the same day: four `bastion_ca.bats` cases fail against the published image and all thirteen pass against one built from this tree. The bastion's build steps moved to `.github/workflows/publish-bastion.yml`, which declares `packages: write` itself and triggers on a push to `master` touching `bastion/**` — and which `publish.yml` now *calls*, so an IB release still refreshes the image against its Ubuntu base. One definition, two reasons to run it; `DECISIONS.md` #22 records the reasoning it replaces. `ARG IMAGE_VERSION` went to `2604.02` with it: the CA fix changed behaviour on 2026-08-29 without a bump, and an unbumped version overwrites its tag. **The workflow itself is in the trigger's path list**, so merging this publishes the bastion — which is also the only way a workflow that cannot be run locally gets exercised at all. `tests/unit/workflows.bats` pins the trigger, the branch restriction and the permission. |
