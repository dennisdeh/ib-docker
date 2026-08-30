# SSH Bastion

Fork of the [docker-bastion](https://github.com/gnzsnz/docker-bastion) project.

Dockerized SSH bastion :japanese_castle:, with hardened defaults. An SSH bastion is a jump server accessible from the Internet that gives access to services in a private network. Once a bastion is in place you can access private network services through it.

Features:

- Implement sensible hardened SSH configuration
- Mount critical data as READ-ONLY.
- It creates hash signatures of passwd, sshd_config, the host keys and everything in `sshd_config.d/` — plus a listing of that directory, so a drop-in that is added or removed is caught too, which a per-file hash cannot see. Every time the container is started it validates them and refuses to start on a mismatch.
- Disabled TTY, it can only be used as a jump host a.k.a bastion.
- Optional TOTP/MFA
- Support for SSH certificate authority (CA)
- Support for scp, sftp, rsync, port forwarding through bastion and from/to bastion.
- Fully customizable.

The image is published as `ghcr.io/dennisdeh/bastion` for `linux/amd64` and
`linux/arm64`, tagged `latest` and with the `ARG IMAGE_VERSION` this
`Dockerfile` declares. In this repository it is one of the three services in
the root `docker-compose.yml`, and `deploy/provision.sh` provisions and starts
it for you — see the *Deploying* section of the top-level `README.md`. The
steps below are the manual equivalent.

## Quick start

Follow the steps below to have a running SSH bastion:

- Create a [docker-compose.yml](https://github.com/dennisdeh/ib-docker/blob/master/bastion/docker-compose.yml) file. See [example](#run-the-container) below
- Create an [.env](https://github.com/dennisdeh/ib-docker/blob/master/bastion/.env-dist) file. See available [options](#environment-variables).
- Copy `authorized_keys` file in `data` folder. We will create two users and asume they already have authorized keys in `/home/user_name/.ssh/autorized_keys`

```bash
# create home folder
export USERS=bastion
mkdir $PWD/data/home/{$USERS}/.ssh
# example to copy authorized_keys file
cp /home/{$USERS}/.ssh/authorized_keys $PWD/data/home/{$USERS}/.ssh
```

- Provision the `data` folder. This is required to create the folder structure required by SSH bastion. See more details on [provisioning](#provision)

- We are ready to go. The image is published and public, so there is nothing
  to build and nothing to log in to:

```bash
docker pull ghcr.io/dennisdeh/bastion:latest
docker compose up -d
```

  To build it yourself instead — a change to this directory, or no access to
  the registry — see [Build the image](#build-the-image).

- Test your setup. See more [examples](#ssh-bastion-use-cases) below

```bash
ssh -J devops@bastion:22222 devops@remote_host
```

This is telling ssh to create an ssh connetion to the server specified with parameter `-J`, in this case `devops@bastion:22222` and once it's connected create another connection from `bastion` to `remote_host`. From the client's point of view, it looks like a direct connection to `remote_host`

### All the steps together

We will clone the git repository to use it as a template and set our preferences.

```bash
git clone https://github.com/dennisdeh/ib-docker.git
cd ib-docker/bastion
cp .env-dist .env
chmod 600 .env # cp leaves it at your umask; this file holds credentials
nano .env # edit env variables
nano docker-compose.yml # edit docker compose file
docker compose config # verify compose file
# set authorized keys, asuming bastion user
mkdir -p $PWD/data/home/bastion/.ssh
cp authorized_keys $PWD/data/home/bastion/.ssh
# run provision
docker run -it --rm -v $PWD/data:/data --env-file .env \
  ghcr.io/dennisdeh/bastion:latest /provision.sh
# start up your SSH bastion
docker compose up -d && docker compose logs -ft
```

Below you will find the available [environment variables](#environment-variables), how to [build](#build-the-image) the image, more details on the [provisioning](#provision) process, running a [bastion container](#run-the-container), managing [user access](#user-access), how to setup your [ssh clinets](#client-setup), the many [use cases](#ssh-bastion-use-cases) for an SSH bastion, [multi-factor](#setting-mfatotp-optional) authentication or MFA/TOTP and certificate authorities [CA](#use-a-certificate-authority). Enjoy the reading.

### Set up with the ib-gateway

> **`deploy/provision.sh init` in the repository root does everything in this
> section**, and does it with restricted `authorized_keys` entries — see
> [Restricting a tunnel key](#restricting-a-tunnel-key) — plus the gateway's
> `known_hosts` filled in from the host key it just generated. Follow the steps
> below when you want to understand what it does, or to do it by hand. See the
> *Deploying* section of the top-level `README.md`.

1. First generate an ssh key pair for the ibgateway user (from the ib-gateway container, same vnet):

```bash
base="$PWD/id_ed25519"; file="$base"; i=1; while [ -e "$file" ] || [ -e "$file.pub" ]; do file="${base}_$i"; i=$((i+1)); done; ssh-keygen -t ed25519 -a 100 -N "" -f "$file"
```

1. Run the provisioning

```bash
sudo rm -rf data/etc data/home          # remove the bogus auto-created dirs
mkdir -p data/home/ibgateway/.ssh
cp <ibgateway_pubkey>.pub data/home/ibgateway/.ssh/authorized_keys
docker run -it --rm -e USERS=ibgateway --env-file .env \
  -v "$PWD/data:/data" ghcr.io/dennisdeh/bastion:latest /provision.sh
```

1. Generate the ssh key pair for the other user (the remote client) and copy it from the repository root to the data folder:

```bash
base="$PWD/id_ed25519"; file="$base"; i=1; while [ -e "$file" ] || [ -e "$file.pub" ]; do file="${base}_$i"; i=$((i+1)); done; ssh-keygen -t ed25519 -a 100 -N "" -f "$file"
```

```bash
mkdir -p data/home/deh/.ssh
sudo install -d -m 700 data/home/deh/.ssh  # if there are problems
cp id_ed25519.pub data/home/deh/.ssh/authorized_keys
```

1. Run the provisioning for both users

```bash
docker run -it --rm -e USERS=deh,ibgateway --env-file .env \
  -v "$PWD/data:/data" ghcr.io/dennisdeh/bastion:latest /provision.sh
```

1. Verify that both users are created for the bastion

```bash
grep -E 'deh|ibgateway' data/etc/group
```

1. Move the private key to ~/.ssh. Then try to ssh into the bastion

```bash
ssh -i ~/.ssh/id_ed25519_remote -p 22222 -N \
    -L 4002:localhost:4002 \
    deh@<DOCKER_HOST_IP>  # localhost if the bastion container is running on the local machine.
```

Install a different key

```bash
cd <your checkout>/bastion
sudo cp ~/.ssh/id_ed25519.pub data/home/deh/.ssh/authorized_keys
sudo chown 1001:1001 data/home/deh/.ssh/authorized_keys
sudo chmod 640      data/home/deh/.ssh/authorized_keys

# then test to compare
docker exec inv_bastion ssh-keygen -lf /home/deh/.ssh/authorized_keys
```

## Environment variables

The following variables are available in the .env file

| Variable | default | Description |
| --- | --- | --- |
| APT_PROXY | blank | Defines an optional APT_PROXY to speed up image build. format -> `http://aptproxy:3142`. You can try [apt-cacher-ng](https://github.com/gnzsnz/apt-cacher-ng) |
| SSH_LISTEN_PORT | 22222 | host external published port |
| USERS | bastion | Coma separated list of users, ex USERS=bastion,devops. Provisioning script will create users defined in this variable |
| USER_SHELL | /usr/sbin/nologin | mandatory, required to set user shell |
| BANNER_ENABLED | no | Enable SSH banner, by default display bastion_banner.tx. To change the banner you need to add a mount point `-v path/to/new_banner.txt:/bastion_banner.txt |
| TOTP_ENABLED | no | Enable TOTP, works with google authenticator or MS authenticator |
| TOTP_ISSUER | Bastion | Description for TOTP applciation |
| TOTP_QR_ENCODE | UTF8 | encoding for the TOTP URI QR, uses qrencoder |
| CA_ENABLED | 'no' | set to 'yes' to enable SSH CA mode |
| SSHD_HOST_CERT | '/etc/ssh/ssh_host_ed25519_key-cert.pub' | CA signed host certificate. You will need to copy it into ./data/etc/ssh directory |
| SSHD_USER_CA | '/etc/ssh/user_ca.pub' | public CA key. You will need to copy it into ./data/etc/ssh directory |
| CONTAINER_NAME_BASTION | bastion | Name given to the container. |
| DNS | blank | Optional DNS server for the container, so clients can use names rather than IP addresses. Commented out in `docker-compose.yml` by default. |
| IMAGE_VERSION | 2604.03 | The image's own version, independent of any IB Gateway release. `ARG IMAGE_VERSION` in the `Dockerfile` is the declaration; `.github/workflows/publish-bastion.yml` reads it to tag the published image and `deploy/provision.sh` reads it to pick which tag to pull, so **that one line is the place to bump it**. A push to `master` under `bastion/` publishes, and an unbumped version overwrites the tag it already has — which is right for a rebuild that only changes how the image is built, and wrong for one that changes how it behaves. Bump it for the second. |
| BASE_VERSION | resolute | Ubuntu base image. Used during build. |

After you have set your .env file check that the configuration is correct.

```bash
docker compose config
```

Make sure you set `USERS` variable with the users that will be using the SSH Bastion.

In addition to environment variables, you can modify the behavior of SSH bastion by passing command line arguments or setting the configuration file. See section [Run the container](#run-the-container) for more details.

## Build the image

The image is published to the [github container registry](https://github.com/dennisdeh/ib-docker/pkgs/container/bastion)
as `ghcr.io/dennisdeh/bastion`, for `linux/amd64` and `linux/arm64`, tagged
`latest` and with its own `IMAGE_VERSION`. It is not on Docker Hub. The package
is public, so pulling it needs no credentials.

You only need to build it to change it — or when a freshly bumped
`IMAGE_VERSION` has no published tag yet:

```bash
docker compose build
```

Both this file and the repository's root `docker-compose.yml` carry
`pull_policy: build` on this service, so a `docker compose up` here builds from
this directory rather than pulling the published tag over what it just built.

If defined, `APT_PROXY` is used during build time to speed the build up.

**Bumping the image:** edit `ARG IMAGE_VERSION` in the `Dockerfile`. That
declaration is what `publish-bastion.yml` tags the published image with and
what `deploy/provision.sh` pulls, so it is the single place to change. A push
to `master` touching `bastion/` publishes the image, so a change that leaves
the version alone overwrites the tag rather than adding one — fine for a
rebuild, not for a change in behaviour. It was once
used by a `LABEL` without being declared at all, which made every image report
its version as `-resolute`.

## Provision

Before you can use a container you need to provision the `./data` host directory with the necessary data. This can be acomplished by running the provision script. The `/data` directory contains all the config needed by SSH, host and user keys plus user access. Provision script will perform the following tasks:

- create users, based on `USERS` env variable
- assign a shell to users, by definition users don't log into a SSH bastion, so leave `/usr/sbin/nologin` default unless you know what you are doing.
- sets data directory with:
  - /data/etc/passwd + shadow + group , based on users created
  - /data/etc/ssh/* , store ssh config and host keys
  - /data/home/*/.ssh/authorized_keys --> sets authorized_keys permissions
- Create a provisioned hash signature, in `/data/etc/ssh/bastion_provisioned_hash`,
  covering
  - `/etc/passwd`, `/etc/group` and `/etc/shadow`
  - `sshd_config` and the ssh host keys
  - the host and user CA files, when `CA_ENABLED=yes`
  - **everything in `/etc/ssh/sshd_config.d/`, plus a listing of that
    directory.** The listing is hashed as well as the files because a per-file
    hash cannot notice a drop-in being *added* or *removed* — every recorded
    line still checks out — and `sshd_config` opens with
    `Include /etc/ssh/sshd_config.d/*.conf`, so an unhashed drop-in could
    change any setting. Added 2026-08-27.
  - `bastion_provisioned_hash.sum` is written beside it, a digest of that list.
    The list is what `entrypoint.sh` verifies with `sha256sum -c` on every
    start; the `.sum` file lets the list itself be checked.
- If `./data` bind mount is already provisioned it will use existing files

> **Nothing under `/home` is hashed — `authorized_keys` included.** The
> checksum is over `/etc`, and it has to be: with TOTP enabled the
> `.google_authenticator` file in each home directory is rewritten at every
> login to record used tokens, so a hash over `/home` would fail on the second
> connection. `/home` is instead mounted read-only, which stops a change from
> *inside* the container but not one made on the host. Editing a key on the
> host and restarting therefore takes effect silently. Re-run the provisioning
> script after any change to `authorized_keys`, both to fix permissions and to
> keep the two in step.
>
> **Data provisioned before 2026-08-27 has no recorded `sshd_config.d` listing,
> and the container stops rather than skipping the check.** Re-run the provision
> script against the existing `data/`: it is idempotent and keeps the host keys,
> so no client's `known_hosts` changes.

The container will mount all those files in read-only mode (unless you are using TOTP which requires write permissions in `/home`)

To set authorized keys,

```bash
# create home folder
export USERS=devops,bastion
mkdir $PWD/data/home/{$USERS}/.ssh
# example to copy authorized_keys file
cp /home/{$USERS}/.ssh/authorized_keys $PWD/data/home/{$USERS}/.ssh
```

This will copy pub keys for user `devops` and `bastion`.

Run provision script

```bash
docker run -it --rm --env-file .env \
  -v $PWD/data:/data \
  dennisdeh/bastion /provision.sh
```

Once the provision script is run, data directory will have all the data required to run the container. Take into account that data directory owner and permissions will reflect data/etc/passwd UIDs and GIDs, you will need `sudo` to make changes.

The provision script will create a hash signature, so if you modify data/etc content you might need to re-run the provision script.

## Run the container

Edit the docker-compose.yml file, the default values should work just fine. You can define a DNS or 'extra_hosts', this will allow SSH clients to use server names rather than IP addresses.

This is [docker-compose.yml](https://github.com/dennisdeh/ib-docker/blob/master/bastion/docker-compose.yml)
in this directory. The root `docker-compose.yml` one level up carries the same
service alongside the gateway and TWS.

```yaml
services:
  bastion:
    build:
      context: .
      platforms:
        - "linux/amd64"
        - "linux/arm64"
      args:
        APT_PROXY: ${APT_PROXY}
        BASE_VERSION: ${BASE_VERSION}
        IMAGE_VERSION: ${IMAGE_VERSION}
    restart: unless-stopped
    pull_policy: build
    image: ghcr.io/dennisdeh/bastion:latest
    container_name: ${CONTAINER_NAME_BASTION:-bastion}
    ports:
      - ${SSH_LISTEN_PORT}:22
    # optional
    # dns: ${DNS}
    #extra_hosts:
    #  - host 10.10.0.5
    # command: ["-o ForwardX11=yes "]
    environment:
      - USERS=${USERS}
      - USER_SHELL=${USER_SHELL}
      - TOTP_ENABLED=${TOTP_ENABLED}
      - TOTP_ISSUER=${TOTP_ISSUER}
      - TOTP_QR_ENCODE=${TOTP_QR_ENCODE}
      - CA_ENABLED=${CA_ENABLED}
      - SSHD_HOST_CERT=${SSHD_HOST_CERT}
      - SSHD_USER_CA=${SSHD_USER_CA}
      - BANNER_ENABLED=${BANNER_ENABLED}
    volumes:
      - ./data/etc/passwd:/etc/passwd:ro
      - ./data/etc/shadow:/etc/shadow:ro
      - ./data/etc/group:/etc/group:ro
      - ./data/etc/ssh:/etc/ssh:ro
      - ./data/home:/home:ro
```

Verify that everything has been set correctly (did you set .env file?)

```bash
docker compose config
```

When the container starts, it will

- Check for provisioned checksum
- Mount /etc/passwd + /etc/shadow + authorized_keys as READ-ONLY. This is to avoid modifications from within the container.

To run the container

```bash
docker compose up -d && docker compose logs -f
```

If you modify the data directory manually, you might need to run again the provision script. This will generate updated checksums that will pass validation during start-up.

You can change the behavior of bastion by setting parameters on the command line or `command` element in `docker-compose.yml` any valid [sshd](https://manpages.ubuntu.com/manpages/jammy/en/man8/sshd.8.html) option will work. The sample docker file above includes a line to allow X forwarding --> `command: ["-o ForwardX11=yes "]`.

Another option is to include additional configuration in `/data/etc/ssh/sshd_config.d/` as bastion will read those files.

## User Access

Bastion follows OpenSSH [authentication](https://manpages.ubuntu.com/manpages/jammy/en/man8/sshd.8.html#authentication). Typically you need to setup user `authorized_keys` file with the public key for each user. A simpler approach for managing `authorized_keys` file point of view is to set up a certificate authority (CA). This requires extra steps to generate and manage the certificates but does not require a line in `authorized_keys` file, nor a `known_host` record for each host. See the section on [certificate authorities](#use-a-certificate-authority).

To add more users, the easiest option is to edit your .env file, set USERS and run provision mode again. It will add to the existing /etc/passwd file and set the authorized keys.

```bash
docker run -it --rm -e USERS=new_user,another_user \
  -v $PWD/data:/data \
  ghcr.io/dennisdeh/bastion:latest /provision.sh
```

Disable existing users

```bash
docker run -it --rm -v $PWD/data:/data \
  ghcr.io/dennisdeh/bastion:latest adduser --disable-login user_name
```

You can add authorized_keys as explained in [provision](#provision) section.

### Restricting a tunnel key

A key that only carries a tunnel needs no shell and no port other than its own,
and `authorized_keys` can say so. Two options do that, and the trap is that
**neither constrains the other**:

- `permitopen` limits what `-L` (and `DynamicForward`) may connect *out* to.
- `permitlisten` limits what `-R` may bind *on the bastion*.

A line naming only one of them leaves the other direction unrestricted — a
client allowed to `-L` to the API port could also bind listeners on the
bastion, and a gateway allowed to `-R` could also reach anything the bastion can
see. `restrict` turns everything off, and the `port-forwarding` that follows it
re-enables **both** directions, which is what makes the omission easy to miss.

So set both on every key, pinning the direction that key does not use to
something it cannot get, such as `127.0.0.1:1`:

```text
# the gateway: may publish the API port on the bastion, may forward nowhere
restrict,port-forwarding,permitlisten="127.0.0.1:4002",permitlisten="localhost:4002",permitopen="127.0.0.1:1" ssh-ed25519 AAAA... ibgateway

# a client: may reach the API port, may publish nothing
restrict,port-forwarding,permitopen="127.0.0.1:4002",permitopen="localhost:4002",permitlisten="127.0.0.1:1" ssh-ed25519 AAAA... jupyter
```

Both spellings of the address are listed because the client chooses which one
it asks for, and OpenSSH matches the request as written rather than resolving
it first.

`deploy/provision.sh` in the repository root writes exactly these lines. This
was measured against a running bastion on 2026-08-27, after shipping it wrong
in both directions, and is pinned by `tests/unit/provision.bats`.

## SSH bastion use cases

If you have followed this README, by now you should have an SSH bastion container up and running. You can now access your ssh servers through bastion

Let's start with a simple case, you open a connection using `-J` option, or you setup you ssh [config](#client-setup) stating that you connect to `server` through a `ProxyJump`.

```bash
ssh -J devops@bastion_host:22222 devops@server
#  if you setup ~/.ssh/config ProxyJump
ssh devops@server
```

We can also do scp, rsync, sftp, port forwarding or a socks proxy

```bash
# scp
scp -J devops@bastion_host:22222 file.gz devops@server:/tmp
# no need to use -J if you use ProxyJump in config file
scp file.gz devops@server:/tmp

# same for rsync
rsync -rtva devops@server:/tmp/file.gz /tmp

# sftp
sftp -J devops@bastion_host:22222 file.gz devops@server:/tmp
sftp file.gz devops@server:/tmp
sftp devops@server

# port forwarding, take into account that forwarding is happening on server
# bastion is just a jump host
ssh -N -L 8888:localhost:80 -J devops@bastion_host:22222 pgsql.example.com
# and without -J
ssh -N -L 8888:localhost:80 devops@pgsql.example.com
# remote forward, ex forward local:80 to remote's localhost:8888
ssh -N -R 80:localhost:8888 devops@app.example.com

# if you setup local or remote forward in your config, then you just do
ssh rf_app
ssh lf_app

# socks proxy
ssh -J devops@bastion_host:22222 -D 1337 -f -N devops@server.example.com
ssh myproxy
```

See next section with examples for [client setup](#client-setup).

A special case that might deserver additional attention is as a *sidecar container* for port forwarding

```text
             >|<   _____________
__________    |    | Bastion   |
| Client | ---|--- | Container | ----\
----------    |    -------------     |
              |     _____________    |
              |     | App       | ---/
              |     | Container |
              |     -------------
              |
             >|<

App to Bastion: ssh -R 8888:localhost:8888 bastion
Client to Bastion: ssh -L 8888:localhost:8888 bastion
```

In the scenario above, our App needs to expose port 8888 however, it's not secure to do so (VNC). In the App container, we can install an ssh client that will create a remote forward on the ssh bastion. While the client will create a local forward. Notice that in this case we are actually connecting to the bastion, we are not using it as a ProxyJump. This is allowed because we are not opening a shell session.

In this scenario, we don't need to install an sshd server in the app container just an ssh client. The only port that needs to be exposed to the internet is the bastion port. With proper ssh client configuration it's both forward connections are easy to setup. The App container can focus on doing what it does best, and the bastion container can create secure connections.

## Client setup

You can setup your `~/.ssh/config` file to simplify your client commands

```text
### The Bastion Host
Host bastion-host-nickname
  HostName bastion-hostname
  AddKeysToAgent yes
  ForwardAgent yes

### The Remote Host
Host remote-host-nickname
  HostName remote-hostname
  ProxyJump bastion-host-nickname
  AddKeysToAgent yes
  ForwardAgent yes

# remote forward example
Host rf_app
  Hostname app.example.com
  ProxyJump bastion-host-nickname
  # local_host:local_port:remote_host:remote_port
  # local is from ssh client point of view, remote is any host accessible for ssh server
  RemoteForward localhost:5432 localhost:5432
  SessionType none
  ForkAfterAuthentication yes
  ExitOnForwardFailure yes
  IdentitiesOnly yes
  CertificateFile ~/.ssh/id_ed25519-cert.pub
  IdentityFile ~/.ssh/id_ed25519

# local forward example
Host lf_pgsql
  Hostname pgsql.example.com
  ProxyJump jump_host_nickname
  # local_host:local_port:remote_host:remote_port
  # local is from ssh client point of view, remote is any host accessible for ssh server
  LocalForward localhost:5432 localhost:5432
  SessionType none
  ForkAfterAuthentication yes
  ExitOnForwardFailure yes
  IdentitiesOnly yes
  CertificateFile ~/.ssh/id_ed25519-cert.pub
  IdentityFile ~/.ssh/id_ed25519

# socks dynamic proxy example
Host myproxy
  Hostname server.example.com
  Port 2222
  ProxyJump bastion-host-nickname
  DynamicForward 1337
  SessionType none
  ForkAfterAuthentication yes
  ExitOnForwardFailure yes
  IdentitiesOnly yes
  CertificateFile ~/.ssh/id_ed25519-cert.pub
  IdentityFile ~/.ssh/id_ed25519

Host *.local 10.0.0.*
  ProxyJump bastion-host-nickname
#  ForwardAgent yes
#  UseKeychain yes
  IdentitiesOnly yes
  CertificateFile ~/.ssh/id_ed25519-cert.pub
  IdentityFile ~/.ssh/id_ed25519
```

To access `remote-hostname`, the bastion container should be able to translate the hostname to an IP address. Make sure your docker-compose.yml contains `extra_hosts` or a DNS entry.

## Setting MFA/TOTP (Optional)

TOTP adds a six-digit code **on top of** the key, not instead of it. When it is
on, the container starts sshd with

```text
-o KbdInteractiveAuthentication=yes
-o AuthenticationMethods=publickey,keyboard-interactive
-o UsePAM=yes
```

and the comma in `publickey,keyboard-interactive` means *both*, in that order —
a valid key alone no longer gets in. `sshd_config` in this directory says
`AuthenticationMethods publickey`; the `-o` on the command line is read before
the file and sshd keeps the first value it obtains for a keyword, so the
runtime setting wins. That is why the file can look as though it contradicts
this. The PAM side is baked into the image: the `Dockerfile` strips
`include common-auth` from `/etc/pam.d/sshd` and appends
`pam_google_authenticator.so`.

To turn it on, set `TOTP_ENABLED=yes` in `.env` and **re-run the provisioning
script**. For each user it does not already have a secret for, it writes three
files into that user's home directory:

| file | mode | what it is |
| --- | --- | --- |
| `.google_authenticator` | 400 | the secret, and the record of used codes |
| `totp_uri` | 400 | the `otpauth://` URI, to paste into an authenticator app |
| `totp_qr` | 400 | the same URI as a QR code, rendered with `qrencode` |

Enrol by scanning `totp_qr` or pasting `totp_uri` into Google Authenticator,
Aegis, 1Password or similar. The secret is generated time-based, with token
reuse disallowed, a window of three codes either side, and a rate limit of
three logins per thirty seconds.

Three things about this are easy to get wrong:

- **`data/home` must NOT be mounted read-only.** Disallowing token reuse means
  `.google_authenticator` is *written* on every successful login, to record the
  code just spent. With `:ro` the first login works and the rest fail. Drop the
  flag from that one mount, and only that one:

  ```yaml
      volumes:
        - ./data/etc/passwd:/etc/passwd:ro
        - ./data/etc/shadow:/etc/shadow:ro
        - ./data/etc/group:/etc/group:ro
        - ./data/etc/ssh:/etc/ssh:ro
        - ./data/home:/home # remove :ro
  ```

  This does not weaken the provisioning checksum, which covers `/etc` only —
  see the note under [Provision](#provision).

- **Re-provisioning does not rotate an existing secret**, and neither
  `TOTP_ISSUER` nor `TOTP_QR_ENCODE` is read again once one exists: both are
  used only at the moment the secret is created. To re-enrol a user, or to
  change how their entry is labelled, delete their `.google_authenticator` and
  provision again — which invalidates whatever they already have in their app.

- **The container refuses to start if any user is not enrolled.** At startup
  `check_totp_users()` walks the members of the `ssh-bastion` group and stops
  the container if one has no `.google_authenticator`, or if the file is not
  owned by that user; a mode other than 400 is a warning. This is deliberate:
  the alternative is a bastion that quietly accepts a key alone for the one
  account nobody enrolled.

A machine account that runs an unattended tunnel — the gateway's own key — has
nowhere to type a code, so TOTP suits human operators rather than the
`ib-gateway` user. `deploy/provision.sh` leaves it off for that reason.

## Use a certificate authority

A certificate authority (CA) signs public keys — for hosts and for users — so
that each side verifies a signature instead of consulting a list. It replaces
two lists, independently:

- a **host certificate** means clients no longer need a `known_hosts` entry for
  this bastion; they trust anything the host CA signed;
- a **user CA** means the bastion no longer needs an `authorized_keys` line per
  user; it accepts any key the user CA signed.

Set `CA_ENABLED=yes` and copy the files into `data/etc/ssh` **before** running
the provisioning script. The container then starts sshd with
`-o HostCertificate=...` and `-o TrustedUserCAKeys=...`. The algorithm lists in
`sshd_config` already include `ssh-ed25519-cert-v01@openssh.com` and the
`rsa-sha2-*-cert-v01` variants, so nothing else needs changing.

`SSHD_HOST_CERT` and `SSHD_USER_CA` name the files. Left empty — as `.env-dist`
leaves them — they default to `/etc/ssh/ssh_host_ed25519_key-cert.pub` and
`/etc/ssh/user_ca.pub`, which is why copying them in under those names is
enough.

Signing, for reference, with the CA key on the machine that holds it:

```bash
# the bastion's host key, signed as a host certificate
ssh-keygen -s host_ca -I bastion -h -n bastion.example.com \
    -V +52w ssh_host_ed25519_key.pub

# a user's key, signed as a user certificate
ssh-keygen -s user_ca -I jane -n jane -V +12w id_ed25519.pub
```

Three things to know before turning this on:

- **A user certificate does not carry the `permitopen` / `permitlisten`
  restrictions this project relies on.** Those live in `authorized_keys`, and a
  certificate is precisely what lets a user in *without* an `authorized_keys`
  line — so the whole restriction disappears with it. Put the equivalent in the
  certificate at signing time instead, and check what you signed with
  `ssh-keygen -L -f id_ed25519-cert.pub`:

  ```bash
  ssh-keygen -s user_ca -I jane -n jane -V +12w \
      -O clear -O permit-port-forwarding \
      -O 'permitopen=127.0.0.1:4002' \
      -O 'permitlisten=127.0.0.1:1' \
      id_ed25519.pub
  ```

  See [Restricting a tunnel key](#restricting-a-tunnel-key) for why both
  directions have to be named.

- **Turning it on proves nothing.** `set_CA()` checks whether the file named by
  `SSHD_HOST_CERT` exists and, if it does not, substitutes the default path —
  with no message, so a typo in the variable looks like it worked. And if the
  default is missing too, **sshd still starts**: it warns `Could not load host
  certificate` and carries on, and says nothing at all about a missing
  `TrustedUserCAKeys`. Measured 2026-08-28 against
  `ghcr.io/dennisdeh/bastion:latest`: with both default paths absent,
  `sshd -t` exits 0 and the container logs `Server listening on 0.0.0.0 port
  22`. So `> SSH CA 🔏 enabled` in the log means the variable was read, not that
  anything is signed or trusted — a bastion in that state accepts exactly what
  it did before, from `authorized_keys`. Check it from outside instead: `ssh -v`
  should report the host key accepted through a certificate, and a client
  holding only a CA-signed key should get in. See `docs/OPEN_ITEMS.md` #26.

- **The CA files are part of the provisioning checksum.** `set_checksum()`
  hashes the host certificate and the user CA when they are present, so
  replacing or removing one afterwards makes the container refuse to start
  until you provision again. Renewing a certificate is a re-provision, not a
  file copy. Note the asymmetry: a CA file *added* after provisioning is not in
  the recorded list, so it is not caught — copy the files in first.

## Additional security

You will probably want to pair SSH bastion with fail2ban or a fail2ban container.

## References

- OpenSSH
  - [sshd](https://manpages.ubuntu.com/manpages/jammy/en/man8/sshd.8.html)
  - [sshd_config](https://manpages.ubuntu.com/manpages/jammy/en/man5/sshd_config.5.html)
  - [ssh](https://manpages.ubuntu.com/manpages/jammy/en/man1/ssh.1.html)
  - [ssh_config](https://manpages.ubuntu.com/manpages/jammy/en/man5/ssh_config.5.html)
  - [ssh-keygen](https://manpages.ubuntu.com/manpages/jammy/en/man1/ssh-keygen.1.html)

- Other bastion containers
  - <https://github.com/panubo/docker-sshd/>
  - <https://github.com/binlab/docker-bastion/>
  - <https://github.com/fphammerle/docker-ssh-bastion/>

- SSH hardening
  - <https://infosec.mozilla.org/guidelines/openssh>
  - <https://www.ssh-audit.com/hardening_guides.html#ubuntu_20_04_lts>
  - <https://goteleport.com/blog/ssh-bastion-host/>
  - <https://goteleport.com/blog/security-hardening-ssh-bastion-best-practices/>
  - <https://news.ycombinator.com/item?id=29924053>
