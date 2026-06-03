# UI helpers: consistent, pipe-friendly output.
# Colors auto-disable when stdout is not a TTY or when NO_COLOR is set.
# TODO(WP1): full theming and route every user string through i18n.

if [[ -t 1 && -z "${NO_COLOR:-}" ]]; then
	_bs_reset=$'\e[0m'; _bs_red=$'\e[31m'; _bs_yellow=$'\e[33m'; _bs_green=$'\e[32m'; _bs_dim=$'\e[2m'
else
	_bs_reset=''; _bs_red=''; _bs_yellow=''; _bs_green=''; _bs_dim=''
fi

ui::info()  { printf '%s\n' "${_bs_dim}::${_bs_reset} $*"; }
ui::ok()    { printf '%s\n' "${_bs_green}ok:${_bs_reset} $*"; }
ui::warn()  { printf '%s\n' "${_bs_yellow}warn:${_bs_reset} $*" >&2; }
ui::error() { printf '%s\n' "${_bs_red}error:${_bs_reset} $*" >&2; }

# Prompt for a yes/no decision. Honors a global --yes (BS_ASSUME_YES) and
# non-interactive sessions. TODO(WP1): wire BS_ASSUME_YES from core arg parsing.
ui::confirm() {
	local prompt="${1:-Continue?}"
	if [[ "${BS_ASSUME_YES:-false}" == true || ! -t 0 ]]; then
		return 0
	fi
	local reply
	read -r -p "$prompt [y/N] " reply
	[[ "$reply" == y || "$reply" == yes ]]
}
