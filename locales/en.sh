# English locale. Keys are referenced from code via i18n::t.
# TODO(WP1): fill the full set of user-facing strings.
# shellcheck disable=SC2034  # populated/consumed by i18n once WP1 lands.

declare -gA BS_STR_EN=(
	[app_tagline]="Bundled Software. We did not solve dependency hell — we wrapped it."
	[err_unsupported_platform]="Unsupported platform: %s"
)
