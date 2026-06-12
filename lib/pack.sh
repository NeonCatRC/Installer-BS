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

# Content hash of a staged tree: sha256 over every file's hash + path, sorted.
# Used as the package's build_id — the runtime keys its extraction cache on it,
# so a rebuilt package with the same name-version never runs from a stale cache.
pack::_tree_id() {
	local dir="$1"
	( cd "$dir" && find . -type f -print0 | LC_ALL=C sort -z | xargs -0 -r sha256sum -- ) \
		| sha256sum | cut -d' ' -f1
}

# Print the highest GLIBC_x.y symbol version required across a tree's ELF binaries
# (= the minimum glibc to run it). Needs objdump or readelf; empty if neither is
# present or nothing links glibc.
pack::_detect_glibc() {
	local dir="$1" f v max=""
	local -a dump
	if   command -v objdump >/dev/null 2>&1; then dump=(objdump -T)
	elif command -v readelf >/dev/null 2>&1; then dump=(readelf -W --dyn-syms)
	else return 0; fi
	while IFS= read -r f; do
		[[ "$(head -c4 "$f" 2>/dev/null | od -An -tx1 | tr -d ' \n')" == 7f454c46 ]] || continue
		v="$("${dump[@]}" "$f" 2>/dev/null | grep -oE 'GLIBC_[0-9]+\.[0-9]+(\.[0-9]+)?' | sed 's/GLIBC_//' | sort -V | tail -1)"
		[[ -n "$v" ]] || continue
		if [[ -z "$max" ]]; then max="$v"; else max="$(printf '%s\n%s\n' "$max" "$v" | sort -V | tail -1)"; fi
	done < <(find "$dir" -type f \( -path '*/bin/*' -o -path '*/lib/*' -o -name '*.so' -o -name '*.so.*' \) 2>/dev/null)
	printf '%s' "$max"
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
	# A recipe is built with `bs make`, not `bs build` — redirect instead of a
	# confusing "manifest not found".
	if [[ -f "$src" && "${src##*/}" == recipe ]] || { [[ -d "$src" ]] && [[ ! -f "$src/manifest" && -f "$src/recipe" ]]; }; then
		local hint="$src"; [[ -d "$src" ]] && hint="$src/recipe"
		ui::error "$(i18n::t err_is_recipe "$hint")"; return 2
	fi
	[[ -d "$src" ]] || { ui::error "$(i18n::t err_not_found "$src")"; return 1; }

	manifest::parse "$src/manifest" || return 1
	manifest::validate              || return 1

	local name="${BS_MANIFEST[name]}" version="${BS_MANIFEST[version]}" arch="${BS_MANIFEST[arch]}"
	local exec_rel="${BS_MANIFEST[exec]}"
	[[ -e "$src/$exec_rel" ]] || { ui::error "exec not found in source: $exec_rel"; return 1; }

	# extra_exec: space-separated extra executables. Each must exist; their
	# basenames become launcher names at install time, so they must be unique
	# and must not collide with the package name (= the main launcher).
	local -a extras=()
	if [[ -n "${BS_MANIFEST[extra_exec]:-}" ]]; then
		read -r -a extras <<< "${BS_MANIFEST[extra_exec]}"
		local x seen=" $name "
		for x in "${extras[@]}"; do
			[[ -e "$src/$x" ]] || { ui::error "extra_exec not found in source: $x"; return 1; }
			local base="${x##*/}"
			if [[ "$seen" == *" $base "* ]]; then
				ui::error "extra_exec launcher name collides: $base"; return 1
			fi
			seen+="$base "
		done
	fi

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
	if [[ -e "$out" ]]; then
		ui::confirm "$(i18n::t build_overwrite "$out")" || { ui::info "$(i18n::t build_cancelled)"; return 1; }
	fi

	local stage payload
	stage="$(mktemp -d)"; payload="$(mktemp)"
	# shellcheck disable=SC2064  # expand the temp paths now; clean up on any exit
	trap "rm -rf '$stage' '$payload'" EXIT

	# Copy the source without touching it, excluding build artifacts. The pipe
	# preserves permissions and symlinks.
	( cd "$src" && tar -cf - --exclude='*.bs' --exclude='*.bs.sha256' --exclude='.git' . ) \
		| ( cd "$stage" && tar -xf - )

	chmod +x "$stage/$exec_rel" 2>/dev/null || ui::warn "could not set +x on $exec_rel"
	local x
	for x in "${extras[@]}"; do
		chmod +x "$stage/$x" 2>/dev/null || ui::warn "could not set +x on $x"
	done

	if [[ -n "${BS_MANIFEST[icon]:-}" && ! -e "$src/${BS_MANIFEST[icon]}" ]]; then
		ui::warn "icon declared but missing: ${BS_MANIFEST[icon]}"
	fi

	if [[ "${BS_MANIFEST[bundle_libs]:-false}" == true ]]; then
		bundle::collect "$stage/$exec_rel" "$stage/lib"
		for x in "${extras[@]}"; do
			bundle::collect "$stage/$x" "$stage/lib"
		done
	fi

	# Record the minimum glibc (max GLIBC_x.y symbol across the payload's ELF
	# binaries) unless declared, so the runtime can warn clearly on too-old hosts.
	if [[ -z "${BS_MANIFEST[min_glibc]:-}" ]]; then
		local g; g="$(pack::_detect_glibc "$stage")"
		if [[ -n "$g" ]]; then
			printf 'min_glibc = %s\n' "$g" >> "$stage/manifest"
			ui::info "detected min glibc: $g"
		fi
	fi

	# Content hash of the staged tree -> build_id in the manifest. The runtime
	# keys its cache on it, so rebuilding with the same name-version invalidates
	# stale extractions. Computed last: it must cover the final payload content.
	printf 'build_id = %s\n' "$(pack::_tree_id "$stage")" >> "$stage/manifest"

	# Compress with xz; fall back to gzip when xz is unavailable or forced.
	local taropt="J"
	if [[ "$comp" == gzip ]] || ! command -v xz >/dev/null 2>&1; then
		[[ "$comp" != gzip ]] && ui::warn "xz not found; using gzip"
		taropt="z"
	fi
	# Reproducible archive on GNU tar: fixed member order, owner and mtime, so the
	# same input tree yields a bit-identical .bs (override the epoch with
	# SOURCE_DATE_EPOCH). The original couldn't even produce the same MD5 twice.
	local -a tarflags=()
	if tar --version 2>/dev/null | grep -q GNU; then
		tarflags=(--sort=name --owner=0 --group=0 --numeric-owner
		          --mtime="@${SOURCE_DATE_EPOCH:-0}")
	else
		ui::warn "non-GNU tar: build will work but won't be byte-reproducible"
	fi
	# Members at the archive root (no ./ prefix), so the runtime reads them by name.
	( cd "$stage" && tar "${tarflags[@]}" -c"$taropt"f "$payload" -- * )

	cat "$BS_ROOT/template/stub.sh" "$payload" > "$out"
	chmod +x "$out"

	# Honest integrity sidecar: detects a corrupted copy, not a security signature.
	if command -v sha256sum >/dev/null 2>&1; then
		( cd "$outdir" && sha256sum "$(basename -- "$out")" > "$(basename -- "$out").sha256" )
	fi

	ui::ok   "$(i18n::t build_done "$out")"
	ui::info "$(i18n::t build_size "$(pack::_human "$(wc -c < "$out")")")"
}
