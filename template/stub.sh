#!/usr/bin/env bash
# Installer-BS package runtime.
# `bs build` prepends this script to a tar(.xz) payload, with a single line
#   __BS_PAYLOAD__
# as the very last line of this script, after which the binary payload begins.
# A package is self-contained: it runs with only coreutils + tar (+ xz/gzip,
# which tar invokes automatically). Spec: docs/PACKAGE-FORMAT.md.
set -euo pipefail

BS_SELF="$(readlink -f -- "$0" 2>/dev/null || printf '%s' "$0")"

_bs_die() {
	printf 'bs: %s\n' "$1" >&2
	[[ -n "${2:-}" ]] && printf '    %s\n' "$2" >&2
	exit 1
}

# --- payload location -------------------------------------------------------
# The marker is matched only as a whole line, so the reference to it inside this
# function's source does not match. We take the first hit (always our marker).
_bs_payload_line() {
	grep -an '^__BS_PAYLOAD__$' "$BS_SELF" | head -1 | cut -d: -f1
}
# First line of the payload (the line after the marker).
_bs_payload_start() {
	local start; start="$(_bs_payload_line)"
	[[ -n "$start" ]] || _bs_die "no payload found in this package" \
		"This .bs is hollow inside. Like the promise to 'tame dependency hell'."
	printf '%s' "$((start + 1))"
}
# This tar does not autodetect compression from a pipe, so we pick the
# decompressor from the payload's magic bytes (xz: fd377a585a00, gzip: 1f8b).
_bs_decomp() { case "$1" in 1f8b*) gzip -dc ;; *) xz -dc ;; esac; }
_bs_magic() {
	local s; s="$(_bs_payload_start)"
	( set +o pipefail; tail -n +"$s" "$BS_SELF" | head -c6 | od -An -tx1 | tr -d ' \n' )
}
_bs_extract_all() {
	local s m; s="$(_bs_payload_start)"; m="$(_bs_magic)"
	tail -n +"$s" "$BS_SELF" | _bs_decomp "$m" | tar -x -C "$1"
}
_bs_read_member() {
	local s m; s="$(_bs_payload_start)"; m="$(_bs_magic)"
	tail -n +"$s" "$BS_SELF" | _bs_decomp "$m" | tar -xO "$1" 2>/dev/null || true
}

# --- manifest (parsed as DATA; never sourced) -------------------------------
declare -A MF=()
_bs_trim() { local s="$1"; s="${s#"${s%%[![:space:]]*}"}"; s="${s%"${s##*[![:space:]]}"}"; printf '%s' "$s"; }
_bs_load_manifest() {
	local line key val got=0
	while IFS= read -r line || [[ -n "$line" ]]; do
		line="${line%$'\r'}"
		[[ -z "${line//[[:space:]]/}" ]] && continue
		[[ "$(_bs_trim "$line")" == \#* ]] && continue
		[[ "$line" != *=* ]] && continue
		key="$(_bs_trim "${line%%=*}")"; val="$(_bs_trim "${line#*=}")"
		[[ -n "$key" ]] && { MF["$key"]="$val"; got=1; }
	done < <(_bs_read_member manifest)
	[[ "$got" == 1 ]] || _bs_die "package has no readable manifest"
	local k
	for k in name version arch os exec; do
		[[ -n "${MF[$k]:-}" ]] || _bs_die "manifest missing required field: $k"
	done
}

_bs_cache_dir() {
	printf '%s/installer-bs/%s-%s' "${XDG_CACHE_HOME:-$HOME/.cache}" "${MF[name]}" "${MF[version]}"
}

# Set up PATH / bundled libs / optional home isolation, given the app dir.
_bs_setup_env() {
	local dir="$1"
	export PATH="$dir/bin:$PATH"
	[[ -d "$dir/lib" ]] && export LD_LIBRARY_PATH="$dir/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
	if [[ "${MF[isolate_home]:-false}" == true ]]; then
		local h="$dir/home"; mkdir -p "$h"
		export HOME="$h" XDG_CONFIG_HOME="$h/.config" XDG_DATA_HOME="$h/.local/share" \
			XDG_STATE_HOME="$h/.local/state" XDG_CACHE_HOME="$h/.cache"
	fi
}

# --- modes ------------------------------------------------------------------
_bs_run() {
	_bs_load_manifest
	local cache; cache="$(_bs_cache_dir)"
	if [[ ! -e "$cache/.bs-ok" ]]; then
		rm -rf "$cache"; mkdir -p "$cache"
		_bs_extract_all "$cache"
		touch "$cache/.bs-ok"
	fi
	local exe="$cache/${MF[exec]}"
	[[ -e "$exe" ]] || _bs_die "executable not found in package: ${MF[exec]}"
	[[ -x "$exe" ]] || chmod +x "$exe" 2>/dev/null || true
	_bs_setup_env "$cache"
	exec "$exe" "$@"
}

_bs_extract_to() {
	_bs_load_manifest
	local dest="${1:-${MF[name]}-${MF[version]}}"
	mkdir -p "$dest"
	_bs_extract_all "$dest"
	printf 'extracted to %s\n' "$dest"
}

_bs_info() {
	_bs_load_manifest
	printf '%s %s (%s/%s)\n' "${MF[name]}" "${MF[version]}" "${MF[os]}" "${MF[arch]}"
	[[ -n "${MF[pretty_name]:-}" ]] && printf '  name        %s\n' "${MF[pretty_name]}"
	[[ -n "${MF[comment]:-}" ]]     && printf '  comment     %s\n' "${MF[comment]}"
	printf '  exec        %s\n' "${MF[exec]}"
	[[ -n "${MF[categories]:-}" ]]  && printf '  categories  %s\n' "${MF[categories]}"
	printf '  bundle_libs %s, isolate_home %s\n' "${MF[bundle_libs]:-false}" "${MF[isolate_home]:-false}"
}

# Resolve install destinations for user (default) or --system mode.
_bs_paths() {
	local name="$1" system="$2"
	if [[ "$system" == true ]]; then
		BS_DATADIR="/opt/$name"; BS_BINDIR="/usr/local/bin"
		BS_APPSDIR="/usr/local/share/applications"; BS_ICONDIR="/usr/local/share/icons"
	else
		local data="${XDG_DATA_HOME:-$HOME/.local/share}"
		BS_DATADIR="$data/installer-bs/$name"; BS_BINDIR="$HOME/.local/bin"
		BS_APPSDIR="$data/applications"; BS_ICONDIR="$data/icons"
	fi
}

_bs_install() {
	local system=false
	[[ "${1:-}" == --system ]] && { system=true; shift; }
	_bs_load_manifest
	local name="${MF[name]}"
	_bs_paths "$name" "$system"
	mkdir -p "$BS_DATADIR" "$BS_BINDIR" "$BS_APPSDIR"
	_bs_extract_all "$BS_DATADIR"

	local launcher="$BS_BINDIR/$name"
	local desktop="$BS_APPSDIR/$name.desktop"
	local iconfile=""
	[[ -n "${MF[icon]:-}" ]] && iconfile="$BS_ICONDIR/$name.${MF[icon]##*.}"

	# Launcher: references the fixed install dir (this is installed, not portable);
	# %q keeps the path safe. No sed-injection, no absolute paths baked by find+sed.
	{
		printf '#!/usr/bin/env bash\n'
		printf '# Generated by Installer-BS for %s. Do not edit.\n' "$name"
		printf 'APPDIR=%q\n' "$BS_DATADIR"
		printf 'export PATH="$APPDIR/bin:$PATH"\n'
		printf '[[ -d "$APPDIR/lib" ]] && export LD_LIBRARY_PATH="$APPDIR/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"\n'
		if [[ "${MF[isolate_home]:-false}" == true ]]; then
			printf 'export HOME="$APPDIR/home"; mkdir -p "$HOME"\n'
			printf 'export XDG_CONFIG_HOME="$HOME/.config" XDG_DATA_HOME="$HOME/.local/share" XDG_CACHE_HOME="$HOME/.cache" XDG_STATE_HOME="$HOME/.local/state"\n'
		fi
		printf 'exec "$APPDIR/%s" "$@"\n' "${MF[exec]}"
	} > "$launcher"
	chmod +x "$launcher"

	# Desktop entry generated from the manifest (Terminal defaults to false).
	{
		printf '[Desktop Entry]\n'
		printf 'Type=Application\n'
		printf 'Name=%s\n' "${MF[pretty_name]:-$name}"
		[[ -n "${MF[comment]:-}" ]] && printf 'Comment=%s\n' "${MF[comment]}"
		printf 'Exec=%s %%F\n' "$launcher"
		printf 'TryExec=%s\n' "$launcher"
		printf 'Terminal=%s\n' "${MF[terminal]:-false}"
		[[ -n "${MF[categories]:-}" ]] && printf 'Categories=%s\n' "${MF[categories]}"
		[[ -n "$iconfile" ]] && printf 'Icon=%s\n' "$iconfile"
	} > "$desktop"

	if [[ -n "$iconfile" && -e "$BS_DATADIR/${MF[icon]}" ]]; then
		mkdir -p "$BS_ICONDIR"
		cp -f "$BS_DATADIR/${MF[icon]}" "$iconfile"
	fi

	# Record the paths we created outside the app dir, for a clean --uninstall.
	{ printf '%s\n%s\n' "$launcher" "$desktop"; [[ -n "$iconfile" ]] && printf '%s\n' "$iconfile"; } > "$BS_DATADIR/.bs-files"

	command -v update-desktop-database >/dev/null 2>&1 && update-desktop-database "$BS_APPSDIR" >/dev/null 2>&1 || true

	printf 'installed %s %s\n' "$name" "${MF[version]}"
	printf '  app      %s\n' "$BS_DATADIR"
	printf '  launcher %s\n' "$launcher"
	printf '  menu     %s\n' "$desktop"
	printf 'No /portsoft was created in your filesystem root. XDG only.\n'
}

_bs_uninstall() {
	local system=false
	[[ "${1:-}" == --system ]] && { system=true; shift; }
	_bs_load_manifest
	local name="${MF[name]}"
	_bs_paths "$name" "$system"
	[[ -d "$BS_DATADIR" ]] || _bs_die "not installed: $BS_DATADIR"
	local f
	if [[ -f "$BS_DATADIR/.bs-files" ]]; then
		while IFS= read -r f; do [[ -n "$f" && -e "$f" ]] && rm -f "$f"; done < "$BS_DATADIR/.bs-files"
	fi
	rm -rf "$BS_DATADIR"
	command -v update-desktop-database >/dev/null 2>&1 && update-desktop-database "$BS_APPSDIR" >/dev/null 2>&1 || true
	printf 'uninstalled %s\n' "$name"
}

_bs_help() {
	_bs_load_manifest 2>/dev/null || true
	local self; self="$(basename "$BS_SELF")"
	cat <<EOF
${MF[name]:-package} ${MF[version]:-} — an Installer-BS package.

  ./$self [app args...]              run portably (no install)
  ./$self --install                 integrate into your user menu (XDG)
  sudo ./$self --install --system   integrate system-wide (/opt, /usr/local)
  ./$self --uninstall [--system]    remove an installed copy
  ./$self --extract [DIR]           unpack the payload
  ./$self --info                    print package metadata

Control options are recognized only as the FIRST argument; anything else is
passed straight to the application. We install into XDG / /opt — never a folder
in your filesystem root.
EOF
}

case "${1-run}" in
	--install)   shift; _bs_install "$@" ;;
	--uninstall) shift; _bs_uninstall "$@" ;;
	--extract)   shift; _bs_extract_to "${1-}" ;;
	--info)      _bs_info ;;
	--help|-h)   _bs_help ;;
	*)           _bs_run "$@" ;;
esac
exit $?
__BS_PAYLOAD__
