# shellcheck shell=bash
# English locale — base/fallback. Strings are data, referenced via i18n::t.
# Values may contain printf format specifiers (e.g. %s).
# shellcheck disable=SC2034  # consumed by i18n::load via indirect expansion.

declare -gA BS_STR_EN=(
	[app_tagline]="installer-bs — Bundled Software. We did not solve dependency hell; we wrapped it in a tarball and moved on."

	[help_usage]="Usage: bs <command> [options]"
	[help_commands]="Commands:"
	[help_build]="Build a .bs package from a source dir + manifest."
	[help_info]="Show a .bs package's manifest."
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

	[err_unknown_command]="Unknown command: %s. Try 'bs --help'."
	[err_unknown_flag]="Unknown option: %s. Try 'bs --help'."
	[err_info_usage]="Usage: bs info <package.bs | installed-name>"
	[err_build_usage]="Usage: bs build <src-dir> [-o out.bs] [--gzip]"
	[err_is_recipe]="that looks like a recipe — build it with: bs make %s"
	[err_not_found]="File or directory not found: %s"

	[build_done]="built %s"
	[build_size]="size: %s"
	[build_overwrite]="Overwrite %s?"
	[build_cancelled]="build cancelled"

	[help_make]="Build a package from a recipe (fetch upstream, verify, pack)."
	[help_sign]="Sign a package with OpenPGP (gpg)."
	[help_verify]="Verify a package's signature and checksum."
	[err_make_usage]="Usage: bs make <recipe> [-o out.bs]"
	[err_sign_usage]="Usage: bs sign <package.bs> [-k KEYID]"
	[err_verify_usage]="Usage: bs verify <package.bs>"
	[err_no_gpg]="gpg not found (install GnuPG to sign/verify)"
	[sign_done]="signed -> %s"
	[sign_fail]="signing failed"
	[verify_sha_ok]="checksum ok (sha256)"
	[verify_sha_bad]="CHECKSUM MISMATCH (sha256)"
	[verify_sig_ok]="signature ok (OpenPGP)"
	[verify_sig_bad]="BAD SIGNATURE (OpenPGP)"
	[verify_nothing]="nothing to verify (no .sig or .sha256 beside the package)"

	[help_run]="Run a .bs package (same as executing it directly)."
	[help_list]="List installed packages (user and system)."
	[help_uninstall]="Uninstall a package by name — the .bs file is not needed."
	[help_cache]="Show or clean the portable-run extraction caches."
	[err_run_usage]="Usage: bs run <package.bs> [args...]"
	[err_uninstall_usage]="Usage: bs uninstall <name> [--system]"
	[err_cache_usage]="Usage: bs cache [list | clean [name]]"
	[err_not_installed]="not installed: %s (see 'bs list')"
	[list_empty]="nothing installed. Your filesystem root remains unpolluted."
	[uninstall_confirm]="Remove %s %s (%s)?"
	[uninstall_cancelled]="uninstall cancelled"
	[uninstall_done]="uninstalled %s"
	[cache_empty]="cache is empty — nothing extracted, nothing hoarded"
	[cache_confirm]="Remove these %s cache dir(s)?"
	[cache_cancelled]="cache clean cancelled"
	[cache_cleaned]="removed %s cache dir(s)"
)
