# RUNBOOK

How to run, provision and recover the local stack. User-facing configuration is
documented in `template_README.md`; this file is about *this* deployment.

*Last updated: 2026-08-25*

## What runs here

| container | image | role |
|---|---|---|
| `inv_gateway` | `ghcr.io/dennisdeh/ib-gateway:latest` (built from `./latest`) | IB Gateway + IBC under Xvfb |
| `inv_bastion` | `dennisdeh/bastion:local-resolute` (built from `./bastion`) | SSH jump host for the tunnel |

Other services on this machine (`inv_visualisation`, `inv_db`, `inv_redis`,
`inv_ntfy`) consume the gateway's API port. **Restarting the gateway interrupts
them** — see the runtime rules in `CLAUDE.md`.

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

```bash
cd <repo root>            # $PWD-based mounts require this
docker compose config     # validate .env + wiring, starts nothing
docker compose up -d      # start
docker logs -f inv_gateway
docker compose down       # stop — interrupts every dependent service
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
