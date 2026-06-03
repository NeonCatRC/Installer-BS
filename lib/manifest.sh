# Manifest: parse the declarative package manifest as DATA — never source/eval it.
# Format and field reference: docs/dev/PACKAGE-FORMAT.md.
# TODO(WP2): implement parsing, validation and injection-safety.

# manifest::parse FILE
# Reads `key = value` lines into the associative array BS_MANIFEST.
# Lines starting with '#' and blank lines are ignored. Shell metacharacters in
# values must stay inert (no eval). Required: name, version, arch, os, exec.
manifest::parse() {
	# TODO(WP2): line-by-line parse into BS_MANIFEST; validate required keys.
	:
}
