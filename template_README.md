# ib-docker

[![Build](https://github.com/dennisdeh/ib-docker/actions/workflows/on-push-n-pr.yml/badge.svg?branch=master)](https://github.com/dennisdeh/ib-docker/actions) [![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT) [![GitHub Issues](https://img.shields.io/github/issues/dennisdeh/ib-docker)](https://github.com/dennisdeh/ib-docker/issues) [![GitHub Repo stars](https://img.shields.io/github/stars/dennisdeh/ib-docker)](#repo-stats) [![GitHub forks](https://img.shields.io/github/forks/dennisdeh/ib-docker)](https://github.com/dennisdeh/ib-docker/network/members)

<img src="https://github.com/dennisdeh/ib-docker/blob/master/logo.png" height="300" class="center" alt="ib-docker"/>

## Credits

This project began as a fork of
[gnzsnz/ib-gateway-docker](https://github.com/gnzsnz/ib-gateway-docker) by
gnzsnz, itself built on earlier work by Emanuel Fernandes, and it keeps their
MIT licence and copyright — see [LICENSE](LICENSE). The bastion image is a fork
of [gnzsnz/docker-bastion](https://github.com/gnzsnz/docker-bastion). Thanks to
both.

It is now maintained independently: it does not track, sync from, or test
against those repositories, and issues found here are fixed here.

## What is it?

Three images that run Interactive Brokers' desktop software headless, with
nobody at the keyboard:

| image | what it is |
| --- | --- |
| [ib-gateway][1] | IB Gateway driven by IBC under Xvfb. The API is reached through socat, or through an ssh tunnel with no port published at all. |
| [tws-rdesktop][2] | Trader Workstation on an xrdp/xfce desktop, for the things only the full client can do. Same versions, same variables. |
| [bastion][3] | A hardened ssh jump host. The gateway opens the API port on it and each client dials back in under its own restricted key. |

One [docker-compose.yml](https://github.com/dennisdeh/ib-docker/blob/master/docker-compose.yml)
runs all three: `ib-gateway` and `tws` sit behind
[Compose profiles](#choosing-the-application) so you pick one, and the bastion
always starts. For a host that should simply *run* this rather than build it,
[`deploy/provision.sh`](#deploying) sets one up end to end from the published
images.

Between them they include:

- [IB Gateway](https://www.interactivebrokers.com/en/index.php?f=16457) ([stable](https://www.interactivebrokers.com/en/trading/ibgateway-stable.php) or [latest](https://www.interactivebrokers.com/en/trading/ibgateway-latest.php))
- Trader Workstation [TWS](https://www.interactivebrokers.com/en/trading/tws-offline-installers.php) ([stable](https://www.interactivebrokers.com/en/trading/tws-offline-stable.php) or [latest](https://www.interactivebrokers.com/en/trading/tws-offline-latest.php)), from `10.26.1h`
- [IBC](https://github.com/IbcAlpha/IBC) - to control TWS/IB Gateway (simulates user input).
- [Xvfb](https://www.x.org/releases/X11R7.6/doc/man/man1/Xvfb.1.xhtml) - a X11
  virtual framebuffer to run IB Gateway Application without graphics hardware.
- [x11vnc](https://wiki.archlinux.org/title/x11vnc) - a VNC server to interact
  with the IB Gateway user interface (optional, for development / maintenance purpose).
- xrdp/xfce enviroment for TWS. Build on top of [linuxserver/rdesktop](https://github.com/linuxserver/docker-rdesktop/).
- [socat](https://manpages.ubuntu.com/manpages/noble/en/man1/socat.1.html) a
  tool to accept TCP connection from non-localhost and relay it to IB Gateway
  from localhost (IB Gateway restricts connections to container's 127.0.0.1 by
  default).
- Optional remote [SSH tunnel](https://manpages.ubuntu.com/manpages/noble/en/man1/ssh.1.html)
  to provide secure connections for both IB Gateway and VNC. Only available for
  `10.19.2g-stable` and `10.25.1o-latest` or greater.
- A hardened [ssh bastion](https://github.com/dennisdeh/ib-docker/blob/master/bastion/README.md)
  to terminate that tunnel, published as an image of its own so a host can run
  the whole stack without building anything.
- Support parallel execution of `live` and `paper` trading mode.
- [Secrets](#credentials) support (latest `10.29.1e`, stable `10.19.2m` or greater)
- Experimental [aarch64](#aarch64-support) support, ex raspberry pi, M1,M2,M3,.., since `10.37.1l`/`10.39.1e`
- Execution of custom scripts during [star-up process](#start-up-scripts).
- Works well together with [Jupyter Quant](https://github.com/quantbelt/jupyter-quant)
  docker image.

## Where things are documented

| you want to | read |
| --- | --- |
| set a host up from the published images | [Deploying](#deploying) |
| configure a container | [Configuration](#configuration), [Ports](#ports) |
| reach the API from another container or machine | [Reaching the API](#reaching-the-api), [SSH Tunnel](#ssh-tunnel) |
| run or provision the ssh bastion by hand | [bastion/README.md](https://github.com/dennisdeh/ib-docker/blob/master/bastion/README.md) |
| change the image, and get the change published | [CONTRIBUTING.md](https://github.com/dennisdeh/ib-docker/blob/master/CONTRIBUTING.md) |
| operate, restart or recover a running stack | [docs/RUNBOOK.md](https://github.com/dennisdeh/ib-docker/blob/master/docs/RUNBOOK.md) |
| find out why something is the way it is | [docs/DECISIONS.md](https://github.com/dennisdeh/ib-docker/blob/master/docs/DECISIONS.md), [docs/OPEN_ITEMS.md](https://github.com/dennisdeh/ib-docker/blob/master/docs/OPEN_ITEMS.md) |

## Supported Tags

Three images are published — [IB gateway][1], [TWS][2] and the ssh bastion the
tunnel dials — for `linux/amd64` and `linux/arm64`, with the following tags:

| Image| Channel  | IB Gateway Version  | IBC Version      | Docker Tags                                    |
| --- | -------- | ------------------- | ---------------- | ---------------------------------------------- |
| [ib-gateway][1] | `latest` | `${LATEST_VERSION}` | `${LATEST_IBC}` | `latest` `${LATEST_MINOR}` `${LATEST_VERSION}` |
| [ib-gateway][1] |`stable` | `${STABLE_VERSION}` | `${STABLE_IBC}` | `stable` `${STABLE_MINOR}` `${STABLE_VERSION}` |
| [tws-rdesktop][2] | `latest` | `${LATEST_VERSION}` | `${LATEST_IBC}` | `latest` `${LATEST_MINOR}` `${LATEST_VERSION}` |
| [tws-rdesktop][2] |`stable` | `${STABLE_VERSION}` | `${STABLE_IBC}` | `stable` `${STABLE_MINOR}` `${STABLE_VERSION}` |
| [bastion][3] | — | — | — | `latest` `${BASTION_VERSION}` |

All tags are available in the container repository for [ib-gateway][1] and
[tws-rdesktop][2]. IB Gateway and TWS share the same version numbers and tags.

The two channels can carry **different IBC versions**, and the table reads each
one from that channel's own image rather than assuming they agree: a new IBC
release lands in the build templates first and reaches a channel when that
channel next moves. So a difference between the two rows is the normal state
between an IBC release and the next IB Gateway one, not a packaging mistake.

The bastion carries no IB version — it is the ssh jump host, and it changes on
its own schedule, so it is tagged with a version of its own. Publishing it
alongside the other two is what lets a host be set up without a checkout to
build anything from.

**These three are the whole stack.** Everything the sample
`docker-compose.yml` runs is built here from this checkout, and everything
`deploy/provision.sh` pulls is one of the three above — there is no fourth
image to find somewhere else. What they are built *on* is short enough to
state: `ubuntu` for the gateway and the bastion, and
[linuxserver/rdesktop](https://github.com/linuxserver/docker-rdesktop/) for the
TWS desktop, which is the only third-party image inside anything published.

## Deploying

Because all three images are published and public, a host needs neither a
checkout nor registry credentials to run this.
`deploy/provision.sh` sets one up end to end — the ssh keys, the bastion's
users, the secrets and the directory layout — and writes a compose file that
**pulls** rather than builds.

```bash
curl -fLO https://raw.githubusercontent.com/dennisdeh/ib-docker/master/deploy/provision.sh
chmod +x provision.sh
./provision.sh init --version ${LATEST_VERSION} --clients jupyter,research
```

Run it from a checkout instead and `--version` is read from the channel's
`Dockerfile`. `--help` lists every option; `add-client <name>` issues another
key later, and `status` prints what is provisioned. It is safe to re-run:
every step checks before it acts, and existing keys and secrets are kept.

Everything lands under `--root` — default `/srv/ib-gateway`, or
`$XDG_DATA_HOME/ib-gateway` where `/srv` is not writable — and **never in the
checkout**, so no credential is one `git add` away from a public repository:

| path | what |
|---|---|
| `docker-compose.yml` | image-only: no build context, no `$PWD` dependency |
| `.env` | non-secret settings; no credential is written here |
| `secrets/` | one `0600` file per secret, mounted at `/run/secrets` |
| `ssh/` | the gateway's own `~/.ssh` — key, `known_hosts`, `config` |
| `clients/<name>/` | one key bundle per client that dials in |
| `bastion/data/` | the bastion's provisioned `/etc` and `/home` |
| `tls/` | self-signed xrdp material, when TWS is selected |

**The only port the emitted stack publishes is the bastion's ssh port**, and on
`127.0.0.1` unless `--bastion-bind` says otherwise. Nothing else is reachable
from outside the host — see [Reaching the API](#reaching-the-api) for why, and
for how a client gets to it.

`init` offers to take the IB password interactively. If you decline, it writes
`secrets/tws_password` empty and says so twice: the gateway will start and then
fail its IB login until the file has a password in it. Either way, finish and
start it with:

```bash
cd /srv/ib-gateway
docker compose up -d
```

### Reaching the API

**The API port is not published, on purpose.** The IB API has no
authentication of its own, so anything that can reach the port can place
orders — reaching it should require a key, not merely a route to the host.
The gateway opens the port on the bastion's loopback with `ssh -R`, and each
client forwards it back with `ssh -L` under a key of its own:

```bash
# in the client container, or wherever your code runs
ssh -F /srv/ib-gateway/clients/jupyter/ssh_config -N jupyter-bastion
# then connect to 127.0.0.1:4002 - the paper API - inside that client
```

Each key is pinned in `authorized_keys` to one direction and one port. Note
that `permitopen` governs `-L` only and `permitlisten` governs `-R` only, and
neither constrains the other, so **both** are set on every key: a client can
open the API port and nothing else, and cannot bind a listener at all; the
gateway can publish the API port and nothing else, and cannot forward out to
anything the bastion can see. Neither can run a command or get a shell.

The bastion's host key is read from the `data/` that was just provisioned and
written into every `known_hosts`, so there is no first-connection window to
accept blindly — clients run with `StrictHostKeyChecking yes`.

### Secrets

Each secret is a file under `secrets/`, mounted at `/run/secrets/<name>` by
Compose and named to the container through its `*_FILE` variable — the same
mechanism described under [Credentials](#credentials) below. The generated
`.env` contains no credential at all. `file_env` refuses to start when both `VAR` and `VAR_FILE` are set, so
only the `_FILE` half is ever emitted.

### Upgrading

Pull the new tag and recreate. One thing needs care: the bastion validates a
checksum over its provisioned `/etc`, and since 2026-08-27 that covers
`sshd_config.d/` as well. A `data/` provisioned before then makes the
container refuse to start rather than skip the check — re-run
`provision.sh init` against it, which keeps the host keys, so no client's
`known_hosts` changes.

## How to use it?

If you would rather write your own compose file — or fold these services into
an existing stack — create a `docker-compose.yml` (or include ib-gateway
services on your existing one). The [sample file provided](https://github.com/dennisdeh/ib-docker/blob/master/docker-compose.yml)
can be used as starting point. Note that it **builds** from the channel
directories, which is how the images are developed; for a deployment, drop the
`build:` blocks and keep the `image:` lines, or use `deploy/provision.sh`
above, which emits exactly that. It carries both images in one file — an
`ib-gateway` service and a `tws` service — and `.env` picks which one runs, see
[Choosing the application](#choosing-the-application).

```yaml
name: algo-trader
services:
  ib-gateway:
    restart: always
    build:
      context: ./stable
      tags:
        - "ghcr.io/dennisdeh/ib-gateway:stable"
    image: ghcr.io/dennisdeh/ib-gateway:stable
    environment:
      TWS_USERID: ${TWS_USERID}
      TWS_PASSWORD: ${TWS_PASSWORD}
      TWS_PASSWORD_FILE: ${TWS_PASSWORD_FILE}
      TRADING_MODE: ${TRADING_MODE:-paper}
      TWS_SETTINGS_PATH: ${TWS_SETTINGS_PATH:-}
      TWS_ACCEPT_INCOMING: ${TWS_ACCEPT_INCOMING:-}
      TWS_MASTER_CLIENT_ID: ${TWS_MASTER_CLIENT_ID:-}
      READ_ONLY_API: ${READ_ONLY_API:-}
      VNC_SERVER_PASSWORD: ${VNC_SERVER_PASSWORD:-}
      TWOFA_TIMEOUT_ACTION: ${TWOFA_TIMEOUT_ACTION:-exit}
      BYPASS_WARNING: ${BYPASS_WARNING:-}
      AUTO_RESTART_TIME: ${AUTO_RESTART_TIME:-}
      AUTO_LOGOFF_TIME: ${AUTO_LOGOFF_TIME:-}
      TWS_COLD_RESTART: ${TWS_COLD_RESTART:-}
      SAVE_TWS_SETTINGS: ${SAVE_TWS_SETTINGS:-}
      RELOGIN_AFTER_TWOFA_TIMEOUT: ${RELOGIN_AFTER_TWOFA_TIMEOUT:-no}
      TWOFA_EXIT_INTERVAL: ${TWOFA_EXIT_INTERVAL:-60}
      TWOFA_DEVICE: ${TWOFA_DEVICE:-}
      EXISTING_SESSION_DETECTED_ACTION: ${EXISTING_SESSION_DETECTED_ACTION:-primary}
      ALLOW_BLIND_TRADING: ${ALLOW_BLIND_TRADING:-no}
      TIME_ZONE: ${TIME_ZONE:-Etc/UTC}
      TZ: ${TIME_ZONE:-Etc/UTC}
      CUSTOM_CONFIG: ${CUSTOM_CONFIG:-NO}
      JAVA_HEAP_SIZE: ${JAVA_HEAP_SIZE:-}
      SSH_TUNNEL: ${SSH_TUNNEL:-}
      SSH_OPTIONS: ${SSH_OPTIONS:-}
      SSH_ALIVE_INTERVAL: ${SSH_ALIVE_INTERVAL:-}
      SSH_ALIVE_COUNT: ${SSH_ALIVE_COUNT:-}
      SSH_PASSPHRASE: ${SSH_PASSPHRASE:-}
      SSH_REMOTE_PORT: ${SSH_REMOTE_PORT:-}
      SSH_USER_TUNNEL: ${SSH_USER_TUNNEL:-}
      SSH_RESTART: ${SSH_RESTART:-}
      SSH_VNC_PORT: ${SSH_VNC_PORT:-}
      START_SCRIPTS: ${START_SCRIPTS:-}
      X_SCRIPTS: ${X_SCRIPTS:-}
      IBC_SCRIPTS: ${IBC_SCRIPTS:-}
#    volumes:
#      - ${PWD}/jts.ini:/home/ibgateway/Jts/jts.ini
#      - ${PWD}/config.ini:/home/ibgateway/ibc/config.ini
#      - ${PWD}/tws_settings/:${TWS_SETTINGS_PATH:-/home/ibgateway/tws_settings}
#      - ${PWD}/ssh/:/home/ibgateway/.ssh
#      - ${PWD}/init-scripts:/home/ibgateway/init-scripts
    ports:
      - "127.0.0.1:4001:4003"
      - "127.0.0.1:4002:4004"
      - "127.0.0.1:5900:5900"

```

Create an .env on root directory. You can use the provided [.env-dist](https://github.com/dennisdeh/ib-docker/blob/master/.env-dist) as a starting point. Example .env file:

```bash
# which image to run: ib-gateway, tws, or both
IB_APP=ib-gateway
COMPOSE_PROFILES=${IB_APP}
TWS_USERID=myTwsAccountName
TWS_PASSWORD=myTwsPassword
# see credentials section
#TWS_PASSWORD_FILE
#TWS_USERID_PAPER=
#TWS_PASSWORD_PAPER=
#TWS_PASSWORD_PAPER_FILE=
# ib-gateway
#TWS_SETTINGS_PATH=/home/ibgateway/tws_settings
# tws
#TWS_SETTINGS_PATH=/config/tws_settings
TWS_SETTINGS_PATH=
TWS_ACCEPT_INCOMING=
TRADING_MODE=paper
READ_ONLY_API=no
VNC_SERVER_PASSWORD=myVncPassword
TWOFA_TIMEOUT_ACTION=restart
TWOFA_DEVICE=
BYPASS_WARNING=
AUTO_RESTART_TIME=11:59 PM
AUTO_LOGOFF_TIME=
TWS_COLD_RESTART=
SAVE_TWS_SETTINGS=
RELOGIN_AFTER_TWOFA_TIMEOUT=yes
EXISTING_SESSION_DETECTED_ACTION=primary
ALLOW_BLIND_TRADING=no
TIME_ZONE=Europe/Zurich
CUSTOM_CONFIG=
SSH_TUNNEL=
SSH_OPTIONS=
SSH_ALIVE_INTERVAL=
SSH_ALIVE_COUNT=
SSH_PASSPHRASE=
SSH_REMOTE_PORT=
SSH_USER_TUNNEL=
SSH_RESTART=
SSH_VNC_PORT=
#START_SCRIPTS=init-scripts/start_scripts
#X_SCRIPTS=init-scripts/x_scripts
#IBC_SCRIPTS=init-scripts/ibc_scripts

```

Once `docker-compose.yml` and `.env` are in place you can start the container with:

```bash
docker compose up -d
docker compose logs -f
```

To get a GUI you can use vnc for ib-gateway or RDP for TWS.

### Choosing the application

The sample `docker-compose.yml` defines both images: service `ib-gateway` runs
[ib-gateway][1], service `tws` runs [tws-rdesktop][2]. Each sits behind a
[Compose profile](https://docs.docker.com/compose/how-tos/profiles/) of the same
name, so only the one you select is created. `IB_APP` in `.env` is the switch:

```bash
# .env
IB_APP=ib-gateway        # IB Gateway, headless, VNC for the GUI
#IB_APP=tws              # TWS desktop, RDP for the GUI
#IB_APP=ib-gateway,tws   # both at once
COMPOSE_PROFILES=${IB_APP}
```

`COMPOSE_PROFILES` is the variable Compose itself reads; `IB_APP` exists so
there is one obviously named line to edit. The two services publish different
host ports — `4001/4002/5900` against `7496/7497/3370` — so `ib-gateway,tws`
starts both without a collision.

Naming a service on the command line enables its profile for that command, so
`docker compose build ib-gateway` works whatever `IB_APP` is set to. A bare
`docker compose build` only builds the selected service.

Looking for help? Please keep reading below — *Troubleshooting socat and
ssh* and *Security Considerations* cover the usual problems — and open an
[issue](https://github.com/dennisdeh/ib-docker/issues) if that does not settle
it.

## Configuration

All environment variables are common between ibgateway and TWS image, unless specifically stated. The container can be configured with the following environment variables:

| Variable | Description | Default |
| --- | --- | --- |
| `TWS_USERID`  | The TWS **username**. |   |
| `TWS_PASSWORD` | The TWS **password**.  |   |
| `TWS_PASSWORD_FILE` | The file containing TWS **password**. See [credentials section](#credentials). |   |
| `TRADING_MODE` | **live** or **paper**. From `10.26.1k` it supports **both** which will start ib-gateway or TWS in live AND paper mode in parallel within the container. | **paper** |
| `TWS_USERID_PAPER`  | If `TRADING_MODE=both`, then this is required to pass paper account user  | **not defined** |
| `TWS_PASSWORD_PAPER` | If `TRADING_MODE=both`, then this is required to pass paper account password  | **not defined**  |
| `TWS_PASSWORD_PAPER_FILE` | If `TRADING_MODE=both`, then this is required to pass paper account password. See [credentials section](#credentials).  | **not defined**  |
| `READ_ONLY_API`  | **yes** or **no**. [See IBC documentation](https://github.com/IbcAlpha/IBC/blob/master/userguide.md)  | **not defined** |
| `VNC_SERVER_PASSWORD`  | VNC server password. If not defined, then VNC server will NOT start. Specific to ibgateway, ignored by TWS. See [credentials section](#credentials). | **not defined** (VNC disabled) |
| `VNC_SERVER_PASSWORD_FILE`  | VNC server password. If not defined, then VNC server will NOT start. Specific to ibgateway, ignored by TWS. | **not defined** (VNC disabled) |
| `TWOFA_TIMEOUT_ACTION`      | 'exit' or 'restart', set to 'restart if you set `AUTO_RESTART_TIME`. See IBC [documentation](https://github.com/IbcAlpha/IBC/blob/master/userguide.md#second-factor-authentication)  | exit  |
| `TWOFA_DEVICE` | second factor authentication device. See IBC [documentation](https://github.com/IbcAlpha/IBC/blob/c98d0bcc2ead9b8ab3900a23a707f01f8fd7dfbc/resources/config.ini#L104) | **not defined** |
| `TWOFA_EXIT_INTERVAL` | It controls how long (in seconds) IBC waits for login to complete after the user acknowledges the second factor authentication. See [IBC documentation](https://github.com/IbcAlpha/IBC/blob/38593af5193ccd634aa226cc66242adc8718b653/resources/config.ini#L147) | 60 seconds |
| `BYPASS_WARNING` | Settings relate to the corresponding 'Precautions' checkboxes in the API section of the Global Configuration dialog. Accepted values `yes`, `no` if not set, the existing TWS/Gateway configuration is unchanged  | **not defined**                                      |
| `AUTO_RESTART_TIME`  | time to restart IB Gateway, does not require daily 2FA validation. format hh:mm AM/PM. See IBC [documentation](https://github.com/IbcAlpha/IBC/blob/master/userguide.md#ibc-user-guide) | **not defined**  |
| `AUTO_LOGOFF_TIME` | Auto-Logoff: at a specified time, TWS shuts down tidily, without restarting   | **not defined**   |
| `TWS_COLD_RESTART` | IBC >= 3.19 set this value to <hh:mm> | **not defined** |
| `SAVE_TWS_SETTINGS`  | automatically save its settings on a schedule of your choosing. You can specify one or more specific times, ex `SaveTwsSettingsAt=08:00   12:30 17:30`  | **not defined**  |
| `RELOGIN_AFTER_TWOFA_TIMEOUT` | support relogin after timeout. See IBC [documentation](https://github.com/IbcAlpha/IBC/blob/master/userguide.md#second-factor-authentication) | no  |
| `EXISTING_SESSION_DETECTED_ACTION` | Set Existing Session Detected Action. See IBC [documentation](https://github.com/dennisdeh/ib-docker/blob/master/latest/config/ibc/config.ini.tmpl#L296-L329) | primary |
| `ALLOW_BLIND_TRADING` | TWS displays a dialog to warn you against blind trading.See IBC [documentation](https://github.com/IbcAlpha/IBC/blob/c98d0bcc2ead9b8ab3900a23a707f01f8fd7dfbc/resources/config.ini#L702)| no |
| `TIME_ZONE`  | Support for timezone, see your TWS jts.ini file for [valid values](https://ibkrguides.com/tws/usersguidebook/configuretws/configgeneral.htm) on a [tz database](https://en.wikipedia.org/wiki/List_of_tz_database_time_zones). This sets time zone for IB Gateway. If jts.ini exists it will not be set. if `TWS_SETTINGS_PATH` is set and stored in a volume, jts.ini will already exists so this will not be used. Examples `Europe/Paris`, `America/New_York`, `Asia/Tokyo` | "Etc/UTC"  |
| `TWS_SETTINGS_PATH` | Settings path used by IBC's parameter `--tws_settings_path`. Use with a volume to preserve settings in the volume. If `TRADING_MODE=both` this will be the prefix four your settings. ex `/config/tws_settings_live` and `/config/tws_settings_paper`. |  |
| `TWS_ACCEPT_INCOMING` | See IBC documentation, possible values `accept`, `reject`, `manual` | `manual` |
| `TWS_MASTER_CLIENT_ID` | See IBC [documentation](https://github.com/IbcAlpha/IBC/blob/b866a263afec948c70352ce077e1560f3ad2b152/resources/config.ini#L349) | **not defined** |
| `CUSTOM_CONFIG` | If set to `yes`, then `run.sh` will not generate config files using env variables. You should mount config files. Use with care and only if you know what you are doing. | NO |
| `JAVA_HEAP_SIZE` | Set Java heap, default 768MB, TWS might need more. Proposed value 1024. Enter just the number, don't enter units, ex mb. See [Increase Memory Size for TWS](https://ibkrguides.com/tws/usersguidebook/priceriskanalytics/custommemory.htm) | **not defined**  |
| `SSH_TUNNEL` | If set to `yes` then `socat` won't start, instead a remote ssh tunnel is started. if set to `both` then `socat` AND remote ssh tunnel are started. SSH keys should be provided to container through ~/.ssh volume.  | **not defined**                                      |
| `SSH_OPTIONS` | additional options for [ssh](https://manpages.ubuntu.com/manpages/noble/en/man1/ssh.1.html) client | **not defined** |
| `SSH_ALIVE_INTERVAL`   | [ssh](https://manpages.ubuntu.com/manpages/noble/en/man1/ssh.1.html) `ServerAliveInterval` setting. Don't set it in `SSH_OPTIONS` as this behavior is undefined. | 20   |
| `SSH_ALIVE_COUNT`  | [ssh](https://manpages.ubuntu.com/manpages/noble/en/man1/ssh.1.html) `ServerAliveCountMax` setting. Don't set it in `SSH_OPTIONS` as this behavior is undefined. | **not defined** |
| `SSH_PASSPHRASE`   | passphrase for ssh keys. If set the container will start ssh-agent and add ssh keys   | **not defined**   |
| `SSH_PASSPHRASE_FILE`   | file containing passphrase for ssh keys. If set the container will start ssh-agent and add ssh keys   | **not defined**   |
| `SSH_REMOTE_PORT`   | **Container-local** port the tunnel forwards to - *not* the port opened on the server, which is always the API port. Leave it unset unless the API listens somewhere other than its default port; setting it to the port you want on the server does not work. If `TRADING_MODE=both` it is reset to the paper port `4002/7498`.  | Same port than IB gateway `4001/4002` or `7497/7498` |
| `SSH_USER_TUNNEL`   | `user@server` to connect to    | **not defined**   |
| `SSH_RESTART`  | Number of seconds to wait before restarting tunnel in case of disconnection.  | 5  |
| `SSH_VNC_PORT`   | If set, a tunnel is created that opens port `5900` **on the server** and forwards it to `SSH_VNC_PORT` **inside the container** - so it must be where x11vnc listens (`5900`). Specific to ibgateway, ignored by TWS.  | **not defined**   |
| `SSH_RDP_PORT`  | If set, a tunnel is created that opens port `3389` **on the server** and forwards it to `SSH_RDP_PORT` **inside the container** - so it must be where xrdp listens (`3389`). Specific to TWS, ignored by ibgateway.  | **not defined** |
| `PUID` | User `uid` for user `abc` (linuxserver default user name). Specific to TWS, ignored by ibgateway. | 1000   |
| `PGID` | User `gid` for user `abc` (linuxserver default user name). Specific to TWS, ignored by ibgateway.  | 1000   |
| `PASSWD` | Password for user `abc` (linuxserver default user name). Specific to TWS, ignored by ibgateway. | abc  |
| `PASSWD_FILE` | File containing password for user `abc` (linuxserver default user name). Specific to TWS, ignored by ibgateway. See [credentials section](#credentials). | abc  |
| `START_SCRIPTS` | Directory with bash scripts to run **before** X environment is up. See [start-up scripts](#start-up-scripts) | **not defined** |
| `X_SCRIPTS` | Directory with bash scripts to run **after** X environment is running. See [start-up scripts](#start-up-scripts) | **not defined** |
| `IBC_SCRIPTS` | Directory with bash scripts to run **after** IBC is running. See [start-up scripts](#start-up-scripts) | **not defined** |

## Ports

The following ports will be ready for usage on the ib-gateway container and docker host:

| Port | Description  |
| ---- | ---- |
| 4003 | TWS API port for live accounts. Through socat, internal TWS API port 4001. Mapped **externally** to 4001 in sample `docker-compose.yml`.  |
| 4004 | TWS API port for paper accounts. Through socat, internal TWS API port 4002. Mapped **externally** to 4002 in sample `docker-compose.yml`. |
| 5900 | When `VNC_SERVER_PASSWORD` was defined, the VNC server port. |

TWS image uses the following ports

| Port | Description   |
| ---- | --- |
| 7498 | TWS API port for live accounts. Through socat, internal TWS API port 7496. Mapped **externally** to 7496 by the `tws` service of the sample `docker-compose.yml`.  |
| 7499 | TWS API port for paper accounts. Through socat, internal TWS API port 7497. Mapped **externally** to 7497 by the `tws` service of the sample `docker-compose.yml`. |
| 3389 | Port for RDP server. Mapped **externally** to 3370 by the `tws` service of the sample `docker-compose.yml`.  |

The bastion uses one port, and it is the only one in the sample file that is
*meant* to be reachable:

| Port | Description   |
| ---- | --- |
| 22 | sshd. Mapped **externally** to `SSH_LISTEN_PORT` (`22222` in `.env-dist`) by the `bastion` service. This is the port a tunnel dials; nothing on it gets a shell. |

Every host-side number above is a default. In the sample
`docker-compose.yml` they are read from `.env` — `PORT_HOST_TWS_LIVE`,
`PORT_HOST_TWS_PAPER` and `PORT_HOST_VNC_SERVER` for the gateway,
`PORT_HOST_RDESKTOP_LIVE`, `PORT_HOST_RDESKTOP_PAPER` and `PORT_HOST_RDP` for
TWS, `SSH_LISTEN_PORT` for the bastion — so two stacks can run side by side
without editing the compose file. See
[.env-dist](https://github.com/dennisdeh/ib-docker/blob/master/.env-dist).

Utility [socat](https://manpages.ubuntu.com/manpages/noble/en/man1/socat.1.html) is used to publish TWS API port from container's `127.0.0.1:4001/4002` to container's `0.0.0.0:4003/4004`, the sample `docker-compose.yml` maps ports to the host back to `4001/4002`. This way any application can use the "standard" IB Gateway ports. For TWS `127.0.0.1:7496/7497` to container's `0.0.0.0:7498/7499`, and the `tws` service will map ports to host back to `7496/7497`.

Note that with the above `docker-compose.yml`, ports are only exposed to the docker host (127.0.0.1), but not to the host network. To expose it to the host network change the port mappings on accordingly (remove the '127.0.0.1:'). **Attention**: See [Leaving localhost](#leaving-localhost)

## Using TWS

From `10.26.1h` it's possible to run TWS in a container. [tws-rdesktop](https://github.com/dennisdeh/ib-docker/pkgs/container/tws-rdesktop) image provides a desktop environment that allows to use TWS.

### Performance considerations for TWS

[tws-rdesktop](https://github.com/dennisdeh/ib-docker/pkgs/container/tws-rdesktop) has the following recomended settings.

On the `tws` service in [docker-compose.yml](https://github.com/dennisdeh/ib-docker/blob/master/docker-compose.yml):

- set `/dev/dri:/dev/dri`
- shm_size: "1gb"
- `seccomp:unconfined`
- `JAVA_HEAP_SIZE`, depending your TWS you might need to increase it. See [Increase Memory Size for TWS](https://ibkrguides.com/tws/usersguidebook/priceriskanalytics/custommemory.htm)
- Volumes, set a volume for `/tmp`. ex `tws_tmp:/tmp`
- Volumes, set a volumen for `/config`

The start up script will disable xfce compositing, as this has a significant impact on performance.

## Customizing the image

Most if not all of the settings needed to run IB Gateway in a container are available as environment variables.

However, if you need to go beyond what's available, the image can be customized by overwriting the default configuration files with custom ones. To do this you must set environment variable `CUSTOM_CONFIG=yes`. By setting `CUSTOM_CONFIG=yes` `run.sh` script will not replace environment variables on config files. You must provide config files ready to be used by IB gateway/TWS and IBC, please make sure that you are familiar with [IBC](https://github.com/IbcAlpha/IBC/blob/master/userguide.md) settings.

Image IB Gateway and IBC config file locations:

| App  | Config file  | Default  |
| --- | --- | --- |
| IB Gateway | /home/ibgateway/Jts/jts.ini    | [jts.ini](https://github.com/dennisdeh/ib-docker/blob/master/image-files/config/ibgateway/jts.ini.tmpl) |
| IBC  | /home/ibgateway/ibc/config.ini | [config.ini](https://github.com/dennisdeh/ib-docker/blob/master/image-files/config/ibc/config.ini.tmpl) |

For TWS image config file locations are:

| App | Config file  | Default  |
| --- | --- | --- |
| TWS | /opt/ibkr/jts.ini   | [jts.ini](https://github.com/dennisdeh/ib-docker/blob/master/image-files/config/ibgateway/jts.ini.tmpl) |
| IBC | /opt/ibc/config.ini | [config.ini](https://github.com/dennisdeh/ib-docker/blob/master/image-files/config/ibc/config.ini.tmpl) |

Sample settings:

```yaml
...
    environment:
      - CUSTOM_CONFIG: yes
...
    volumes:
      - ${PWD}/config.ini:/home/ibgateway/ibc/config.ini
      - ${PWD}/jts.ini:/home/ibgateway/Jts/jts.ini # for IB Gateway
      - ${PWD}/jts.ini:/opt/ibkr/jts.ini # for TWS
      - ${PWD}/config.ini:/opt/ibc/config.ini # for TWS
...
```

### Preserve settings across containers

You can preserve IB Gateway configuration by setting environment variable
`$TWS_SETTINGS_PATH` and setting a volume

```yaml
...
    environment:
      - TWS_SETTINGS_PATH: /home/ibgateway/tws_settings # IB Gateway
      - TWS_SETTINGS_PATH: /config/tws_settings # tws rdesktop
...
    volumes:
      - ${PWD}/tws_settings:/home/ibgateway/tws_settings # IB Gateway
      - ${PWD}/config:/config # for TWS we use linuxserver /config volume
...

```

For TWS it's recommended to use `TWS_SETTINGS_PATH`, as there is a good amount
of data written to disk.

**Important**: when you save your config in a volume, file `jts.ini` will be
saved. `TIME_ZONE` will only be applied to `jts.ini` if the file does not
exists (first run) but not once the file exists. This is to avoid overwriting
your settings.

## Start-up scripts

You can run scripts during start up to automate tasks or install additional
tools. This can be done by setting environment variables `START_SCRIPTS`,
`X_SCRIPTS` and `IBC_SCRIPTS` with a path containing start-up scripts.
Scripts files should have `.sh` extension. Files will be executed in
order, so `00-script.sh` will be executed before that `99-other-script.sh`.
Start-up directory should be available in the container through a volume.

For example for `ibgateway`:

```bash
# .env file
START_SCRIPTS=init-scripts/start_scripts
X_SCRIPTS=init-scripts/x_scripts
IBC_SCRIPTS=init-scripts/ibc_scripts
```

and a volume in `docker-compose.yml`

```yaml
  volume:
    - ${PWD}/init-scripts:/home/ibgateway/init-scripts
```

For TWS you can set your `.env` file as in the example and create a directory
with your scripts in `/config/init-scripts/`. In TWS `$HOME=/config/`, while
ib-gateway uses `$HOME=/home/ibgateway`.

The start up process will search for start-up scripts in `$HOME/START_SCRIPTS`,
`$HOME/X_SCRIPTS` and `$HOME/IBC_SCRIPTS`.

Scripts in directory `$HOME/START_SCRIPTS` will run before the X environment is
up. Scripts in `$HOME/X_SCRIPTS` will run once X environment is up, and
`$HOME/IBC_SCRIPTS` once IBC runs. Take into account that scripts will run as
soon as possible, so you might need to wait for X environment to be fully up or
IBC to complete ibgateway/TWS start-up process.

## Security Considerations

### Leaving localhost

The IB API protocol is based on an unencrypted, unauthenticated, raw TCP socket
connection between a client and the IB Gateway. If the port to IB API is open
to the network, every device on it (including potential rogue devices) can access
your IB account via the IB Gateway.

Because of this, the default `docker-compose.yml` only exposes the IB API port
to the **localhost** on the docker host, but not to the whole network.

If you want to connect to IB Gateway from a remote device, consider adding an
additional layer of security (e.g. TLS/SSL or SSH tunnel) to protect the
'plain text' TCP sockets against unauthorized access or manipulation.

The strongest of the configurations below is the last one, and
[Deploying](#deploying) sets it up for you: no API port published anywhere,
reached only through a key that is restricted to that one port.

#### Possible IB API port configurations

Some examples of possible configurations

- Available to `localhost`, this is the default setup provided in [docker-compose.yml](https://github.com/dennisdeh/ib-docker/blob/master/docker-compose.yml).
Suitable for testing. It does not expose API port to host network, host must be trusted.
- Available to the host network. Unsecure configuration, suitable for short
  tests in a secure network. **Not recommended**.

  ```yaml
  ports:
    - "4001:4003"
    - "4002:4004"
    - "5900:5900"
  ```

- Available for other services in same docker network. Services with access to
  `trader` network can access IB Gateway through hostname `ib-gateway` (same
  than service name). Secure setup, although host should be trusted.

  ```yaml
  services:
    ib-gateway:
      networks:
        - trader
  #    ports: # commented out
  #      - "4001:4003"
  #      - "4002:4004"
  #      - "5900:5900"
  networks:
    trader:
  ```

- SSH Tunnel, enable ssh tunnel as explained in [ssh tunnel](#ssh-tunnel)
  section. This will only make IB API port available through a secure SSH
  tunnel. Secure option if utilized correctly.

### SSH Tunnel

You can optionally setup an SSH tunnel to avoid exposing IB Gateway port. The
container DOES NOT run an SSH server (sshd), what it does is to create a
[remote tunnel](https://manpages.ubuntu.com/manpages/noble/en/man1/ssh.1.html)
using ssh client. So basically it will connect to an ssh server and expose IB
Gateway port there.

The bastion that terminates the tunnel ships with this repository — it is the
[bastion][3] image and the third service in the sample `docker-compose.yml`, so
there is nothing separate to install. An example setup runs the gateway with
that bastion as a sidecar and a client such as
[jupyter-quant](https://github.com/quantbelt/jupyter-quant) beside it, which
together make a working algorithmic trading environment. IB Gateway opens a
**remote** port on the bastion and listens on it; the client opens a **local**
port tunnelled into the bastion on that same port. The pair of tunnels puts the
IB API inside the client container, ready for
[ib_async](https://github.com/ib-api-reloaded/ib_async) — the maintained
successor to [ib_insync](https://github.com/erdewit/ib_insync), which is
archived. The only port reachable from outside is the bastion's, which is
publickey-only, gives no shell, and is described in
[bastion/README.md](https://github.com/dennisdeh/ib-docker/blob/master/bastion/README.md).

Sample ssh tunnels for reference.

```bash
# on ib gateway - this is managed by the container
ssh -NR 4001:localhost:4001 ibgateway@bastion
# on juypter-quant container.
eval $(ssh-agent) # start agent
ssh-add # add keys to agent
#  -f will send it to foreground
ssh -o ServerAliveInterval=20 -o ServerAliveCountMax=3 -fNL 4001:localhost:4001 jupyter@bastion
# on desktop connect to VNC
ssh -o ServerAliveInterval=20 -o ServerAliveCountMax=3 -NL 5900:localhost:5900 trader@bastion
```

It would look like this

```text
       _____________
      |  IB Gateway | \   :4001
       -------------  |
                      |
      _____________   |
      | SSH Bastion | /   :4001
      -------------   \
                       |
                       |
      _______________  |
     | Jupyter Quant |/  :4001
      ---------------
```

`ib-docker` is using `ServerAliveInterval` and `ServerAliveCountMax`
ssh settings to keep the tunnel open. Additionally it will restart the tunnel
automatically if it's stopped, and will keep trying to restart it.

**Minimal ssh tunnel setup**:

- `SSH_TUNNEL`: set it to `yes`. This will NOT start `socat` and only start an
  ssh tunnel.
- `SSH_USER_TUNNEL`: The user name that ssh should use. It should be in the
  form `user@server`
- `SSH_PASSPHRASE`: Not mandatory, but strongly recommended. If set it will
  start `ssh-agent` and add ssh keys to agent. `ssh` will use `ssh-agent`.

**Restrict the key on the server, in `authorized_keys`.** A tunnel key needs no
shell and no other port, and saying so takes two options that are easy to get
half right: `permitopen` governs `-L` only, `permitlisten` governs `-R` only,
and **neither constrains the other**, so a key that names one of them leaves
the other direction wide open. Set both on every key, pinning the direction you
do not use to something unbindable:

```text
# the gateway's key: may publish the API port, may forward nowhere
restrict,port-forwarding,permitlisten="127.0.0.1:4002",permitopen="127.0.0.1:1" ssh-ed25519 AAAA...

# a client's key: may reach the API port, may publish nothing
restrict,port-forwarding,permitopen="127.0.0.1:4002",permitlisten="127.0.0.1:1" ssh-ed25519 AAAA...
```

`deploy/provision.sh` writes exactly these lines for you — see
[Reaching the API](#reaching-the-api).

In addition to the environment variables listed above you need to pass ssh keys
to `ib-docker` container. This is achieved through a volume mount

```yaml
...
    volumes:
      - ${PWD}/ssh:/home/ibgateway/.ssh # IB Gateway
      - ${PWD}/config/ssh:/config/.ssh # TWS
...
```

TWS image will search ssh keys on `HOME` directory, so store keys on `/config/.ssh`

Make sure that:

- you copy ssh keys with a standard name, ex ~/.ssh/id_rsa, ~/.ssh/id_ecdsa,
  ~/.ssh/id_ecdsa_sk, ~/.ssh/id_ed25519, ~/.ssh/id_ed25519_sk, or ~/.ssh/id_dsa
- keys should have proper permissions. ex `chmod 600 -R $PWD/ssh/*`
- you would need a `$PWD/ssh/known_hosts` file. Or pass `SSH_OPTIONS=-o
  StrictHostKeyChecking=no`, although this last option is **NOT recommended**
  for a production environment.
- and please make sure that you are familiar with
  [ssh tunnels](https://manpages.ubuntu.com/manpages/noble/en/man1/ssh.1.html)

### Credentials

This image does not contain nor store any user credentials.

They are provided as environment variable during the container startup and
the host is responsible to properly protect it.

From `10.29.1e` and `10.19.2m` it's possible to use `docker secrets`. If the
`_FILE` environment variable is defined, then that file will be used to get
credentials.

Sample `docker-compose.yml`:

```yml
name: algo-trader
services:
  ib-gateway:
  ...
  environment:
    ...
    TWS_PASSWORD_FILE: /run/secrets/tws_password
    SSH_PASSPHRASE_FILE: /run/secrets/ssh_passphrase
    VNC_SERVER_PASSWORD_FILE: /run/secrets/vnc_password
    ...
  secrets:
    - tws_password
    - ssh_passphrase
    - vnc_password
  ...
secrets:
  tws_password:
    file: tws_password.txt
  ssh_passphrase:
    file: ssh_password.txt
  vnc_password:
    file: vnc_password.txt

```

The repository's own [docker-compose.yml](https://github.com/dennisdeh/ib-docker/blob/master/docker-compose.yml)
is a full working example of both: it carries an `ib-gateway` service, a `tws`
service and the bastion in one file. It takes credentials from the environment,
because it is the file the image is *developed* with. For a deployment, use
[Deploying](#deploying) instead: it emits a compose file that uses `secrets:`
throughout and writes no credential into `.env` at all.

### RDP

[tws-rdesktop][2] will create a new TLS certificate every time the container
starts, so your RDP client cannot trust it. Supply your own instead: mount
`key.pem` and `cert.pem` at `/etc/xrdp/`, plus an empty `keylock` file at
`/keylock` to stop the container generating one. `deploy/provision.sh` does
this for you — it writes a self-signed pair into `tls/` and mounts all three
— see [Deploying](#deploying).

## Troubleshooting socat and ssh

In case you experience problems with the API connection, you can restart the `socat` process

```bash
docker exec -it algo-trader-ib-gateway-1 pkill -x socat
```

That name is Compose's default, `<project>-<service>-<n>`, matching the
`name: algo-trader` sample above. The repository's own `docker-compose.yml`
sets `container_name`, so there the container is just `ib-gateway` — check with
`docker compose ps` before copying the command.

After `SSH_RESTART` seconds socat will restart the connection. If `SSH_RESTART`
is not set, by default the restart period will be 5 seconds.

For ssh tunnel,

```bash
docker exec -it algo-trader-ib-gateway-1 pkill -x ssh
```

The ssh tunnel will restart after 5 seconds if `SSH_RESTART` is not set, or the
value in seconds defined in `SSH_RESTART`.

## aarch64 support

This is experimental, so expect bugs. Please check
[open issues](https://github.com/dennisdeh/ib-docker/issues) before opening one, and
include what you ran and what the container logged — "it does not work for me"
cannot be acted on.

To use aarch64 you just need to run:

```bash
# set IB_APP in .env to ib-gateway or tws, then
docker compose up -d
```

Compose selects the aarch64 image; the manifest carries both architectures.

The aarch64 image installs Interactive Brokers' own `arm` installer, so a
channel can only publish `linux/arm64` for a version whose
[release](https://github.com/dennisdeh/ib-docker/releases) carries the
`ibgateway-<version>-standalone-linux-arm.sh` asset. Releases from
`stable@10.45.1h` and `latest@10.47.1e` onward all carry it, and both published
channels are on such a version, so both are published for `linux/amd64` and
`linux/arm64`. A handful of older releases are x64 only.

## IB Gateway installation files

Note that the
[Dockerfile.template](https://github.com/dennisdeh/ib-docker/blob/master/Dockerfile.template)
**does not download IB Gateway installer files from IB homepage but from the
[github-releases](https://github.com/dennisdeh/ib-docker/releases) of this
project**.

This is because it shall be possible to (re-)build the image, targeting a
specific Gateway version,
but IB only provide download links for the `latest` or `stable` version (there
is no 'old version' download archive).

The installer files stored on
[releases](https://github.com/dennisdeh/ib-docker/releases) have been
downloaded from IB homepage and renamed to reflect the version.

Each release here carries **two** installers, `…-standalone-linux-x64.sh` and
`…-standalone-linux-arm.sh`, and the build picks by architecture — every IB
installer bundles the JRE for its own, so the x64 one cannot install on
aarch64. A version whose release predates that and carries only the x64 asset
can be built for `linux/amd64` only.

If you would rather fetch the installer from IB directly, or use a copy you
already have, change the download in
[Dockerfile.template](https://github.com/dennisdeh/ib-docker/blob/master/Dockerfile.template).
It is not a single `curl` line — it selects the file and verifies it:

```docker
if [ "$(uname -m)" = "aarch64" ]; then ib_arch=arm; else ib_arch=x64; fi && \
ib_file="ibgateway-${IB_GATEWAY_VERSION}-standalone-linux-${ib_arch}.sh" && \
curl -sSOLf "${IB_GATEWAY_RELEASE_URL}/${ib_file}" && \
curl -sSOLf "${IB_GATEWAY_RELEASE_URL}/${ib_file}.sha256" && \
sha256sum --check "./${ib_file}.sha256" && \
```

Repointing `ARG IB_GATEWAY_RELEASE_URL` is enough if the new location serves the
matching `.sha256` beside the installer; drop the second `curl` and the
`sha256sum --check` line as well if it does not. A build that fails *at* the
checksum step usually means the release asset is missing rather than that the
Dockerfile is wrong — `curl -sSOLf` fails on a 404 instead of saving the error
page, so an unexpected filename shows up there.

### How to build locally step by step

1. Clone the repository. `latest/` and `stable/` are ready-to-build contexts,
   one IB Gateway version each, generated by `update.sh` from the templates:

    ```bash
    git clone https://github.com/dennisdeh/ib-docker
    cd ib-docker
    docker build -t ib-gateway:local ./latest
    ```

   That is the whole of it when the version you want has a release here. Through
   Compose it is `docker compose build --pull ib-gateway`; name the service,
   because the two applications sit behind profiles.

1. To use an installer of your own, put it in the channel directory and replace
   the download with a `COPY`. `Dockerfile.template` marks the spot:

   ```docker
   # Use this instead of "RUN curl .." to install a local file:
   #COPY ibgateway-${IB_GATEWAY_VERSION}-standalone-linux-x64.sh .
   ```

   Name the file so `${IB_GATEWAY_VERSION}` matches `ENV IB_GATEWAY_VERSION` in
   the Dockerfile, and remove the `curl`/`sha256sum --check` lines shown above
   along with it.

1. IBC is verified against a **digest pinned in the Dockerfile**, because IBC
   publishes no checksum file. `ARG IBC_SHA256` must move whenever
   `ENV IBC_VERSION` does, or the build stops at the check — which is the
   intended behaviour, not a bug. `sha256sum IBCLinux-<version>.zip` gives the
   value to paste in.

1. Edit `Dockerfile.template` and `image-files/`, never the channel copies, then
   regenerate. A change written into `latest/` or `stable/` is destroyed by the
   next release run, silently:

    ```bash
    ./update.sh latest ${LATEST_VERSION}
    ./update.sh stable ${STABLE_VERSION}
    ```

1. To build the other architecture on an x86 machine, register the emulator
   once and pass `--platform`. Expect it to be slow — most of it is the IB
   installer under emulation:

    ```bash
    docker run --privileged --rm tonistiigi/binfmt --install arm64
    docker build --platform linux/arm64 -t ib-gateway:arm64 ./latest
    ```

See [CONTRIBUTING.md](https://github.com/dennisdeh/ib-docker/blob/master/CONTRIBUTING.md)
for the lint and test commands a change is expected to pass.

[1]: https://github.com/users/dennisdeh/packages/container/package/ib-gateway "ib-gateway"
[2]: https://github.com/dennisdeh/ib-docker/pkgs/container/tws-rdesktop "tws-rdesktop"
[3]: https://github.com/dennisdeh/ib-docker/pkgs/container/bastion "bastion"

## Repo stats

Repository stars overtime.

[![Stargazers over time](https://starchart.cc/dennisdeh/ib-docker.svg?variant=adaptive)](https://starchart.cc/dennisdeh/ib-docker)
