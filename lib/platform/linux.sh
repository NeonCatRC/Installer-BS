# Platform abstraction for Linux. ALL OS-specific behavior (sed -i form, stat
# format, base install paths) lives behind this thin interface so the rest of
# the code stays platform-agnostic. A future lib/platform/freebsd.sh can be
# added without scattering `if FreeBSD` branches through every function.
# TODO(WP1/WP2): implement the helpers as they are needed.

# platform::sed_inplace EXPR FILE
platform::sed_inplace() {
	# Linux GNU sed form. TODO(WP2): implement (sed -i "$1" "$2").
	:
}

# platform::file_mode FILE  -> prints octal permission bits
platform::file_mode() {
	# TODO(WP2): stat -c '%a' "$1"
	:
}
