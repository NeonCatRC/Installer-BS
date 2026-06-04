# shellcheck shell=bash
# Pack: `bs build <src-dir>` turns a prepared directory + manifest into one
# self-extracting .bs file (template/stub.sh + tar payload). It never mutates the
# source, cleans its temps via trap, and writes an optional sha256 sidecar.

pack::_usage() { printf '%s\n' "Usage: bs build <src-dir> [-o out.bs] [--gzip]"; }

# Human-readable byte size.
pack::_human() {
	local b="$1"
	if   ((b < 1024));    then printf '%d B' "$b"
	elif ((b < 1048576)); then printf '%d KiB' "$((b / 1024))"
	else                       printf '%d MiB' "$((b / 1048576))"
	fi
}

pack::build() {
	local src="" out="" comp="auto"
	while (($#)); do
		case "$1" in
			-o|--output) shift; out="${1:-}" ;;
			--gzip)      comp="gzip" ;;
			-h|--help)   pack::_usage; return 0 ;;
			-*)          ui::error "unknown build option: $1"; return 2 ;;
			*)           if [[ -z "$src" ]]; then src="$1"; else ui::error "unexpected argument: $1"; return 2; fi ;;
		esac
		shift
	done

	[[ -n "$src" ]] || { ui::error "$(i18n::t err_build_usage)"; return 2; }
	[[ -d "$src" ]] || { ui::error "$(i18n::t err_not_found "$src")"; return 1; }

	manifest::parse "$src/manifest" || return 1
	manifest::validate              || return 1

	local name="${BS_MANIFEST[name]}" version="${BS_MANIFEST[version]}" arch="${BS_MANIFEST[arch]}"
	local exec_rel="${BS_MANIFEST[exec]}"
	[[ -e "$src/$exec_rel" ]] || { ui::error "exec not found in source: $exec_rel"; return 1; }

	# Library bundling resolves deps with the host loader, so it needs a native host.
	if [[ "${BS_MANIFEST[bundle_libs]:-false}" == true ]]; then
		core::detect_platform
		[[ "$arch" == "$BS_ARCH" ]] || {
			ui::error "bundle_libs needs a native build host (manifest arch=$arch, host=$BS_ARCH)"
			return 1
		}
	fi

	[[ -n "$out" ]] || out="$name-$version-$arch.bs"
	local outdir; outdir="$(dirname -- "$out")"
	[[ -d "$outdir" ]] || { ui::error "output directory does not exist: $outdir"; return 1; }
	[[ -e "$out" ]] && ui::warn "overwriting $out"

	local stage payload
	stage="$(mktemp -d)"; payload="$(mktemp)"
	# shellcheck disable=SC2064  # expand the temp paths now; clean up on any exit
	trap "rm -rf '$stage' '$payload'" EXIT

	# Copy the source without touching it, excluding build artifacts. The pipe
	# preserves permissions and symlinks.
	( cd "$src" && tar -cf - --exclude='*.bs' --exclude='*.bs.sha256' --exclude='.git' . ) \
		| ( cd "$stage" && tar -xf - )

	chmod +x "$stage/$exec_rel" 2>/dev/null || ui::warn "could not set +x on $exec_rel"

	if [[ -n "${BS_MANIFEST[icon]:-}" && ! -e "$src/${BS_MANIFEST[icon]}" ]]; then
		ui::warn "icon declared but missing: ${BS_MANIFEST[icon]}"
	fi

	if [[ "${BS_MANIFEST[bundle_libs]:-false}" == true ]]; then
		bundle::collect "$stage/$exec_rel" "$stage/lib"
	fi

	# Compress with xz; fall back to gzip when xz is unavailable or forced.
	local taropt="J"
	if [[ "$comp" == gzip ]] || ! command -v xz >/dev/null 2>&1; then
		[[ "$comp" != gzip ]] && ui::warn "xz not found; using gzip"
		taropt="z"
	fi
	# Members at the archive root (no ./ prefix), so the runtime reads them by name.
	( cd "$stage" && tar -c"$taropt"f "$payload" -- * )

	cat "$BS_ROOT/template/stub.sh" "$payload" > "$out"
	chmod +x "$out"

	# Honest integrity sidecar: detects a corrupted copy, not a security signature.
	if command -v sha256sum >/dev/null 2>&1; then
		( cd "$outdir" && sha256sum "$(basename -- "$out")" > "$(basename -- "$out").sha256" )
	fi

	ui::ok   "$(i18n::t build_done "$out")"
	ui::info "$(i18n::t build_size "$(pack::_human "$(wc -c < "$out")")")"
}
