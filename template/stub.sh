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
# function's source does not match. grep -m1 stops at the marker and never scans
# the binary payload behind it. The offset and magic are computed once and
# cached in globals (callers run in the main shell, so the cache sticks).
_BS_START="" _BS_MAGIC=""
_bs_locate_payload() {
	[[ -n "$_BS_START" ]] && return 0
	local line
	line="$(grep -m1 -an '^__BS_PAYLOAD__$' "$BS_SELF" | cut -d: -f1 || true)"
	[[ -n "$line" ]] || _bs_die "no payload found in this package" \
		"This .bs is hollow inside. Like the promise to 'tame dependency hell'."
	_BS_START=$((line + 1))
	# Payload's magic bytes pick the decompressor (xz: fd377a585a00, gzip: 1f8b);
	# this tar does not autodetect compression from a pipe.
	_BS_MAGIC="$( set +o pipefail; tail -n +"$_BS_START" "$BS_SELF" | head -c6 | od -An -tx1 | tr -d ' \n' )"
}
_bs_decomp() { case "$1" in 1f8b*) gzip -dc ;; *) xz -dc ;; esac; }
# Fail early with a clear, actionable message if the needed decompressor is absent
# (otherwise extraction silently yields nothing -> a confusing "no manifest").
_bs_check_decomp() {
	local tool; case "$1" in 1f8b*) tool=gzip ;; *) tool=xz ;; esac
	command -v "$tool" >/dev/null 2>&1 || _bs_die "this package needs '$tool' to unpack, and it isn't installed" \
		"install it (xz-utils / gzip), or rebuild the package with: bs build --gzip"
}
_bs_extract_all() {
	_bs_locate_payload
	_bs_check_decomp "$_BS_MAGIC"
	tail -n +"$_BS_START" "$BS_SELF" | _bs_decomp "$_BS_MAGIC" | tar -x -C "$1"
}
_bs_read_member() {
	_bs_locate_payload
	_bs_check_decomp "$_BS_MAGIC"
	tail -n +"$_BS_START" "$BS_SELF" | _bs_decomp "$_BS_MAGIC" | tar -xO "$1" 2>/dev/null || true
}

# --- manifest (parsed as DATA; never sourced) -------------------------------
declare -A MF=()
_bs_trim() { local s="$1"; s="${s#"${s%%[![:space:]]*}"}"; s="${s%"${s##*[![:space:]]}"}"; printf '%s' "$s"; }
_bs_load_manifest() {
	_bs_locate_payload                # cache offset/magic in the main shell
	_bs_check_decomp "$_BS_MAGIC"     # clear error here, not inside a subshell
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

_bs_dialog() {
	[[ -n "${DISPLAY:-}${WAYLAND_DISPLAY:-}" ]] || return 0
	if   command -v zenity   >/dev/null 2>&1; then zenity --error --no-wrap --title="Installer-BS" --text="$1" >/dev/null 2>&1 || true
	elif command -v kdialog  >/dev/null 2>&1; then kdialog --title "Installer-BS" --error "$1"                >/dev/null 2>&1 || true
	elif command -v xmessage >/dev/null 2>&1; then xmessage -center "$1"                                      >/dev/null 2>&1 || true
	fi
}

# --- platform guard ----------------------------------------------------------
# One package = one os/arch (the fix for the original's 8-binaries-per-package).
# So tell the user clearly when this is the wrong build, instead of letting the
# kernel mumble "Exec format error". Same uname normalization as lib/core.sh.
_bs_assert_platform() {
	[[ -z "${BS_NO_ARCH_CHECK:-}" ]] || return 0
	local os arch
	os="$(uname -s 2>/dev/null || echo unknown)"; os="${os,,}"
	arch="$(uname -m 2>/dev/null || echo unknown)"
	case "$arch" in
		x86_64|amd64)  arch=x86_64 ;;
		i?86)          arch=x86 ;;
		aarch64|arm64) arch=aarch64 ;;
		armv7l|armv6l) arch=armhf ;;
	esac
	# arch=any marks an architecture-independent payload (pure scripts, no ELF) —
	# e.g. the GUI launcher. The os field is still honoured.
	[[ "$os" == "${MF[os]}" && ( "${MF[arch]}" == any || "$arch" == "${MF[arch]}" ) ]] && return 0
	printf 'bs: this package is built for %s/%s, but this machine is %s/%s\n' "${MF[os]}" "${MF[arch]}" "$os" "$arch" >&2
	printf '    get a build for your platform, or set BS_NO_ARCH_CHECK=1 to try anyway\n' >&2
	printf '    (the original shipped 8 binaries per package and guessed; we just tell you)\n' >&2
	_bs_dialog "Installer-BS: cannot run ${MF[pretty_name]:-${MF[name]}}.

This package is built for ${MF[os]}/${MF[arch]}, but this machine is $os/$arch.
Get a build for your platform."
	exit 1
}

# --- glibc guard ------------------------------------------------------------
# A package built against glibc X cannot run on an older glibc. The builder
# records min_glibc; here we warn clearly (a GUI dialog when available) instead
# of letting the loader die with a cryptic "version 'GLIBC_2.x' not found".
_bs_host_glibc() {
	local v; v="$(getconf GNU_LIBC_VERSION 2>/dev/null)"; v="${v##* }"
	[[ "$v" =~ ^[0-9]+\.[0-9]+ ]] || v="$(ldd --version 2>/dev/null | head -1 | grep -oE '[0-9]+\.[0-9]+' | tail -1)"
	[[ "$v" =~ ^[0-9]+\.[0-9]+ ]] && printf '%s' "$v"
}
_bs_vlt() { [[ "$1" != "$2" && "$(printf '%s\n%s\n' "$1" "$2" | sort -V | head -1)" == "$1" ]]; }
_bs_assert_glibc() {
	local need="${MF[min_glibc]:-}"
	[[ -n "$need" && -z "${BS_NO_GLIBC_CHECK:-}" ]] || return 0
	local have; have="$(_bs_host_glibc)"
	[[ -n "$have" ]] || return 0
	_bs_vlt "$have" "$need" || return 0
	printf 'bs: this system has glibc %s, but this package needs >= %s\n' "$have" "$need" >&2
	printf '    it will not run here — use a build for an older glibc, or set BS_NO_GLIBC_CHECK=1 to force\n' >&2
	_bs_dialog "Installer-BS: cannot run ${MF[pretty_name]:-${MF[name]}}.

This package needs glibc >= $need, but this system has $have.
Use a build made for an older glibc, or set BS_NO_GLIBC_CHECK=1 to try anyway."
	exit 1
}

# --- modes ------------------------------------------------------------------
_bs_run() {
	_bs_load_manifest
	_bs_assert_platform
	_bs_assert_glibc
	local cache id; cache="$(_bs_cache_dir)"; id="${MF[build_id]:-}"
	# The cache is keyed on build_id: a rebuilt package with the same
	# name-version re-extracts instead of running stale files.
	if [[ ! -e "$cache/.bs-ok" || "$(cat "$cache/.bs-ok" 2>/dev/null)" != "$id" ]]; then
		mkdir -p "${cache%/*}"
		local tmp; tmp="$(mktemp -d "$cache.tmp.XXXXXX")"
		_bs_extract_all "$tmp"
		printf '%s\n' "$id" > "$tmp/.bs-ok"
		# Publish atomically (rename), so concurrent first runs never see a
		# half-extracted tree. If another process won the race, use its copy.
		if [[ -e "$cache" ]]; then
			if mv -- "$cache" "$cache.old.$$" 2>/dev/null; then rm -rf -- "$cache.old.$$"; fi
		fi
		mv -T -- "$tmp" "$cache" 2>/dev/null || rm -rf -- "$tmp"
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

# Integrity self-test. No checksum is embedded in this file (a hash stored in
# the file it "protects" is the original's MD5 theater all over again). Instead
# the payload is streamed through the decompressor, whose container checksums
# (xz CRC64 / gzip CRC32) catch corruption and truncation. Sidecar files beside
# the package (.sha256, .sig) are verified too when present.
_bs_check() {
	_bs_load_manifest
	local n
	if n="$(tail -n +"$_BS_START" "$BS_SELF" | _bs_decomp "$_BS_MAGIC" | tar -t | wc -l)"; then
		printf 'payload ok: %s member(s), container checksums intact\n' "$((n))"
	else
		_bs_die "payload is corrupt or truncated" "re-download this package and check again"
	fi
	if [[ -f "$BS_SELF.sha256" ]] && command -v sha256sum >/dev/null 2>&1; then
		if ( cd "$(dirname -- "$BS_SELF")" && sha256sum -c --status "$(basename -- "$BS_SELF").sha256" ) 2>/dev/null; then
			printf 'sha256 sidecar ok\n'
		else
			_bs_die "sha256 sidecar MISMATCH — this copy is not the one that was built"
		fi
	fi
	if [[ -f "$BS_SELF.sig" ]]; then
		if command -v gpg >/dev/null 2>&1; then
			if gpg --verify "$BS_SELF.sig" "$BS_SELF" >/dev/null 2>&1; then
				printf 'OpenPGP signature ok\n'
			else
				_bs_die "BAD OpenPGP signature — do not run this file"
			fi
		else
			printf 'signature present, but gpg is not installed — authorship not verified\n'
		fi
	fi
	printf 'note: this checks corruption; authorship is the OpenPGP .sig, not vibes\n'
}

_bs_info() {
	_bs_load_manifest
	printf '%s %s (%s/%s)\n' "${MF[name]}" "${MF[version]}" "${MF[os]}" "${MF[arch]}"
	[[ -n "${MF[pretty_name]:-}" ]] && printf '  name        %s\n' "${MF[pretty_name]}"
	[[ -n "${MF[comment]:-}" ]]     && printf '  comment     %s\n' "${MF[comment]}"
	printf '  exec        %s\n' "${MF[exec]}"
	[[ -n "${MF[extra_exec]:-}" ]]  && printf '  extra_exec  %s\n' "${MF[extra_exec]}"
	[[ -n "${MF[categories]:-}" ]]  && printf '  categories  %s\n' "${MF[categories]}"
	[[ -n "${MF[mime_types]:-}" ]]  && printf '  mime_types  %s\n' "${MF[mime_types]}"
	[[ -n "${MF[min_glibc]:-}" ]]   && printf '  min_glibc   %s\n' "${MF[min_glibc]}"
	[[ -n "${MF[build_id]:-}" ]]    && printf '  build_id    %s\n' "${MF[build_id]:0:12}"
	printf '  bundle_libs %s, isolate_home %s\n' "${MF[bundle_libs]:-false}" "${MF[isolate_home]:-false}"
}

# Resolve install destinations for user (default) or --system mode.
_bs_paths() {
	local name="$1" system="$2"
	if [[ "$system" == true ]]; then
		BS_DATADIR="/opt/$name"; BS_BINDIR="/usr/local/bin"
		BS_APPSDIR="/usr/local/share/applications"; BS_ICONDIR="/usr/local/share/icons"
		BS_MANDIR="/usr/local/share/man"; BS_COMPDIR="/usr/local/share/bash-completion/completions"
	else
		local data="${XDG_DATA_HOME:-$HOME/.local/share}"
		BS_DATADIR="$data/installer-bs/$name"; BS_BINDIR="$HOME/.local/bin"
		BS_APPSDIR="$data/applications"; BS_ICONDIR="$data/icons"
		BS_MANDIR="$data/man"; BS_COMPDIR="$data/bash-completion/completions"
	fi
}

# Write a launcher that references the fixed install dir (this is installed, not
# portable); %q keeps the path safe. No sed-injection, no paths baked by find+sed.
_bs_write_launcher() {
	local file="$1" exec_rel="$2"
	# shellcheck disable=SC2016  # these refs must stay literal; they expand in the generated launcher
	{
		printf '#!/usr/bin/env bash\n'
		printf '# Generated by Installer-BS for %s. Do not edit.\n' "${MF[name]}"
		printf 'APPDIR=%q\n' "$BS_DATADIR"
		printf 'export PATH="$APPDIR/bin:$PATH"\n'
		printf '[[ -d "$APPDIR/lib" ]] && export LD_LIBRARY_PATH="$APPDIR/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"\n'
		if [[ "${MF[isolate_home]:-false}" == true ]]; then
			printf 'export HOME="$APPDIR/home"; mkdir -p "$HOME"\n'
			printf 'export XDG_CONFIG_HOME="$HOME/.config" XDG_DATA_HOME="$HOME/.local/share" XDG_CACHE_HOME="$HOME/.cache" XDG_STATE_HOME="$HOME/.local/state"\n'
		fi
		printf 'exec "$APPDIR/%s" "$@"\n' "$exec_rel"
	} > "$file"
	chmod +x "$file"
}

_bs_install() {
	local system=false
	[[ "${1:-}" == --system ]] && { system=true; shift; }
	_bs_load_manifest
	_bs_assert_platform
	_bs_assert_glibc
	local name="${MF[name]}"
	_bs_paths "$name" "$system"

	# Upgrade path: an existing install is replaced cleanly — the old version's
	# recorded files and payload go away (no orphans from removed files), but
	# the isolated home with the user's data survives.
	if [[ -d "$BS_DATADIR" ]]; then
		local oldver="" f
		oldver="$(sed -n 's/^[[:space:]]*version[[:space:]]*=[[:space:]]*//p' "$BS_DATADIR/manifest" 2>/dev/null | head -1)" || true
		if [[ -f "$BS_DATADIR/.bs-files" ]]; then
			while IFS= read -r f; do [[ -z "$f" ]] || rm -f -- "$f"; done < "$BS_DATADIR/.bs-files"
		fi
		local keep="$BS_DATADIR.bs-home-keep.$$"
		[[ -d "$BS_DATADIR/home" ]] && mv -- "$BS_DATADIR/home" "$keep"
		rm -rf -- "$BS_DATADIR"
		mkdir -p "$BS_DATADIR"
		[[ -d "$keep" ]] && mv -- "$keep" "$BS_DATADIR/home"
		[[ -n "$oldver" ]] && printf 'replacing installed %s %s\n' "$name" "$oldver"
	fi

	mkdir -p "$BS_DATADIR" "$BS_BINDIR" "$BS_APPSDIR"
	_bs_extract_all "$BS_DATADIR"

	local -a files=()
	local launcher="$BS_BINDIR/$name"
	local desktop="$BS_APPSDIR/$name.desktop"
	_bs_write_launcher "$launcher" "${MF[exec]}"
	files+=("$launcher")

	# Extra executables (manifest extra_exec): one launcher per basename.
	local -a extras=()
	[[ -n "${MF[extra_exec]:-}" ]] && read -r -a extras <<< "${MF[extra_exec]}"
	local x
	for x in "${extras[@]}"; do
		_bs_write_launcher "$BS_BINDIR/${x##*/}" "$x"
		files+=("$BS_BINDIR/${x##*/}")
	done

	# Icon goes into the hicolor theme (scalable for svg, NxN for raster with
	# icon_size, default 256), so Icon= can be the themed name, not a path.
	local iconfile="" icon_name=""
	if [[ -n "${MF[icon]:-}" && -e "$BS_DATADIR/${MF[icon]}" ]]; then
		local ext="${MF[icon]##*.}"
		if [[ "$ext" == svg ]]; then
			iconfile="$BS_ICONDIR/hicolor/scalable/apps/$name.svg"
		else
			local sz="${MF[icon_size]:-256}"
			iconfile="$BS_ICONDIR/hicolor/${sz}x${sz}/apps/$name.$ext"
		fi
		mkdir -p "${iconfile%/*}"
		cp -f -- "$BS_DATADIR/${MF[icon]}" "$iconfile"
		icon_name="$name"
		files+=("$iconfile")
	fi

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
		[[ -n "${MF[mime_types]:-}" ]] && printf 'MimeType=%s\n' "${MF[mime_types]}"
		[[ -n "$icon_name" ]] && printf 'Icon=%s\n' "$icon_name"
	} > "$desktop"
	files+=("$desktop")

	# Man pages: anything under share/man/man<N>/ is linked into the standard
	# man path (man-db finds it next to the launcher's bin dir automatically).
	if [[ -d "$BS_DATADIR/share/man" ]]; then
		local mp sec
		while IFS= read -r mp; do
			sec="${mp%/*}"; sec="${sec##*/}"
			mkdir -p "$BS_MANDIR/$sec"
			ln -sf -- "$mp" "$BS_MANDIR/$sec/${mp##*/}"
			files+=("$BS_MANDIR/$sec/${mp##*/}")
		done < <(find "$BS_DATADIR/share/man" -type f -path '*/share/man/man[0-9n]/*' 2>/dev/null)
	fi

	# Bash completion (manifest bash_completion: path inside the payload).
	if [[ -n "${MF[bash_completion]:-}" && -e "$BS_DATADIR/${MF[bash_completion]}" ]]; then
		mkdir -p "$BS_COMPDIR"
		ln -sf -- "$BS_DATADIR/${MF[bash_completion]}" "$BS_COMPDIR/$name"
		files+=("$BS_COMPDIR/$name")
	fi

	# Record the paths we created outside the app dir, for a clean --uninstall.
	printf '%s\n' "${files[@]}" > "$BS_DATADIR/.bs-files"

	command -v update-desktop-database >/dev/null 2>&1 && update-desktop-database "$BS_APPSDIR" >/dev/null 2>&1 || true
	command -v gtk-update-icon-cache  >/dev/null 2>&1 && gtk-update-icon-cache -q "$BS_ICONDIR/hicolor" >/dev/null 2>&1 || true

	printf 'installed %s %s\n' "$name" "${MF[version]}"
	printf '  app      %s\n' "$BS_DATADIR"
	printf '  launcher %s\n' "$launcher"
	printf '  menu     %s\n' "$desktop"
	printf 'No /portsoft was created in your filesystem root. XDG only.\n'
	case ":$PATH:" in
		*":$BS_BINDIR:"*) ;;
		*) printf 'note: %s is not on your PATH — add it to run %s by name\n' "$BS_BINDIR" "$name" ;;
	esac
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
		while IFS= read -r f; do [[ -z "$f" ]] || rm -f -- "$f"; done < "$BS_DATADIR/.bs-files"
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
  ./$self --check                   self-test payload integrity (+ sidecars)
  ./$self --info                    print package metadata
  ./$self --help                    this help

Control options are recognized only as the FIRST argument; anything else is
passed straight to the application. We install into XDG / /opt — never a folder
in your filesystem root.
EOF
}

case "${1-run}" in
	--install)   shift; _bs_install "$@" ;;
	--uninstall) shift; _bs_uninstall "$@" ;;
	--extract)   shift; _bs_extract_to "${1-}" ;;
	--check)     _bs_check ;;
	--info)      _bs_info ;;
	--help|-h)   _bs_help ;;
	*)           _bs_run "$@" ;;
esac
exit $?
# shellcheck disable=SC2317  # payload marker; bs build appends the tar stream below this line
__BS_PAYLOAD__
