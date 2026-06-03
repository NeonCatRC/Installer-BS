# i18n: load locales/<lang>.sh based on $LANG, with English as the fallback base.
# Strings are data in associative arrays, never sourced-as-logic. Lookup by key
# means code holds no user-facing literals.

declare -gA BS_STR=()

# i18n::load [lang]
# English is loaded first as a complete fallback, then the requested language is
# overlaid on top, so a missing translation key degrades to English, not to blank.
i18n::load() {
	local lang="${1:-${LANG:-}}"
	lang="${lang%%[._]*}"   # ru_RU.UTF-8 -> ru
	lang="${lang,,}"
	[[ -z "$lang" || "$lang" == c || "$lang" == posix ]] && lang=en

	BS_STR=()
	# shellcheck source=locales/en.sh
	source "$BS_ROOT/locales/en.sh"
	local k
	for k in "${!BS_STR_EN[@]}"; do BS_STR["$k"]="${BS_STR_EN[$k]}"; done

	if [[ "$lang" != en && -f "$BS_ROOT/locales/$lang.sh" ]]; then
		# shellcheck disable=SC1090
		source "$BS_ROOT/locales/$lang.sh"
		local -n _overlay="BS_STR_${lang^^}"
		for k in "${!_overlay[@]}"; do BS_STR["$k"]="${_overlay[$k]}"; done
		# shellcheck disable=SC2034  # read by core.sh (debug line)
		BS_LANG="$lang"
	else
		# shellcheck disable=SC2034
		BS_LANG=en
	fi
}

# i18n::t KEY [printf-args...]
# Returns the localized string for KEY, formatted with any extra args.
i18n::t() {
	local key="$1"; shift
	local fmt="${BS_STR[$key]:-$key}"
	# shellcheck disable=SC2059  # fmt is an intentional, trusted format string
	printf "$fmt" "$@"
}
