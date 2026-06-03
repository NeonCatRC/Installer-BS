# Core: single source of truth for platform detection, global flag parsing and
# the subcommand dispatcher. No logic is duplicated across modules — they call here.
# TODO(WP1): implement the bodies below.

# core::detect_platform
# Normalizes `uname -s`/`uname -m` into BS_OS (linux) and BS_ARCH (x86_64, ...).
# This is the ONLY place architecture/OS is detected.
core::detect_platform() {
	# TODO(WP1): set BS_OS / BS_ARCH from uname, reject unsupported with a clear error.
	:
}

# core::dispatch "$@"
# Parses global flags (--help/--version/--yes/--lang/--debug) and routes to a
# subcommand (build, info, ...).
core::dispatch() {
	# TODO(WP1): argument parsing + routing.
	:
}
