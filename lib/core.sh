# Core: single source of truth for platform detection, global flag parsing and
# the subcommand dispatcher. No logic is duplicated across modules.

BS_NAME="installer-bs"
BS_VERSION="0.1.0"
readonly BS_NAME BS_VERSION

# core::detect_platform
# Normalizes uname into BS_OS / BS_ARCH. The ONLY place the platform is detected
# (the original duplicated this across three files). Non-fatal on unusual systems:
# the tool is just bash and may be inspected anywhere; `bs build` enforces a
# supported target later.
core::detect_platform() {
	local os arch
	os="$(uname -s 2>/dev/null || echo unknown)"
	arch="$(uname -m 2>/dev/null || echo unknown)"
	case "$os" in
		Linux) BS_OS=linux ;;
		*)     BS_OS="${os,,}" ;;
	esac
	case "$arch" in
		x86_64|amd64)  BS_ARCH=x86_64 ;;
		i?86)          BS_ARCH=x86 ;;
		aarch64|arm64) BS_ARCH=aarch64 ;;
		armv7l|armv6l) BS_ARCH=armhf ;;
		*)             BS_ARCH="$arch" ;;
	esac
}

# core::dispatch "$@"
# Parses global flags and routes to a subcommand.
core::dispatch() {
	local cmd=""
	local -a rest=()
	# Global flags are parsed only until the subcommand token. Everything after
	# it belongs to the subcommand (so `bs build src -o out` reaches pack::build).
	while (($#)) && [[ -z "$cmd" ]]; do
		case "$1" in
			-h|--help)    cmd=help ;;
			-V|--version) cmd=version ;;
			-y|--yes)     ui::set_assume_yes ;;
			--no-color)   ui::set_no_color ;;
			--debug)      BS_DEBUG=true ;;
			--lang)       shift; LANG="${1:-}"; i18n::load ;;
			--lang=*)     LANG="${1#*=}"; i18n::load ;;
			--)           shift; if (($#)); then cmd="$1"; shift; fi; break ;;
			-*)           ui::error "$(i18n::t err_unknown_flag "$1")"; return 2 ;;
			*)            cmd="$1" ;;
		esac
		shift
	done
	rest=("$@")

	if [[ "${BS_DEBUG:-false}" == true ]]; then
		core::detect_platform
		ui::info "debug: $BS_NAME $BS_VERSION on ${BS_OS}/${BS_ARCH}, lang=${BS_LANG:-en}, args=[${rest[*]:-}]"
	fi

	case "${cmd:-help}" in
		help)    core::cmd_help ;;
		version) core::cmd_version ;;
		build)   pack::build "${rest[@]}" ;;
		info)    core::cmd_info "${rest[@]}" ;;
		*)       ui::error "$(i18n::t err_unknown_command "$cmd")"; return 2 ;;
	esac
}

# core::cmd_info PKG
# Show a .bs package's metadata by delegating to its self-contained runtime.
core::cmd_info() {
	local pkg="${1:-}"
	[[ -n "$pkg" ]] || { ui::error "$(i18n::t err_info_usage)"; return 2; }
	[[ -f "$pkg" ]] || { ui::error "$(i18n::t err_not_found "$pkg")"; return 1; }
	bash "$pkg" --info
}

core::cmd_version() {
	core::detect_platform
	printf '%s %s (%s/%s)\n' "$BS_NAME" "$BS_VERSION" "$BS_OS" "$BS_ARCH"
	ui::info "$(i18n::t version_quip)"
}

core::cmd_help() {
	cat <<EOF
$(i18n::t app_tagline)

$(i18n::t help_usage)

$(i18n::t help_commands)
  build    $(i18n::t help_build)
  info     $(i18n::t help_info)
  version  $(i18n::t help_version)
  help     $(i18n::t help_help)

$(i18n::t help_options)
  -y, --yes        $(i18n::t help_opt_yes)
      --lang LANG  $(i18n::t help_opt_lang)
      --no-color   $(i18n::t help_opt_nocolor)
      --debug      $(i18n::t help_opt_debug)
  -h, --help       $(i18n::t help_opt_help)
  -V, --version    $(i18n::t help_opt_version)

$(i18n::t help_footer)
EOF
}
