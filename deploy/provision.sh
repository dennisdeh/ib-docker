#!/usr/bin/env bash
###############################################################################
# deploy/provision.sh
#
# Provision a host to run the published IB Gateway image behind the SSH
# bastion, and emit a compose file that pulls that image instead of building
# it. Safe to re-run: every step checks before it acts.
#
# Everything lands under --root (default /srv/ib-gateway), never in the
# checkout:
#
#   .env                    non-secret settings; compose reads it from there
#   docker-compose.yml      image-only - no build context, no $PWD
#   secrets/                one file per secret, 0600, mounted at /run/secrets
#   ssh/                    the gateway's own ~/.ssh - key, known_hosts, config
#   clients/<name>/         one bundle per client that dials in
#   bastion/data/           the bastion's provisioned /etc and /home
#   tls/                    self-signed xrdp material, for the TWS image
#
# The IB API has no authentication of its own: whatever reaches the port can
# place orders. So nothing here publishes it. The gateway opens it on the
# bastion's loopback over an ssh remote forward, and each client forwards it
# back out under its own key - restricted, by `permitlisten`/`permitopen` in
# authorized_keys, to that one port and nothing else.
#
# See docs/RUNBOOK.md for the operator's walk-through.
###############################################################################
set -Eeuo pipefail

REPO_ROOT="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/.." && pwd)"

# The live deployment this machine already runs. Compose identifies a project
# by name, not by directory, so emitting a stack under this name would make
# `up -d` adopt the running inv_gateway/inv_bastion. Refused outright.
readonly RESERVED_PROJECT='inv_ibkr'
readonly RESERVED_CONTAINERS='inv_gateway inv_bastion'

# Defaults. Every one of these is a flag; see usage().
ROOT=''
PROJECT='ibkr'
CHANNEL='latest'
VERSION=''
APP='ib-gateway'
TRADING_MODE='paper'
READ_ONLY_API='yes'
TIME_ZONE='Europe/Zurich'
CLIENTS=''
GATEWAY_USER='ibgateway'
BASTION_HOST='bastion'
BASTION_PORT='22222'
BASTION_BIND='127.0.0.1'
BASTION_IMAGE='dennisdeh/bastion:local-resolute'
NETWORK=''
IB_UID='1000'
IB_GID='1000'
TWS_USERID=''
KEY_TYPE='ed25519'
CLIENT_PASSPHRASE='yes'
INTERACTIVE='yes'
ROTATE_KEYS='no'
FORCE='no'
COMMAND='init'
ADD_CLIENT=''

###############################################################################
# Output and small helpers
###############################################################################

log() { printf '.> %s\n' "$*"; }
warn() { printf '!> %s\n' "$*" >&2; }
die() {
	printf '!> %s\n' "$*" >&2
	exit 1
}

# Ask for a value, honouring --non-interactive. Usage: ask VAR "prompt" default
ask() {
	local __var="$1" __prompt="$2" __default="${3-}" __reply=''
	if [ "$INTERACTIVE" != 'yes' ]; then
		printf -v "$__var" '%s' "$__default"
		return 0
	fi
	read -r -p "?> ${__prompt} [${__default}]: " __reply || true
	printf -v "$__var" '%s' "${__reply:-$__default}"
}

# Ask a yes/no question. Returns 0 for yes.
confirm() {
	local prompt="$1" default="${2:-no}" reply=''
	if [ "$INTERACTIVE" != 'yes' ]; then
		[ "$default" = 'yes' ]
		return
	fi
	read -r -p "?> ${prompt} [$([ "$default" = 'yes' ] && echo 'Y/n' || echo 'y/N')]: " reply || true
	reply="${reply:-$default}"
	case "$reply" in
	y | Y | yes | YES | Yes) return 0 ;;
	*) return 1 ;;
	esac
}

# A name that is going to become a unix user, a directory and an ssh config
# stanza. Refuse anything that is not obviously safe in all three.
valid_name() {
	[[ $1 =~ ^[a-z][a-z0-9_-]{0,30}$ ]]
}

# 32 bytes of urandom, base64, stripped of characters that would need quoting
# in an .env file, an ssh config or a URI.
gen_secret() {
	LC_ALL=C tr -dc 'A-Za-z0-9' </dev/urandom | head -c 32
	echo
}

# Write $2 to file $1 with mode $3, creating parents. Never logs the content.
write_private() {
	local path="$1" content="$2" mode="${3:-600}"
	mkdir -p "$(dirname "$path")"
	printf '%s\n' "$content" >"$path"
	chmod "$mode" "$path"
}

# True when a file is missing, or holds nothing but whitespace. `-s` cannot be
# used for this: an "empty" secret written as a bare newline is one byte, so
# `-s` calls it populated - while `file_env` in common.sh reads it with
# `$(<file)`, which strips the newline and yields an empty password. That gap
# let provisioning report success and the gateway then fail its IB login.
blank_file() {
	[ -s "$1" ] || return 0
	[ -z "$(tr -d '[:space:]' <"$1")" ]
}

# Create a secret only if absent, so re-running never rotates one silently.
ensure_secret() {
	local path="$1" label="$2"
	if ! blank_file "$path"; then
		log "secret exists, kept: ${label}"
		chmod 600 "$path"
		return 0
	fi
	write_private "$path" "$(gen_secret)" 600
	log "secret generated: ${label}"
}

###############################################################################
# The two lines that carry the whole authorisation model
###############################################################################

# `permitopen` governs `-L` only and `permitlisten` governs `-R` only: neither
# constrains the other, and `port-forwarding` re-enables BOTH directions after
# `restrict` turned them off. OpenSSH has no "local only" or "remote only"
# token, so a key that names just one of the two keeps the other direction
# completely unrestricted - measured, not assumed:
#
#   restrict,port-forwarding,permitopen=API      -L allowed   -R ALLOWED
#   restrict,permitopen=API                      -L denied    -R denied
#   restrict,port-forwarding,permitopen=API,
#            permitlisten=127.0.0.1:1            -L allowed   -R denied
#
# So each key pins both, and the direction it must not use is pinned to port 1,
# which the unprivileged session user can neither bind nor be forwarded to.
readonly UNUSABLE_PORT='127.0.0.1:1'

# The gateway's key. It only ever runs `ssh -R`, publishing the API port on the
# bastion's loopback. Without the permitopen below it could also `-L` to
# anything the bastion can reach.
gateway_authorized_key() {
	local pubkey="$1" api_port="$2"
	printf 'restrict,port-forwarding,permitlisten="127.0.0.1:%s",permitlisten="localhost:%s",permitopen="%s" %s\n' \
		"$api_port" "$api_port" "$UNUSABLE_PORT" "$pubkey"
}

# A client's key. It only ever runs `ssh -L` to the port the gateway published.
# Without the permitlisten below it could bind ports on the bastion - including
# the API port itself whenever the gateway is not holding it, which would let a
# compromised client serve a counterfeit IB API to the others.
client_authorized_key() {
	local pubkey="$1" api_port="$2"
	printf 'restrict,port-forwarding,permitopen="127.0.0.1:%s",permitopen="localhost:%s",permitlisten="%s" %s\n' \
		"$api_port" "$api_port" "$UNUSABLE_PORT" "$pubkey"
}

# known_hosts entry. A non-default port must be written as [host]:port, and the
# gateway dials the bastion by its compose service name on port 22 while an
# off-host client dials the published port - so both forms get pinned.
known_hosts_entry() {
	local host="$1" port="$2" keyline="$3"
	if [ "$port" = '22' ]; then
		printf '%s %s\n' "$host" "$keyline"
	else
		printf '[%s]:%s %s\n' "$host" "$port" "$keyline"
	fi
}

# IB Gateway's API port for a trading mode. `set_ports()` in common.sh binds
# these; the tunnel opens the same number on the bastion. TRADING_MODE=both
# starts two IBC instances and tunnels the paper port.
api_port_for() {
	case "$1" in
	live) echo 4001 ;;
	paper | both) echo 4002 ;;
	*) return 1 ;;
	esac
}

###############################################################################
# Preflight
###############################################################################

require_docker() {
	command -v docker >/dev/null 2>&1 || die "docker is not on PATH"
	docker info >/dev/null 2>&1 || die "cannot talk to the docker daemon"
}

# This host already runs a stack that other services depend on. Provisioning
# must not adopt it, and compose adopts by project name alone.
refuse_live_deployment() {
	[ "$PROJECT" != "$RESERVED_PROJECT" ] ||
		die "project name '${RESERVED_PROJECT}' belongs to the running deployment; choose another with --project"

	local running='' name
	for name in $RESERVED_CONTAINERS; do
		if docker ps --format '{{.Names}}' | grep -qx "$name"; then
			running+=" $name"
		fi
	done
	if [ -n "$running" ]; then
		warn "this host is already running:${running}"
		warn "they belong to another checkout and other services depend on them."
		if [ "$FORCE" = 'yes' ]; then
			warn "--force given; continuing. Nothing here touches those containers."
		else
			die "refusing to provision alongside them without --force (nothing would be stopped, but read docs/RUNBOOK.md first)"
		fi
	fi
}

###############################################################################
# Steps
###############################################################################

resolve_version() {
	if [ -n "$VERSION" ]; then return 0; fi
	local dockerfile="${REPO_ROOT}/${CHANNEL}/Dockerfile"
	[ -f "$dockerfile" ] || die "no ${CHANNEL}/Dockerfile to read a version from; pass --version"
	VERSION="$(grep 'ENV IB_GATEWAY_VERSION=' "$dockerfile" | head -1 | cut -d '=' -f 2)"
	[ -n "$VERSION" ] || die "could not read IB_GATEWAY_VERSION from ${dockerfile}"
	log "pinning ${CHANNEL} to ${VERSION} (from ${CHANNEL}/Dockerfile)"
}

create_layout() {
	log "layout under ${ROOT}"
	mkdir -p "$ROOT"/{secrets,ssh,clients,tls,config}
	mkdir -p "$ROOT"/bastion/{data,pubkeys}
	chmod 700 "$ROOT/secrets" "$ROOT/ssh" "$ROOT/bastion/pubkeys"
	chmod 755 "$ROOT" "$ROOT/clients"
}

create_secrets() {
	ensure_secret "$ROOT/secrets/ssh_passphrase" 'ssh key passphrase'
	ensure_secret "$ROOT/secrets/vnc_password" 'VNC password'
	if ! blank_file "$ROOT/secrets/tws_password"; then
		log "secret exists, kept: IB account password"
		chmod 600 "$ROOT/secrets/tws_password"
	else
		local pw=''
		if [ "$INTERACTIVE" = 'yes' ]; then
			read -r -s -p "?> IB account password (leave blank to fill in later): " pw || true
			echo
		fi
		write_private "$ROOT/secrets/tws_password" "$pw" 600
		if [ -z "$pw" ]; then
			warn "secrets/tws_password is empty - write the password into it before starting"
		else
			log "secret stored: IB account password"
		fi
	fi
	if [ "$APP" = 'tws' ] || [ "$APP" = 'both' ]; then
		ensure_secret "$ROOT/secrets/rdp_password" 'RDP password'
	fi
}

# One keypair, created if absent. Honours --rotate-keys and, interactively,
# asks - which is the only destructive choice this script offers.
ensure_keypair() {
	local dir="$1" comment="$2" passphrase="$3"
	local key="${dir}/id_${KEY_TYPE}"

	if [ -f "$key" ]; then
		local rotate='no'
		if [ "$ROTATE_KEYS" = 'yes' ]; then
			rotate='yes'
		elif [ "$INTERACTIVE" = 'yes' ]; then
			log "a key already exists: ${key}"
			log "fingerprint: $(ssh-keygen -lf "${key}.pub" 2>/dev/null || echo 'unreadable')"
			confirm "rotate it? every authorized_keys entry for it is rewritten" 'no' && rotate='yes'
		fi
		if [ "$rotate" != 'yes' ]; then
			log "keeping existing key: ${key}"
			chmod 600 "$key"
			[ -f "${key}.pub" ] && chmod 644 "${key}.pub"
			return 0
		fi
		local stamp
		stamp="$(date +%Y%m%d%H%M%S)"
		mv "$key" "${key}.replaced-${stamp}"
		[ -f "${key}.pub" ] && mv "${key}.pub" "${key}.pub.replaced-${stamp}"
		warn "previous key kept as ${key}.replaced-${stamp}"
	fi

	mkdir -p "$dir"
	chmod 700 "$dir"
	ssh-keygen -q -t "$KEY_TYPE" -a 100 -N "$passphrase" -C "$comment" -f "$key"
	chmod 600 "$key"
	chmod 644 "${key}.pub"
	log "key created: ${key} ($(ssh-keygen -lf "${key}.pub" | awk '{print $1, $2}'))"
}

create_gateway_key() {
	ensure_keypair "$ROOT/ssh" "ib-gateway@${PROJECT}" "$(cat "$ROOT/secrets/ssh_passphrase")"
	cp "$ROOT/ssh/id_${KEY_TYPE}.pub" "$ROOT/bastion/pubkeys/${GATEWAY_USER}.pub"
}

create_client_keys() {
	local name passphrase
	for name in $(clients_list); do
		valid_name "$name" || die "invalid client name: '${name}'"
		mkdir -p "$ROOT/clients/$name"
		chmod 700 "$ROOT/clients/$name"
		passphrase=''
		if [ "$CLIENT_PASSPHRASE" = 'yes' ]; then
			ensure_secret "$ROOT/clients/$name/passphrase" "passphrase for client '${name}'"
			passphrase="$(cat "$ROOT/clients/$name/passphrase")"
		fi
		ensure_keypair "$ROOT/clients/$name" "${name}@${PROJECT}" "$passphrase"
		cp "$ROOT/clients/$name/id_${KEY_TYPE}.pub" "$ROOT/bastion/pubkeys/${name}.pub"
	done
}

clients_list() {
	printf '%s' "$CLIENTS" | tr ',' ' '
}

bastion_users() {
	local users="$GATEWAY_USER" name
	for name in $(clients_list); do
		users="${users},${name}"
	done
	printf '%s' "$users"
}

# The bastion image is built here, not pulled: it is not published anywhere.
build_bastion_image() {
	if docker image inspect "$BASTION_IMAGE" >/dev/null 2>&1; then
		log "bastion image present: ${BASTION_IMAGE}"
		return 0
	fi
	[ -d "${REPO_ROOT}/bastion" ] || die "no bastion/ directory to build ${BASTION_IMAGE} from"
	log "building ${BASTION_IMAGE} from ${REPO_ROOT}/bastion"
	docker build -t "$BASTION_IMAGE" "${REPO_ROOT}/bastion"
}

# authorized_keys and the users that own them are written *inside* the
# provisioning container. provision.sh chowns data/ to root, so a second run
# from the host could not write into it, and this keeps every step that
# touches data/ on the same side of the mount.
write_wiring_script() {
	local api_port="$1"
	cat >"$ROOT/bastion/wire.sh" <<-'WIRE'
		#!/usr/bin/env bash
		# Generated by deploy/provision.sh. Runs inside the bastion image with
		# data/ at /data and the public keys at /pubkeys.
		set -Eeuo pipefail

		for pub in /pubkeys/*.pub; do
			user="$(basename "$pub" .pub)"
			install -d -m 750 "/data/home/${user}"
			install -d -m 700 "/data/home/${user}/.ssh"
			# The restriction line is generated with the key, not here, so the
			# authorisation model lives in one place.
			install -m 600 "/authorized_keys/${user}" "/data/home/${user}/.ssh/authorized_keys"
			echo "> authorized_keys installed for ${user}"
		done

		exec /provision.sh
	WIRE
	chmod +x "$ROOT/bastion/wire.sh"

	# One authorized_keys file per user, built on the host where the
	# restriction helpers live.
	local dir="$ROOT/bastion/authorized_keys"
	rm -rf "$dir"
	mkdir -p "$dir"
	chmod 700 "$dir"
	gateway_authorized_key "$(cat "$ROOT/bastion/pubkeys/${GATEWAY_USER}.pub")" "$api_port" \
		>"${dir}/${GATEWAY_USER}"
	local name
	for name in $(clients_list); do
		client_authorized_key "$(cat "$ROOT/bastion/pubkeys/${name}.pub")" "$api_port" \
			>"${dir}/${name}"
	done
	chmod 600 "$dir"/*
}

provision_bastion() {
	local api_port="$1"
	write_wiring_script "$api_port"
	log "provisioning the bastion's data/ (users: $(bastion_users))"
	docker run --rm \
		-e USERS="$(bastion_users)" \
		-e USER_SHELL='/usr/sbin/nologin' \
		-e TOTP_ENABLED='no' \
		-e CA_ENABLED='no' \
		-e BANNER_ENABLED='no' \
		-v "$ROOT/bastion/data:/data" \
		-v "$ROOT/bastion/pubkeys:/pubkeys:ro" \
		-v "$ROOT/bastion/authorized_keys:/authorized_keys:ro" \
		-v "$ROOT/bastion/wire.sh:/wire.sh:ro" \
		--entrypoint /wire.sh \
		"$BASTION_IMAGE"
}

# Q7: the host key is read from what was just provisioned, never scanned off
# the network - there is no first-connection window to get wrong.
pin_known_hosts() {
	local hostkey="$ROOT/bastion/data/etc/ssh/ssh_host_ed25519_key.pub"
	[ -f "$hostkey" ] || die "the bastion did not produce a host key at ${hostkey}"

	local keyline
	keyline="$(cut -d ' ' -f 1,2 <"$hostkey")"

	local kh
	kh="$(
		known_hosts_entry "$BASTION_HOST" '22' "$keyline"
		known_hosts_entry "$BASTION_HOST" "$BASTION_PORT" "$keyline"
		known_hosts_entry '127.0.0.1' "$BASTION_PORT" "$keyline"
	)"

	write_private "$ROOT/ssh/known_hosts" "$kh" 644
	local name
	for name in $(clients_list); do
		write_private "$ROOT/clients/$name/known_hosts" "$kh" 644
	done
	log "bastion host key pinned: $(ssh-keygen -lf "$hostkey" | awk '{print $1, $2}')"
}

write_ssh_configs() {
	# The gateway reaches the bastion over the compose network, by service
	# name, on 22 - the published port is for everyone else.
	write_private "$ROOT/ssh/config" "$(
		cat <<-CFG
			# Generated by deploy/provision.sh
			Host ${BASTION_HOST}
			    HostName ${BASTION_HOST}
			    Port 22
			    User ${GATEWAY_USER}
			    IdentityFile ~/.ssh/id_${KEY_TYPE}
			    IdentitiesOnly yes
			    StrictHostKeyChecking yes
			    UserKnownHostsFile ~/.ssh/known_hosts
			    ExitOnForwardFailure yes
		CFG
	)" 644

	local name
	for name in $(clients_list); do
		write_private "$ROOT/clients/$name/ssh_config" "$(
			cat <<-CFG
				# Generated by deploy/provision.sh - client '${name}'
				# Forward the IB API to this container's own localhost:
				#   ssh -F ssh_config -N ${name}-bastion
				Host ${name}-bastion
				    HostName ${BASTION_HOST}
				    Port ${BASTION_PORT}
				    User ${name}
				    IdentityFile ${ROOT}/clients/${name}/id_${KEY_TYPE}
				    IdentitiesOnly yes
				    StrictHostKeyChecking yes
				    UserKnownHostsFile ${ROOT}/clients/${name}/known_hosts
				    ExitOnForwardFailure yes
				    LocalForward 127.0.0.1:${API_PORT} 127.0.0.1:${API_PORT}
			CFG
		)" 644
	done
}

create_tls() {
	[ "$APP" = 'tws' ] || [ "$APP" = 'both' ] || return 0
	touch "$ROOT/tls/keylock"
	if [ -f "$ROOT/tls/key.pem" ] && [ -f "$ROOT/tls/cert.pem" ]; then
		log "xrdp certificate exists, kept"
		chmod 600 "$ROOT/tls/key.pem"
		chmod 644 "$ROOT/tls/cert.pem"
		return 0
	fi
	command -v openssl >/dev/null 2>&1 || die "openssl is needed to generate the xrdp certificate"
	openssl req -x509 -newkey rsa:4096 -sha256 -days 3650 -nodes \
		-keyout "$ROOT/tls/key.pem" -out "$ROOT/tls/cert.pem" \
		-subj "/CN=${PROJECT}-tws" >/dev/null 2>&1
	chmod 600 "$ROOT/tls/key.pem"
	chmod 644 "$ROOT/tls/cert.pem"
	log "self-signed xrdp certificate generated (10 years)"
}

write_env() {
	local env_file="$ROOT/.env"
	cat >"$env_file" <<-ENV
		# Generated by deploy/provision.sh. Non-secret settings only - every
		# credential is a file under ./secrets, mounted at /run/secrets, and
		# named to the container through a *_FILE variable.
		#
		# Re-running provision.sh rewrites this file. Values you edit by hand
		# are lost; pass them as flags instead.

		COMPOSE_PROJECT_NAME=${PROJECT}
		IB_GATEWAY_IMAGE=ghcr.io/dennisdeh/ib-gateway:${VERSION}
		IB_TWS_IMAGE=ghcr.io/dennisdeh/tws-rdesktop:${VERSION}
		BASTION_IMAGE=${BASTION_IMAGE}

		TWS_USERID=${TWS_USERID}
		TRADING_MODE=${TRADING_MODE}
		READ_ONLY_API=${READ_ONLY_API}
		TIME_ZONE=${TIME_ZONE}

		BASTION_BIND=${BASTION_BIND}
		BASTION_PORT=${BASTION_PORT}
		BASTION_USERS=$(bastion_users)

		# State, read back by \`provision.sh add-client\`. Not read by compose.
		IBKR_CLIENTS=${CLIENTS}
		IBKR_CHANNEL=${CHANNEL}
		IBKR_APP=${APP}
	ENV
	chmod 600 "$env_file"
	log "wrote ${env_file}"
}

write_compose() {
	local compose="$ROOT/docker-compose.yml"
	local net="${NETWORK:-${PROJECT}_ibkr}"

	{
		cat <<-HEAD
			# Generated by deploy/provision.sh - do not edit; re-run the script.
			#
			# Pulls the published images; there is no build context and no \$PWD
			# dependency, so this file works from any directory.
			#
			# The IB API port is deliberately NOT published. The gateway opens it
			# on the bastion's loopback with \`ssh -R\`, and a client forwards it
			# back with \`ssh -L\` under its own restricted key. Reaching the API
			# therefore requires a private key, not merely a route to this host.
			name: ${PROJECT}

			services:
			  bastion:
			    image: \${BASTION_IMAGE}
			    container_name: ${PROJECT}_bastion
			    restart: unless-stopped
			    # Published for clients that are not on the network below. Bound
			    # to ${BASTION_BIND}; widen deliberately, with a firewall rule.
			    ports:
			      - "\${BASTION_BIND}:\${BASTION_PORT}:22"
			    environment:
			      USERS: \${BASTION_USERS}
			      USER_SHELL: /usr/sbin/nologin
			      TOTP_ENABLED: "no"
			      CA_ENABLED: "no"
			      BANNER_ENABLED: "no"
			    volumes:
			      - ./bastion/data/etc/passwd:/etc/passwd:ro
			      - ./bastion/data/etc/shadow:/etc/shadow:ro
			      - ./bastion/data/etc/group:/etc/group:ro
			      - ./bastion/data/etc/ssh:/etc/ssh:ro
			      - ./bastion/data/home:/home:ro
			    networks:
			      - ibkr
			    healthcheck:
			      test: ["CMD-SHELL", "timeout 2 bash -c '</dev/tcp/127.0.0.1/22'"]
			      interval: 30s
			      timeout: 5s
			      retries: 3
		HEAD

		if [ "$APP" = 'ib-gateway' ] || [ "$APP" = 'both' ]; then
			cat <<-GATEWAY

				  ib-gateway:
				    image: \${IB_GATEWAY_IMAGE}
				    container_name: ${PROJECT}_gateway
				    restart: always
				    depends_on:
				      bastion:
				        condition: service_healthy
				    environment:
				      TWS_USERID: \${TWS_USERID}
				      TWS_PASSWORD_FILE: /run/secrets/tws_password
				      TRADING_MODE: \${TRADING_MODE}
				      READ_ONLY_API: \${READ_ONLY_API}
				      TIME_ZONE: \${TIME_ZONE}
				      TZ: \${TIME_ZONE}
				      VNC_SERVER_PASSWORD_FILE: /run/secrets/vnc_password
				      # socat never starts: the API leaves only through the tunnel.
				      SSH_TUNNEL: "yes"
				      SSH_USER_TUNNEL: ${GATEWAY_USER}@${BASTION_HOST}
				      SSH_PASSPHRASE_FILE: /run/secrets/ssh_passphrase
				      SSH_ALIVE_INTERVAL: "20"
				      SSH_ALIVE_COUNT: "3"
				      SSH_RESTART: "5"
				      AUTO_RESTART_TIME: "11:59 PM"
				    secrets:
				      - tws_password
				      - vnc_password
				      - ssh_passphrase
				    volumes:
				      - ./ssh:/home/ibgateway/.ssh:ro
				    networks:
				      - ibkr
			GATEWAY
		fi

		if [ "$APP" = 'tws' ] || [ "$APP" = 'both' ]; then
			cat <<-TWS

				  tws:
				    image: \${IB_TWS_IMAGE}
				    container_name: ${PROJECT}_tws
				    restart: unless-stopped
				    depends_on:
				      bastion:
				        condition: service_healthy
				    devices:
				      - /dev/dri:/dev/dri
				    shm_size: "1gb"
				    security_opt:
				      - seccomp:unconfined
				    environment:
				      PUID: "${IB_UID}"
				      PGID: "${IB_GID}"
				      PASSWD_FILE: /run/secrets/rdp_password
				      TWS_USERID: \${TWS_USERID}
				      TWS_PASSWORD_FILE: /run/secrets/tws_password
				      TRADING_MODE: \${TRADING_MODE}
				      READ_ONLY_API: \${READ_ONLY_API}
				      TIME_ZONE: \${TIME_ZONE}
				      TZ: \${TIME_ZONE}
				      SSH_TUNNEL: "yes"
				      SSH_USER_TUNNEL: ${GATEWAY_USER}@${BASTION_HOST}
				      SSH_PASSPHRASE_FILE: /run/secrets/ssh_passphrase
				    secrets:
				      - tws_password
				      - rdp_password
				      - ssh_passphrase
				    volumes:
				      - ./ssh:/config/.ssh:ro
				      - ./config:/config
				      - ./tls/keylock:/keylock
				      - ./tls/key.pem:/etc/xrdp/key.pem:ro
				      - ./tls/cert.pem:/etc/xrdp/cert.pem:ro
				    networks:
				      - ibkr
			TWS
		fi

		cat <<-TAIL

			secrets:
			  tws_password:
			    file: ./secrets/tws_password
			  vnc_password:
			    file: ./secrets/vnc_password
			  ssh_passphrase:
			    file: ./secrets/ssh_passphrase
		TAIL

		if [ "$APP" = 'tws' ] || [ "$APP" = 'both' ]; then
			cat <<-TAILTWS
				  rdp_password:
				    file: ./secrets/rdp_password
			TAILTWS
		fi

		cat <<-NET

			networks:
			  ibkr:
			    name: ${net}
			    # Sibling stacks join this by declaring it external.
		NET
	} >"$compose"

	chmod 644 "$compose"
	log "wrote ${compose}"
}

###############################################################################
# Commands
###############################################################################

do_init() {
	require_docker
	refuse_live_deployment
	resolve_version

	API_PORT="$(api_port_for "$TRADING_MODE")" ||
		die "invalid --trading-mode: ${TRADING_MODE} (paper, live or both)"

	if [ -z "$TWS_USERID" ] && [ "$INTERACTIVE" = 'yes' ]; then
		ask TWS_USERID 'IB account user name' ''
	fi

	log "project ${PROJECT}, ${APP}, ${TRADING_MODE}, API port ${API_PORT}"
	log "clients: ${CLIENTS:-<none>}"

	create_layout
	create_secrets
	create_gateway_key
	create_client_keys
	build_bastion_image
	provision_bastion "$API_PORT"
	pin_known_hosts
	write_ssh_configs
	create_tls
	write_env
	write_compose
	summary
}

do_add_client() {
	valid_name "$ADD_CLIENT" || die "invalid client name: '${ADD_CLIENT}'"
	[ -f "$ROOT/.env" ] || die "${ROOT} is not provisioned yet; run 'provision.sh init' first"

	# Re-read what the last run decided, so a client can be added without
	# repeating every flag.
	local existing
	existing="$(sed -n 's/^IBKR_CLIENTS=//p' "$ROOT/.env")"
	CHANNEL="$(sed -n 's/^IBKR_CHANNEL=//p' "$ROOT/.env")"
	APP="$(sed -n 's/^IBKR_APP=//p' "$ROOT/.env")"
	TRADING_MODE="$(sed -n 's/^TRADING_MODE=//p' "$ROOT/.env")"
	TWS_USERID="$(sed -n 's/^TWS_USERID=//p' "$ROOT/.env")"
	VERSION="$(sed -n 's|^IB_GATEWAY_IMAGE=.*:||p' "$ROOT/.env")"

	case ",${existing}," in
	*",${ADD_CLIENT},"*) log "client '${ADD_CLIENT}' already present; re-wiring it" ;;
	*) CLIENTS="${existing:+${existing},}${ADD_CLIENT}" ;;
	esac
	[ -n "$CLIENTS" ] || CLIENTS="$existing"

	log "clients after this run: ${CLIENTS}"
	do_init
}

do_status() {
	[ -f "$ROOT/.env" ] || die "${ROOT} is not provisioned"
	echo "root:     ${ROOT}"
	sed -n 's/^COMPOSE_PROJECT_NAME=/project:  /p;s/^IB_GATEWAY_IMAGE=/image:    /p;s/^IBKR_CLIENTS=/clients:  /p' "$ROOT/.env"
	echo
	echo "keys:"
	local key
	for key in "$ROOT/ssh/id_"*.pub "$ROOT"/clients/*/id_*.pub; do
		[ -f "$key" ] || continue
		printf '  %-46s %s\n' "${key#"$ROOT"/}" "$(ssh-keygen -lf "$key" | awk '{print $2}')"
	done
	echo
	echo "bastion host key:"
	local hk="$ROOT/bastion/data/etc/ssh/ssh_host_ed25519_key.pub"
	[ -f "$hk" ] && printf '  %s\n' "$(ssh-keygen -lf "$hk" | awk '{print $1, $2}')" || echo '  not provisioned'
}

summary() {
	local name
	cat <<-SUMMARY

		    Provisioned ${ROOT}

		    Nothing is running yet. Start it with:

		      cd ${ROOT}
		      docker compose up -d

		    The IB API is not published on this host. To reach it, a client
		    forwards it over the bastion with its own key:
	SUMMARY
	for name in $(clients_list); do
		printf '      ssh -F %s/clients/%s/ssh_config -N %s-bastion\n' "$ROOT" "$name" "$name"
	done
	[ -n "$CLIENTS" ] || printf '      (no clients yet - add one with: %s add-client <name>)\n' "$0"
	cat <<-SUMMARY

		    ...then connect to 127.0.0.1:${API_PORT} inside that client.

		    Secrets live in ${ROOT}/secrets (0600) and reach the containers as
		    files under /run/secrets. No credential is written into .env.
	SUMMARY
	if blank_file "$ROOT/secrets/tws_password"; then
		echo
		warn "secrets/tws_password is still empty - the gateway cannot log in until you fill it"
	fi
}

###############################################################################
# Arguments
###############################################################################

usage() {
	cat <<-USAGE
		Usage: deploy/provision.sh [command] [options]

		Commands:
		  init                  provision everything (default)
		  add-client NAME       add one client keypair and bastion user
		  status                show what is provisioned

		Options:
		  --root DIR            where everything lives
		                        (default: /srv/ib-gateway, or
		                        \$XDG_DATA_HOME/ib-gateway when /srv is not writable)
		  --project NAME        compose project name (default: ${PROJECT})
		  --channel CH          latest or stable (default: ${CHANNEL})
		  --version VER         pin this IB version instead of reading the channel
		  --app APP             ib-gateway, tws or both (default: ${APP})
		  --trading-mode MODE   paper, live or both (default: ${TRADING_MODE})
		  --read-only-api YN    yes or no (default: ${READ_ONLY_API})
		  --time-zone TZ        (default: ${TIME_ZONE})
		  --tws-userid NAME     IB account user name
		  --clients a,b,c       clients that will dial in, one keypair each
		  --bastion-host HOST   name the gateway dials (default: ${BASTION_HOST})
		  --bastion-port PORT   published ssh port (default: ${BASTION_PORT})
		  --bastion-bind ADDR   interface to publish it on (default: ${BASTION_BIND})
		  --network NAME        docker network name siblings join
		  --key-type TYPE       ed25519 or rsa (default: ${KEY_TYPE})
		  --no-client-passphrase  leave client keys unencrypted
		  --rotate-keys         replace existing keys instead of asking
		  --non-interactive     never prompt; use defaults and flags
		  --force               provision even though a live stack is running
		  -h, --help            this text
	USAGE
}

parse_args() {
	case "${1-}" in
	init | status)
		COMMAND="$1"
		shift
		;;
	add-client)
		COMMAND='add-client'
		shift
		ADD_CLIENT="${1-}"
		[ -n "$ADD_CLIENT" ] || die "add-client needs a name"
		shift
		;;
	esac

	while [ $# -gt 0 ]; do
		case "$1" in
		--root)
			ROOT="$2"
			shift 2
			;;
		--project)
			PROJECT="$2"
			shift 2
			;;
		--channel)
			CHANNEL="$2"
			shift 2
			;;
		--version)
			VERSION="$2"
			shift 2
			;;
		--app)
			APP="$2"
			shift 2
			;;
		--trading-mode)
			TRADING_MODE="$2"
			shift 2
			;;
		--read-only-api)
			READ_ONLY_API="$2"
			shift 2
			;;
		--time-zone)
			TIME_ZONE="$2"
			shift 2
			;;
		--tws-userid)
			TWS_USERID="$2"
			shift 2
			;;
		--clients)
			CLIENTS="$2"
			shift 2
			;;
		--bastion-host)
			BASTION_HOST="$2"
			shift 2
			;;
		--bastion-port)
			BASTION_PORT="$2"
			shift 2
			;;
		--bastion-bind)
			BASTION_BIND="$2"
			shift 2
			;;
		--network)
			NETWORK="$2"
			shift 2
			;;
		--key-type)
			KEY_TYPE="$2"
			shift 2
			;;
		--no-client-passphrase)
			CLIENT_PASSPHRASE='no'
			shift
			;;
		--rotate-keys)
			ROTATE_KEYS='yes'
			shift
			;;
		--non-interactive)
			INTERACTIVE='no'
			shift
			;;
		--force)
			FORCE='yes'
			shift
			;;
		-h | --help)
			usage
			exit 0
			;;
		*) die "unknown option: $1 (try --help)" ;;
		esac
	done

	# /srv is the conventional place on a server, but needs root. Fall back to
	# the user's own data directory rather than demanding sudo.
	if [ -z "$ROOT" ]; then
		if [ -w /srv ] || [ "$(id -u)" = '0' ]; then
			ROOT='/srv/ib-gateway'
		else
			ROOT="${XDG_DATA_HOME:-$HOME/.local/share}/ib-gateway"
		fi
	fi

	valid_name "$PROJECT" || die "invalid --project: '${PROJECT}'"
	case "$APP" in ib-gateway | tws | both) ;; *) die "invalid --app: ${APP}" ;; esac
	case "$KEY_TYPE" in ed25519 | rsa) ;; *) die "invalid --key-type: ${KEY_TYPE}" ;; esac
	[ ! -t 0 ] && INTERACTIVE='no'
	return 0
}

main() {
	parse_args "$@"
	case "$COMMAND" in
	init) do_init ;;
	add-client) do_add_client ;;
	status) do_status ;;
	esac
}

# Sourced by the test suite, which calls the helpers above directly.
if [ "${BASH_SOURCE[0]}" = "$0" ]; then
	main "$@"
fi
