#!/usr/bin/env bash
# End-to-end lifecycle test: build examples/hello, run it portably, --install into
# a temporary XDG prefix, verify launcher + .desktop, --uninstall, verify cleanup.
# Runs entirely in temp dirs; never touches the real system; needs no root.
# TODO(WP4): implement once bs build (WP3) and the stub runtime (WP2) exist.
set -euo pipefail

echo "e2e not implemented yet (WP4)." >&2
exit 1
