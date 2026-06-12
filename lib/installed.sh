# shellcheck shell=bash
# Installed: manage what `--install` put on this machine WITHOUT the original
# .bs file (the original could only uninstall through a script it sed-injected
# into the install dir at install time). An install of ours is recognized by
# the manifest + .bs-files pair in its app dir; anything else under /opt is
# somebody else's and is never touched.

installed::_user_root() { printf '%s/installer-bs' "${XDG_DATA_HOME:-$HOME/.local/share}"; }

# installed::_dirs SCOPE  (user|system) — print app dirs that are our installs.
installed::_dirs() {
	local root d
	case "$1" in
		user)   root="$(installed::_user_root)" ;;
		system) root=/opt ;;
	esac
	[[ -d "$root" ]] || return 0
	for d in "$root"/*/; do
		d="${d%/}"
		[[ -f "$d/manifest" && -f "$d/.bs-files" ]] && printf '%s\n' "$d"
	done
	return 0
}

# installed::list — table of installed packages across both scopes.
installed::list() {
	local scope d count=0
	for scope in user system; do
		while IFS= read -r d; do
			manifest::parse "$d/manifest" >/dev/null 2>&1 || continue
			printf '%-24s %-14s %-7s %s\n' \
				"${BS_MANIFEST[name]:-?}" "${BS_MANIFEST[version]:-?}" "$scope" "$d"
			count=$((count + 1))
		done < <(installed::_dirs "$scope")
	done
	((count)) || ui::info "$(i18n::t list_empty)"
}

# installed::uninstall NAME [--system] — remove by name, via the recorded
# .bs-files list, exactly like the package's own --uninstall would.
installed::uninstall() {
	local name="" system=false
	while (($#)); do
		case "$1" in
			--system) system=true ;;
			-*) ui::error "$(i18n::t err_unknown_flag "$1")"; return 2 ;;
			*)  if [[ -z "$name" ]]; then name="$1"; else ui::error "unexpected argument: $1"; return 2; fi ;;
		esac
		shift
	done
	[[ -n "$name" ]] || { ui::error "$(i18n::t err_uninstall_usage)"; return 2; }

	local dir
	if [[ "$system" == true ]]; then dir="/opt/$name"; else dir="$(installed::_user_root)/$name"; fi
	[[ -f "$dir/.bs-files" ]] || { ui::error "$(i18n::t err_not_installed "$name")"; return 1; }

	local ver=""
	manifest::parse "$dir/manifest" >/dev/null 2>&1 && ver="${BS_MANIFEST[version]:-}"
	ui::confirm "$(i18n::t uninstall_confirm "$name" "$ver" "$dir")" \
		|| { ui::info "$(i18n::t uninstall_cancelled)"; return 1; }

	local f
	while IFS= read -r f; do [[ -z "$f" ]] || rm -f -- "$f"; done < "$dir/.bs-files"
	rm -rf -- "$dir"

	local apps="${XDG_DATA_HOME:-$HOME/.local/share}/applications"
	[[ "$system" == true ]] && apps=/usr/local/share/applications
	command -v update-desktop-database >/dev/null 2>&1 && update-desktop-database "$apps" >/dev/null 2>&1 || true
	ui::ok "$(i18n::t uninstall_done "$name")"
}

# installed::info_name NAME — metadata + file list of an installed package.
# Returns 1 when the name is not installed in any scope (caller decides the error).
installed::info_name() {
	local name="$1" scope d found=1
	for scope in user system; do
		if [[ "$scope" == user ]]; then d="$(installed::_user_root)/$name"; else d="/opt/$name"; fi
		[[ -f "$d/manifest" && -f "$d/.bs-files" ]] || continue
		found=0
		manifest::parse "$d/manifest" || continue
		printf '%s %s (%s/%s) — installed, %s\n' \
			"${BS_MANIFEST[name]:-$name}" "${BS_MANIFEST[version]:-?}" \
			"${BS_MANIFEST[os]:-?}" "${BS_MANIFEST[arch]:-?}" "$scope"
		printf '  app   %s\n' "$d"
		local f
		while IFS= read -r f; do [[ -z "$f" ]] || printf '  file  %s\n' "$f"; done < "$d/.bs-files"
	done
	return "$found"
}

# installed::cache [list|clean [NAME]] — the portable-run extraction caches
# accumulate one dir per name-version forever; let the user see and drop them.
installed::cache() {
	local cmd="${1:-list}"
	(($#)) && shift
	local root="${XDG_CACHE_HOME:-$HOME/.cache}/installer-bs"
	case "$cmd" in
		list)
			local d any=0
			if [[ -d "$root" ]]; then
				for d in "$root"/*/; do
					d="${d%/}"
					[[ -d "$d" ]] || continue
					printf '%-10s %s\n' "$(du -sh -- "$d" 2>/dev/null | cut -f1)" "$d"
					any=1
				done
			fi
			((any)) || ui::info "$(i18n::t cache_empty)"
			;;
		clean)
			local name="${1:-}" d
			local -a targets=()
			if [[ -d "$root" ]]; then
				if [[ -n "$name" ]]; then
					for d in "$root/$name"-*/; do [[ -d "$d" ]] && targets+=("${d%/}"); done
				else
					for d in "$root"/*/; do [[ -d "$d" ]] && targets+=("${d%/}"); done
				fi
			fi
			((${#targets[@]})) || { ui::info "$(i18n::t cache_empty)"; return 0; }
			printf '%s\n' "${targets[@]}"
			ui::confirm "$(i18n::t cache_confirm "${#targets[@]}")" \
				|| { ui::info "$(i18n::t cache_cancelled)"; return 1; }
			rm -rf -- "${targets[@]}"
			ui::ok "$(i18n::t cache_cleaned "${#targets[@]}")"
			;;
		*)
			ui::error "$(i18n::t err_cache_usage)"; return 2 ;;
	esac
}
