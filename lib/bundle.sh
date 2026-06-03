# Bundle: collect an executable's non-system shared libraries (AppImage-style)
# so a package can run on hosts that lack them. Base libc/loader are excluded.
# TODO(WP3): implement collection via ldd + exclude-list.

# bundle::collect EXEC DEST_LIB_DIR
# Copies dependent .so files of EXEC into DEST_LIB_DIR, skipping the exclude-list
# (ld-linux*, libc, libm, libpthread, libdl, librt; libstdc++ optional).
bundle::collect() {
	# TODO(WP3): ldd parse, filter by exclude-list, copy, report kept/skipped.
	:
}
