#!/usr/bin/env bash
###############################################################################
# entrypoint.sh
#
# sshd bastion
#
# entrypoint script for sshd bastion docker image. it starts sshd by default,
# takes '-o' sshd option parameters. or run a command in container, ex:
# docker run -it ghcr.io/dennisdeh/bastion:latest bash
#
###############################################################################

set -e

# The path is the one inside the image, which shellcheck cannot resolve from
# the repository; the source= directive below records where it actually lives.
# shellcheck source=bastion/sshd_config_d.sh
# shellcheck disable=SC1091
. /sshd_config_d.sh

DAEMON=sshd
PROVISON=/etc/ssh/bastion_provisioned_hash
declare -a SSHD_OPT

stop() {
	echo "> Received SIGINT or SIGTERM. Shutting down $DAEMON"
	# Get PID
	local pid
	pid=$(cat /var/run/$DAEMON.pid)
	# Set TERM
	kill -SIGTERM "${pid}"
	# Wait for exit
	wait "${pid}"
	# All done.
	echo "> Done... $?"
}

check_totp_users() {
	if [ "$TOTP_ENABLED" != "yes" ]; then
		return 0
	fi

	echo "> Verifying TOTP enrollment ..."

	local failed=0
	local user

	for user in $(getent group ssh-bastion | awk -F: '{print $4}' | tr ',' ' '); do

		home=$(getent passwd "$user" | cut -d: -f6)
		ga_file="${home}/.google_authenticator"

		if [ ! -f "$ga_file" ]; then
			echo "> ERROR: user '$user' has no .google_authenticator file"
			failed=1
			continue
		fi

		if ! stat -c "%U" "$ga_file" | grep -qx "$user"; then
			echo "> ERROR: '$ga_file' is not owned by '$user'"
			failed=1
		fi

		if [ "$(stat -c "%a" "$ga_file")" != "400" ]; then
			echo "> WARNING: '$ga_file' permissions are not 400"
		fi
	done

	if [ "$failed" -ne 0 ]; then
		echo "> TOTP validation failed. Refusing to start."
		exit 1
	fi

	echo "> All users have valid TOTP enrollment."
}

check_provision() {

	if [ ! -f $PROVISON ]; then
		echo "> Container not provisioned."
		exit 1
	elif sha256sum -c $PROVISON; then
		echo "> 🔑 checksum valid."
	else
		echo "> checksum FAILED. 🔒 exiting ..."
		echo "> You might want to provision your data/ dir
    docker run -it --rm --env-file .env \
      -v $PWD/data:/data \
      dennisdeh/bastion /provision.sh
    "
		exit 1
	fi
}

check_sshd_config_d() {
	#
	# The per-file hashes in $PROVISON prove no drop-in was edited. They say
	# nothing about one being added or removed - every recorded line still
	# checks out - and sshd_config includes whatever is in there. So compare
	# the directory against the listing that was hashed with it.
	#
	if [ ! -f "$SSHD_CONFIG_D_LIST" ]; then
		echo "> ERROR: $SSHD_CONFIG_D_LIST is missing."
		echo "> This data/ was provisioned before the drop-in directory was"
		echo "> covered by the checksum. Re-provision it; see docs/RUNBOOK.md."
		echo "> 🔒 exiting ..."
		exit 1
	fi

	if [ "$(sshd_config_d_list)" != "$(cat "$SSHD_CONFIG_D_LIST")" ]; then
		echo "> ERROR: $SSHD_CONFIG_D does not match what was provisioned."
		echo "> sshd_config includes every file in it, so this can change"
		echo "> AllowTcpForwarding, PermitRootLogin or the ciphers."
		echo "> provisioned:"
		sed 's/^/>   /' "$SSHD_CONFIG_D_LIST"
		echo "> found:"
		sshd_config_d_list | sed 's/^/>   /'
		echo "> 🔒 exiting ..."
		exit 1
	fi

	echo "> 🔑 sshd_config.d matches ($(sshd_config_d_list | wc -l) drop-ins)."
}

bastion_banner() {
	# show banner
	if [ "$BANNER_ENABLED" == "yes" ]; then
		SSHD_OPT+=("-o Banner=/bastion_banner.txt")
		echo "> Banner enabled"
		cat /bastion_banner.txt
	else
		echo "> Banner disabled"
	fi
}

set_totp() {
	#
	# set TOTP sshd paramenters in variable SSHD_OPT
	#
	if [ "$TOTP_ENABLED" == "yes" ]; then
		declare -a SSHD_TOTP
		SSHD_TOTP+=('-o KbdInteractiveAuthentication=yes')
		SSHD_TOTP+=('-o AuthenticationMethods=publickey,keyboard-interactive')
		SSHD_TOTP+=('-o UsePAM=yes')
		SSHD_OPT+=("${SSHD_TOTP[@]}")
		echo "> TOTP ⌛🔑 enabled"
	else
		echo "> TOTP ⌛🔑 disabled"
	fi
}

set_CA() {
	#
	# set CA parameters in SSHD_OPT variable
	#
	if [ "$CA_ENABLED" == "yes" ]; then
		declare -a SSHD_CA
		# set host certificate
		[ ! -f "$SSHD_HOST_CERT" ] && SSHD_HOST_CERT='/etc/ssh/ssh_host_ed25519_key-cert.pub'
		SSHD_CA+=("-o HostCertificate=$SSHD_HOST_CERT")
		# set user CA public key
		[ ! -f "$SSHD_USER_CA" ] && SSHD_USER_CA='/etc/ssh/user_ca.pub'
		SSHD_CA+=("-o TrustedUserCAKeys=$SSHD_USER_CA")

		# add to SSHD options
		SSHD_OPT+=("${SSHD_CA[@]}")
		echo "> SSH CA 🔏 enabled"
	else
		echo "> SSH CA 🔏 disabled"
	fi
}

commmon_start() {
	check_provision
	check_sshd_config_d
	check_totp_users
	set_totp
	set_CA
	bastion_banner
	if command -v lslogins >/dev/null 2>&1; then
		lslogins
	else
		echo "> lslogins not available, skipping login summary"
	fi
}

echo "> SSH Bastion:"
echo "> Running $*"
if [ "$(basename "$1" 2>/dev/null)" == "$DAEMON" ]; then
	commmon_start
	echo "> Starting $* ... ${SSHD_OPT[*]}"
	trap stop SIGINT SIGTERM
	"$@" "${SSHD_OPT[@]}" &
	pid="$!"
	echo "> $DAEMON pid: $pid"
	wait "${pid}"
	exit $?
elif echo "$*" | grep ^-o; then
	# accept parameters from command line or compose
	commmon_start
	echo "> Starting $* ... ${SSHD_OPT[*]}"
	trap stop SIGINT SIGTERM
	/usr/sbin/sshd -D -e "$@" "${SSHD_OPT[@]}" &
	pid="$!"
	echo "> $DAEMON pid: $pid"
	wait "${pid}"
	exit $?
else
	# run command from docker run
	exec "$@"
fi
