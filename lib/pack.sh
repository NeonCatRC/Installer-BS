# Pack: `bs build <src-dir>` turns a prepared directory + manifest into one
# self-extracting .bs file (template/stub.sh + marker + tar.xz payload).
# TODO(WP3): implement build; optional sha256 sidecar; idempotent temp via mktemp+trap.

# pack::build SRC_DIR [-o OUT]
pack::build() {
	# TODO(WP3): validate manifest, optional bundle::collect, tar -cJf payload,
	# concat stub + marker + payload, chmod +x, optional sha256sum sidecar.
	:
}
