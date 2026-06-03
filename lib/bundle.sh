# Bundle: collect an executable's non-system shared libraries (AppImage-style),
# so a package can run on hosts that lack them. The base loader/libc set is
# excluded, as linuxdeploy/AppImage do.
#
# Caution: `ldd` may execute the target in some configurations. Only run it on
# binaries you trust — here, the packager's own. Bundling requires a native host.

# bundle::_is_elf FILE  -> true if FILE starts with the ELF magic
bundle::_is_elf() {
	local magic
	magic="$(head -c4 "$1" 2>/dev/null | od -An -tx1 | tr -d ' \n')"
	[[ "$magic" == 7f454c46 ]]
}

# bundle::collect EXEC DEST_LIB_DIR
# Copies dependent .so files of EXEC into DEST_LIB_DIR, skipping the base set.
bundle::collect() {
	local exec="$1" dest="$2"
	command -v ldd >/dev/null 2>&1 || { ui::warn "ldd not found; skipping lib bundling"; return 0; }
	bundle::_is_elf "$exec"        || { ui::warn "exec is not an ELF binary; nothing to bundle"; return 0; }

	# Never bundle the loader/libc; libstdc++/libgcc_s are treated as system by default.
	local exclude='^(ld-linux.*|libc|libm|libmvec|libpthread|libdl|librt|libstdc\+\+|libgcc_s)\.so'

	local line soname path copied=0 skipped=0 made=0
	while IFS= read -r line; do
		[[ "$line" == *"=>"* ]] || continue                 # skip vdso / loader lines
		soname="$(manifest::_trim "${line%%=>*}")"
		path="${line#*=>}"; path="$(manifest::_trim "${path%%(*}")"
		if [[ -z "$path" || "$path" == *"not found"* ]]; then
			ui::warn "unresolved dependency: $soname"; continue
		fi
		[[ -e "$path" ]] || continue
		[[ "$soname" =~ $exclude ]] && { skipped=$((skipped + 1)); continue; }
		if ((made == 0)); then mkdir -p "$dest"; made=1; fi
		cp -L -- "$path" "$dest/$soname"
		copied=$((copied + 1))
	done < <(ldd "$exec" 2>/dev/null || true)

	ui::info "bundled $copied lib(s), skipped $skipped base/system lib(s)"
}
