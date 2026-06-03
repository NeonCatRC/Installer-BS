# English locale — base/fallback. Strings are data, referenced via i18n::t.
# Values may contain printf format specifiers (e.g. %s).
# shellcheck disable=SC2034  # consumed by i18n::load via indirect expansion.

declare -gA BS_STR_EN=(
	[app_tagline]="installer-bs — Bundled Software. We did not solve dependency hell; we wrapped it in a tarball and moved on."

	[help_usage]="Usage: bs <command> [options]"
	[help_commands]="Commands:"
	[help_build]="Build a .bs package from a source dir + manifest (WP3)."
	[help_info]="Show a .bs package's manifest (WP2)."
	[help_version]="Print version and detected platform."
	[help_help]="Show this help."
	[help_options]="Options:"
	[help_opt_yes]="Assume yes; never prompt (good for scripts)."
	[help_opt_lang]="Force interface language (e.g. en, ru)."
	[help_opt_nocolor]="Disable colored output."
	[help_opt_debug]="Verbose debug output."
	[help_opt_help]="Show this help."
	[help_opt_version]="Print version."
	[help_footer]="Plan: docs/dev/AGENT-TASKS.md  -  Museum of the original's sins: docs/MUSEUM.md"

	[version_quip]="No /portsoft was created in your filesystem root. You're welcome."

	[err_unsupported_platform]="Unsupported platform: %s"
	[err_unknown_command]="Unknown command: %s. Try 'bs --help'."
	[err_unknown_flag]="Unknown option: %s. Try 'bs --help'."
	[err_pending]="'%s' is not wired up yet — it lands in %s."
)
