# UI helpers: consistent, pipe-friendly output.
# Colors auto-disable when stdout is not a TTY or when NO_COLOR is set.
# Color/confirm state is owned here so the rest of the code never juggles globals.

_bs_assume_yes=false

# Recompute color escapes. Called at load and again after --no-color.
ui::init_colors() {
	if [[ -t 1 && -z "${NO_COLOR:-}" ]]; then
		_bs_reset=$'\e[0m'; _bs_red=$'\e[31m'; _bs_yellow=$'\e[33m'; _bs_green=$'\e[32m'; _bs_dim=$'\e[2m'
	else
		_bs_reset=''; _bs_red=''; _bs_yellow=''; _bs_green=''; _bs_dim=''
	fi
}
ui::init_colors

ui::set_no_color()  { NO_COLOR=1; ui::init_colors; }
ui::set_assume_yes() { _bs_assume_yes=true; }

ui::info()  { printf '%s\n' "${_bs_dim}::${_bs_reset} $*"; }
ui::ok()    { printf '%s\n' "${_bs_green}ok:${_bs_reset} $*"; }
ui::warn()  { printf '%s\n' "${_bs_yellow}warn:${_bs_reset} $*" >&2; }
ui::error() { printf '%s\n' "${_bs_red}error:${_bs_reset} $*" >&2; }

# Ask a yes/no question. Honors --yes and non-interactive stdin (returns yes).
ui::confirm() {
	local prompt="${1:-Continue?}"
	if [[ "$_bs_assume_yes" == true || ! -t 0 ]]; then
		return 0
	fi
	local reply
	read -r -p "$prompt [y/N] " reply
	[[ "$reply" == y || "$reply" == yes ]]
}
