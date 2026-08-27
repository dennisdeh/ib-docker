# shellcheck shell=bash
#
# Sourced, never executed - hence no shebang.
###############################################################################
# sshd_config_d.sh
#
# `sshd_config` opens with `Include /etc/ssh/sshd_config.d/*.conf`, so anything
# in that directory is part of the running configuration - it can set
# AllowTcpForwarding, PermitRootLogin or the cipher list. provision.sh hashes
# those files so an edit to one is caught, but a per-file hash cannot notice a
# file being *added* or *removed*: the recorded lines still check out. So the
# sorted listing is recorded as a file of its own and hashed with the rest,
# and entrypoint.sh compares it against reality before sshd starts.
#
# Sourced by both provision.sh (which writes the list) and entrypoint.sh (which
# checks it). The two must agree byte for byte, which is why this is one file
# and not the same four lines copied twice.
###############################################################################

# shellcheck disable=SC2034  # both are read by the scripts that source this
SSHD_CONFIG_D=/etc/ssh/sshd_config.d
SSHD_CONFIG_D_LIST=/etc/ssh/sshd_config.d.list

# Names, sorted, of everything in the drop-in directory. `sort` is pinned to the
# C locale so the list does not depend on the container's locale.
sshd_config_d_list() {
	find "$SSHD_CONFIG_D" -mindepth 1 -maxdepth 1 2>/dev/null |
		sed 's|.*/||' | LC_ALL=C sort
}
