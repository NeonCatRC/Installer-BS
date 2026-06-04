# shellcheck shell=bash
# Platform interface — Linux reference implementation.
#
# Groundwork, NOT dead code. This is the single seam where OS-specific behavior
# would live (the `sed -i` form, the `stat` format, base paths), so the rest of
# the codebase never sprouts `if FreeBSD` branches the way the original did.
#
# It is intentionally not sourced yet: the current Linux-only code has nothing
# that diverges by platform. When a second platform is added, copy this file to
# lib/platform/<os>.sh, adjust the bodies, and source the right one from `bs`
# after detection. The bodies below are real (GNU coreutils) so this doubles as
# the reference any port starts from.

# platform::sed_inplace EXPR FILE  — edit FILE in place.
platform::sed_inplace() { sed -i -e "$1" -- "$2"; }

# platform::file_mode FILE  — print octal permission bits (e.g. 755).
platform::file_mode() { stat -c '%a' -- "$1"; }
