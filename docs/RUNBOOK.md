# RUNBOOK

How to run, provision and recover the local stack. User-facing configuration is
documented in `template_README.md`; this file is about *this* deployment.

*Last updated: 2026-08-27*

## What runs, and from where

**Not from this checkout.** `inv_gateway` and `inv_bastion` are started from a
vendored copy of this project inside the Investio repository:

```text
/mnt/data/Documents/Investio/modules/p00_apps/ib-gateway-docker/docker-compose.yml
```

*(Read from the containers' `com.docker.compose.project.config_files` label,
2026-08-25.)* Investio is expected to consume this repository later.

| container | image | role |
|---|---|---|
| `inv_gateway` | `ghcr.io/dennisdeh/ib-gateway:latest` | IB Gateway + IBC under Xvfb |
| `inv_bastion` | `dennisdeh/bastion:local-resolute` | SSH jump host for the tunnel |

The bastion image name above is what the vendored copy *builds*; since
2026-08-27 this repository also publishes `ghcr.io/dennisdeh/bastion`, and
`docker-compose.yml` here names that instead. The running container keeps the
locally built tag until the Investio copy is synced.

Other services on this machine (`inv_visualisation`, `inv_db`, `inv_redis`,
`inv_ntfy`) consume the gateway's API port.

> This repository's `docker-compose.yml` declares `name: inv_ibkr`, the same
> project name the Investio copy uses, and Compose identifies a project by that
> name rather than by directory: a lifecycle command run in *this* repository
> acts on those live containers. Verified 2026-08-25 — `docker compose ps` here
> lists them. See `CLAUDE.md`.

## Ports

*Last updated: 2026-08-25 — read from `.env`; re-check before relying on it.*

| host | container | what |
|---|---|---|
| `127.0.0.1:9898` | `4004` (socat) → `4002` (API) | paper API |
| `127.0.0.1:9899` | `4003` (socat) → `4001` (API) | live API |
| `127.0.0.1:9897` | `5900` | VNC |
| `2222` | `22` | bastion SSH |

The published port is always the **socat** port, never the API port IB Gateway
itself listens on. See *Key conventions* in `CLAUDE.md`.

## Start / stop

Run these **from whichever checkout owns the deployment** — today the Investio
copy above, not this one:

```bash
cd <the owning checkout>   # $PWD-based mounts require this
docker compose config      # validate .env + wiring, starts nothing
docker compose up -d       # start
docker compose down        # stop — interrupts every dependent service
```

`up -d` starts whatever `IB_APP` in that checkout's `.env` selects, plus the
bastion. The vendored copy still carries the pre-2026-08-25 two-file layout,
which has no `IB_APP`; when it is synced from this repository, `.env` there
needs `IB_APP=ib-gateway` and `COMPOSE_PROFILES=${IB_APP}` or `up -d` will
create the bastion alone.

Safe from anywhere, read-only:

```bash
docker logs -f inv_gateway
docker compose config      # validation only, starts nothing
```

## Provisioning a host from scratch

*Last updated: 2026-08-27.*

`deploy/provision.sh` prepares a host to run the **published** images alongside
other containers, and emits the compose file to run it with. It creates the ssh
keys, the bastion's `data/`, the secrets and the directory layout, and it is
safe to re-run — every step checks before it acts.

The user-facing version of this is the *Deploying* section of `README.md`
(edit `template_README.md`); what follows is what applies to **this** machine.
The script needs no checkout when given `--version`: it pulls all three images
and writes the bastion's `data/` from inside the bastion container. Verified on
2026-08-27 by running a copy of the script alone, outside the repository.

```bash
deploy/provision.sh init --clients jupyter,visualisation --tws-userid <account>
deploy/provision.sh add-client backtester   # one more key + bastion user
deploy/provision.sh status                  # fingerprints and what is pinned
```

Everything lands under `--root` (default `/srv/ib-gateway`, or
`$XDG_DATA_HOME/ib-gateway` when `/srv` is not writable) — **never in the
checkout**, so no credential is one `git add` away from a public repository.

- **Nothing publishes the IB API port.** The API has no authentication of its
  own, so reaching it must require a key rather than a route. The gateway opens
  it on the bastion's loopback with `ssh -R`; each client forwards it back with
  `ssh -L` under its own key. Only the bastion's ssh port is published, and on
  `127.0.0.1` unless `--bastion-bind` says otherwise.
- **Each key is restricted to one direction and one port**, in
  `authorized_keys`. Both `permitopen` *and* `permitlisten` are set on every
  key: they govern `-L` and `-R` respectively and **neither constrains the
  other**, so a key naming only one leaves the other direction unrestricted.
  The unused direction is pinned to `127.0.0.1:1`, which the unprivileged
  session user can neither bind nor be forwarded to. Verified against a running
  bastion, and pinned by `tests/unit/provision.bats`.
- **The bastion's host key is read from the `data/` that was just provisioned**
  and written into every `known_hosts`, so there is no first-connection window
  to get wrong. Clients run with `StrictHostKeyChecking yes`.
- **Credentials are files, never values.** Each is a `0600` file under
  `secrets/`, mounted at `/run/secrets/<name>` through compose `secrets:`, and
  named to the container with the `*_FILE` variable that `file_env` reads. The
  emitted `.env` holds no credential at all. `file_env` errors out when both
  `VAR` and `VAR_FILE` are set, so only the `_FILE` half is ever emitted.
- **It refuses to provision beside the live stack.** `inv_gateway` /
  `inv_bastion` running, or `--project inv_ibkr`, stops it: compose identifies a
  project by name, so an emitted stack sharing that name would adopt the running
  containers. `--force` proceeds; nothing is ever stopped either way.
- `secrets/tws_password` is left empty when no password is given
  interactively, and the script says so — loudly, twice. An empty secret is
  written as a bare newline, which `file_env` reads back as the empty string,
  so the gateway would otherwise start and fail its IB login.

All three images are published, so the script pulls rather than builds. It falls
back to building the bastion from `bastion/` when it cannot pull —
`ghcr.io/dennisdeh` is private, so run `docker login ghcr.io` first, and a
freshly bumped `IMAGE_VERSION` has no published tag until the next release.

> **The bastion refuses to start on a `data/` provisioned before 2026-08-27.**
> `sshd_config.d/*.conf` is now covered by the provisioning checksum — the files
> and a listing of the directory, so an added or removed drop-in is caught too,
> which no per-file hash can do. Data provisioned before that has no recorded
> listing, and the container stops rather than skipping the check. Re-run
> `deploy/provision.sh init` (or `bastion/provision.sh`) against the existing
> `data/`; it is idempotent and keeps the host keys, so no client's
> `known_hosts` changes.

## Provisioning the bastion `data/` directory

This is what `deploy/provision.sh` drives for you; the below is the manual
equivalent, and what the existing deployment was built with.

`data/` is gitignored and must exist before the bastion starts. It is created by
`bastion/provision.sh`, run *inside* the bastion image with `data/` bind-mounted
at `/data` (see the header comment in that script for the exact `docker run`).
The container hashes the provisioned `/etc/passwd`, `sshd_config`, the host keys
and — since 2026-08-27 — everything in `sshd_config.d/` plus a listing of that
directory, into `data/etc/ssh/bastion_provisioned_hash.sum`, and re-validates on
every start: editing any of it by hand makes the container refuse to start until
it is re-provisioned. That is intentional. The listing is hashed as well as the
files because a per-file hash cannot notice a drop-in being *added* or
*removed* — every recorded line still checks out — and `sshd_config` includes
whatever is in there.

## Recovery

- **Gateway will not log in.** Check IB's nightly restart window
  (`AUTO_RESTART_TIME` in `.env`), IB maintenance, and whether another session
  is holding the account. IB allows one session per account.
- **API port refuses connections but the container is up.** socat may have died;
  `run_socat.sh` restarts it in a loop after `SSH_RESTART` seconds. Check
  `docker logs inv_gateway` for the "Forking" line.
- **Settings changes have no effect.** `jts.ini` is only written when absent,
  and `CUSTOM_CONFIG=yes` disables templating entirely.
- **Never clean up with a bare `pkill socat` / `pkill -f ssh` on the host** —
  those patterns match other containers' helpers and your own tooling.
