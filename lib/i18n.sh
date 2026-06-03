# i18n: load locales/<lang>.sh based on $LANG, fall back to English.
# Strings are looked up by key so code never holds user-facing literals.
# TODO(WP1): implement loading and lookup; populate locales/{en,ru}.sh.

# i18n::load [lang]
# Picks the locale from the argument or $LANG, defaults to "en".
i18n::load() {
	# TODO(WP1): source "$BS_ROOT/locales/<lang>.sh" with an en fallback.
	:
}

# i18n::t KEY
# Returns the localized string for KEY (English fallback).
i18n::t() {
	# TODO(WP1): echo "${BS_STR[$1]:-$1}"
	printf '%s' "${1:-}"
}
