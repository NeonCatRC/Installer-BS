# shellcheck shell=bash
# Recipe: build a .bs from a declarative recipe that fetches a real upstream
# artifact (e.g. Krita's official AppImage), verifies its checksum, lays out a
# package directory and hands it to the packager. A recipe is a small bash file
# authored by the packager — trusted, like a PKGBUILD — sourced in a scoped way.
#
# A recipe sets: name, version, arch, os, exec (required) and optionally
# pretty_name, comment, categories, icon, terminal, bundle_libs, isolate_home.
# To obtain the files it either:
#   - declares source_url + source_type (appimage|tar|file) [+ source_sha256], or
#   - defines a prepare() function that populates $pkgdir (using bs_fetch etc.).

# --- helpers exposed to recipes ---------------------------------------------

# bs_fetch URL DEST [SHA256] — fetch URL to DEST, verifying sha256 if given.
# A local path or file:// URL is copied directly (handy for offline recipes/tests).
# Checksummed downloads are kept in a content-addressed cache (keyed by the
# sha256, so reuse is safe by construction); a repeated `bs make` works offline.
# Unverified downloads are never cached. Disable with BS_NO_FETCH_CACHE=1.
bs_fetch() {
	local url="$1" dest="$2" want="${3:-}" src="$1"
	[[ "$src" == file://* ]] && src="${src#file://}"
	local cache="" fetched=0
	[[ -n "$want" && -z "${BS_NO_FETCH_CACHE:-}" ]] \
		&& cache="${XDG_CACHE_HOME:-$HOME/.cache}/installer-bs/downloads/sha256-$want"

	if [[ -f "$src" ]]; then
		ui::info "copying $src"
		cp -- "$src" "$dest" || { ui::error "copy failed: $src"; return 1; }
	elif [[ -n "$cache" && -f "$cache" ]]; then
		ui::info "cached download: $url"
		cp -- "$cache" "$dest" || { ui::error "copy failed: $cache"; return 1; }
	else
		ui::info "fetching $url"
		if command -v curl >/dev/null 2>&1; then
			curl -fL --retry 2 -o "$dest" -- "$url" || { ui::error "download failed: $url"; return 1; }
		elif command -v wget >/dev/null 2>&1; then
			wget -q -O "$dest" -- "$url" || { ui::error "download failed: $url"; return 1; }
		else
			ui::error "need curl or wget to fetch sources"; return 127
		fi
		fetched=1
	fi

	if [[ -n "$want" ]]; then
		command -v sha256sum >/dev/null 2>&1 || { ui::error "sha256sum needed to verify source"; return 127; }
		local got; got="$(sha256sum "$dest" | cut -d' ' -f1)"
		if [[ "$got" != "$want" ]]; then
			ui::error "source sha256 mismatch"
			ui::info "  want $want"
			ui::info "  got  $got"
			# A cached copy that no longer matches is poison — drop it.
			[[ -n "$cache" && -f "$cache" ]] && rm -f -- "$cache"
			return 1
		fi
		ui::ok "source sha256 verified"
		if [[ "$fetched" == 1 && -n "$cache" && ! -f "$cache" ]]; then
			mkdir -p "${cache%/*}"
			cp -- "$dest" "$cache" 2>/dev/null || true
		fi
	else
		ui::warn "no source_sha256 given — using the download unverified"
	fi
}

# bs_fetch_all — fetch every URL of the recipe's sources=() array into $srcdir,
# verified against sha256s=() by index. For multi-input recipes with their own
# prepare(); each file lands as $srcdir/<basename of the URL>.
bs_fetch_all() {
	local i url dest
	((${#sources[@]})) || { ui::error "recipe sets no sources=() array"; return 1; }
	for i in "${!sources[@]}"; do
		url="${sources[$i]}"
		dest="$srcdir/$(basename -- "${url%%\?*}")"
		bs_fetch "$url" "$dest" "${sha256s[$i]:-}" || return 1
	done
}

# bs_zip_extract FILE DESTDIR — extract a zip source (unzip, or bsdtar fallback).
bs_zip_extract() {
	local file="$1" dest="$2"
	mkdir -p "$dest"
	if command -v unzip >/dev/null 2>&1; then
		unzip -q -- "$file" -d "$dest" || { ui::error "zip extract failed"; return 1; }
	elif command -v bsdtar >/dev/null 2>&1; then
		bsdtar -xf "$file" -C "$dest" || { ui::error "zip extract failed"; return 1; }
	else
		ui::error "need unzip (or bsdtar) to extract zip sources"; return 127
	fi
}

# bs_deb_extract FILE DESTDIR — unpack a .deb's data tree (usr/bin, usr/share...).
# A .deb is an ar archive holding data.tar.<comp>; no dpkg is needed to read it.
bs_deb_extract() {
	local file="$1" dest="$2" member
	mkdir -p "$dest"
	if command -v ar >/dev/null 2>&1; then
		# No -m1/head here: early pipe close would SIGPIPE `ar` under pipefail.
		member="$(ar t "$file" 2>/dev/null | grep '^data\.tar' || true)"
		member="${member%%$'\n'*}"
		[[ -n "$member" ]] || { ui::error "not a .deb (no data.tar member): $file"; return 1; }
		local -a decomp
		case "$member" in
			*.xz)  decomp=(xz -dc) ;;
			*.gz)  decomp=(gzip -dc) ;;
			*.zst) decomp=(zstd -dc) ;;
			*.bz2) decomp=(bzip2 -dc) ;;
			*.tar) decomp=(cat) ;;
			*)     ui::error "unsupported deb data member: $member"; return 1 ;;
		esac
		command -v "${decomp[0]}" >/dev/null 2>&1 \
			|| { ui::error "need ${decomp[0]} to unpack $member"; return 127; }
		ar p "$file" "$member" | "${decomp[@]}" | tar -x -C "$dest" \
			|| { ui::error "deb extract failed"; return 1; }
	elif command -v bsdtar >/dev/null 2>&1; then
		bsdtar -xOf "$file" 'data.tar*' | bsdtar -xf - -C "$dest" \
			|| { ui::error "deb extract failed"; return 1; }
	else
		ui::error "need binutils 'ar' (or bsdtar) to extract .deb sources"; return 127
	fi
}

# bs_appimage_extract FILE DESTDIR — extract an AppImage's tree into DESTDIR.
# Needs a Linux host of the matching architecture (the AppImage self-extracts).
bs_appimage_extract() {
	local file="$1" dest="$2" wd
	chmod +x "$file" 2>/dev/null || true
	wd="$(mktemp -d)"
	if ( cd "$wd" && "$file" --appimage-extract >/dev/null 2>&1 ) && [[ -d "$wd/squashfs-root" ]]; then
		mkdir -p "$dest"; cp -a "$wd/squashfs-root/." "$dest/"
		rm -rf "$wd"
	else
		rm -rf "$wd"
		ui::error "AppImage extraction failed (need a Linux host of the right architecture)"
		return 1
	fi
}

# --- runner -----------------------------------------------------------------

recipe::_write_manifest() {
	{
		printf '# generated by bs make from a recipe\n'
		printf 'name = %s\n'    "$name"
		printf 'version = %s\n' "$version"
		printf 'arch = %s\n'    "$arch"
		printf 'os = %s\n'      "$os"
		printf 'exec = %s\n'    "$exec"
		[[ -n "${pretty_name:-}" ]] && printf 'pretty_name = %s\n' "$pretty_name"
		[[ -n "${comment:-}" ]]     && printf 'comment = %s\n'     "$comment"
		[[ -n "${categories:-}" ]]  && printf 'categories = %s\n'  "$categories"
		[[ -n "${icon:-}" ]]        && printf 'icon = %s\n'        "$icon"
		[[ -n "${icon_size:-}" ]]   && printf 'icon_size = %s\n'   "$icon_size"
		[[ -n "${extra_exec:-}" ]]  && printf 'extra_exec = %s\n'  "$extra_exec"
		[[ -n "${mime_types:-}" ]]  && printf 'mime_types = %s\n'  "$mime_types"
		[[ -n "${bash_completion:-}" ]] && printf 'bash_completion = %s\n' "$bash_completion"
		printf 'terminal = %s\n'     "${terminal:-false}"
		printf 'bundle_libs = %s\n'  "${bundle_libs:-false}"
		printf 'isolate_home = %s\n' "${isolate_home:-false}"
		[[ -n "${min_glibc:-}" ]] && printf 'min_glibc = %s\n' "$min_glibc"
	} > "$1"
}

# Default layout when the recipe declares source_url instead of its own prepare().
recipe::_default_prepare() {
	if [[ -z "${source_url:-}" ]]; then
		if ((${#sources[@]})); then
			ui::error "a sources=() array needs its own prepare() (use bs_fetch_all there)"
		else
			ui::error "recipe defines neither prepare() nor source_url"
		fi
		return 1
	fi
	local dl="$srcdir/download"
	bs_fetch "$source_url" "$dl" "${source_sha256:-}" || return 1
	case "${source_type:-}" in
		appimage) bs_appimage_extract "$dl" "$pkgdir" ;;
		tar)      tar -xf "$dl" -C "$pkgdir" || { ui::error "tar extract failed"; return 1; } ;;
		zip)      bs_zip_extract "$dl" "$pkgdir" ;;
		deb)      bs_deb_extract "$dl" "$pkgdir" ;;
		file)     mkdir -p "$pkgdir/$(dirname -- "$exec")"; cp -- "$dl" "$pkgdir/$exec" ;;
		*)        ui::error "set source_type to appimage|tar|zip|deb|file (got '${source_type:-}')"; return 1 ;;
	esac
}

# recipe::run RECIPE [-o OUT]
# Thin wrapper: parse args, make a workspace, run the build, always clean up.
# (No RETURN trap — it would also fire when `source "$recipe"` finishes and wipe
# the workspace mid-build.)
recipe::run() {
	local recipe="" out=""
	while (($#)); do
		case "$1" in
			-o|--output) shift; out="${1:-}" ;;
			-*) ui::error "unknown make option: $1"; return 2 ;;
			*) if [[ -z "$recipe" ]]; then recipe="$1"; else ui::error "unexpected argument: $1"; return 2; fi ;;
		esac
		shift
	done
	[[ -n "$recipe" ]] || { ui::error "$(i18n::t err_make_usage)"; return 2; }
	[[ -f "$recipe" ]] || { ui::error "$(i18n::t err_not_found "$recipe")"; return 1; }

	local work rc=0
	work="$(mktemp -d)"
	recipe::_build "$work" "$recipe" "$out" || rc=$?
	rm -rf "$work"
	return "$rc"
}

# recipe::_build WORK RECIPE OUT
# Recipe fields are locals here so the sourced recipe (and its prepare()) see and
# set them via dynamic scope.
recipe::_build() {
	local work="$1" recipe="$2" out="$3"
	local name="" version="" arch="" os="" exec="" pretty_name="" comment=""
	local categories="" icon="" icon_size="" terminal="" bundle_libs="" isolate_home=""
	local extra_exec="" mime_types="" bash_completion=""
	local source_url="" source_sha256="" source_type="" min_glibc=""
	local -a sources=() sha256s=()
	local srcdir="$work/src" pkgdir="$work/pkg"
	mkdir -p "$srcdir" "$pkgdir"
	# Directory of the recipe, so a recipe can reference its own sources.
	# Exported so the sourced recipe (and any tool it runs) can read it.
	local RECIPE_DIR
	RECIPE_DIR="$(cd -- "$(dirname -- "$recipe")" && pwd)"
	export RECIPE_DIR

	# A recipe is the packager's own trusted build script (cf. PKGBUILD/formula).
	# shellcheck disable=SC1090
	source "$recipe"

	local v
	for v in name version arch os exec; do
		[[ -n "${!v}" ]] || { ui::error "recipe missing required field: $v"; return 1; }
	done

	if declare -F prepare >/dev/null 2>&1; then
		prepare || { ui::error "recipe prepare() failed"; return 1; }
		unset -f prepare
	else
		recipe::_default_prepare || return 1
	fi

	recipe::_write_manifest "$pkgdir/manifest"

	[[ -n "$out" ]] || out="$name-$version-$arch.bs"
	pack::build "$pkgdir" -o "$out"
}
