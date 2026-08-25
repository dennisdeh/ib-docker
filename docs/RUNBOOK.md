# RUNBOOK

How to run, provision and recover the local stack. User-facing configuration is
documented in `template_README.md`; this file is about *this* deployment.

*Last updated: 2026-08-25*

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

Other services on this machine (`inv_visualisation`, `inv_db`, `inv_redis`,
`inv_ntfy`) consume the gateway's API port.

> Both compose files declare `name: inv_ibkr`, so Compose treats them as the
> same project regardless of directory: a lifecycle command run in *this*
> repository acts on those live containers. Verified 2026-08-25 — `docker
> compose ps` here lists them. See `CLAUDE.md`.

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

Safe from anywhere, read-only:

```bash
docker logs -f inv_gateway
docker compose config      # validation only, starts nothing
```

## Provisioning the bastion `data/` directory

`data/` is gitignored and must exist before the bastion starts. It is created by
`bastion/provision.sh`, run *inside* the bastion image with `data/` bind-mounted
at `/data` (see the header comment in that script for the exact `docker run`).
The container hashes the provisioned `/etc/passwd` and `sshd_config` into
`data/etc/ssh/bastion_provisioned_hash.sum` and re-validates on every start:
editing those files by hand makes the container refuse to start until it is
re-provisioned. That is intentional.

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
