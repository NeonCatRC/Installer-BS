#!/usr/bin/env bash
# Installer-BS package runtime (stub).
# This script is prepended to a tar.xz payload to form a self-extracting .bs
# package. At build time `bs build` appends the marker line and the payload.
# Spec: docs/dev/PACKAGE-FORMAT.md.
# TODO(WP2): implement run / --install / --uninstall / --extract / --info / --help.
set -euo pipefail

# The payload begins on the line AFTER this marker (filled/located at runtime):
#   __BS_PAYLOAD__
# Locate it with:  offset=$(grep -an '^__BS_PAYLOAD__$' "$0" | head -1 | cut -d: -f1)
# Extract with:    tail -n +$((offset+1)) "$0" | xz -dc | tar -x -C "$dest"

# TODO(WP2): read embedded manifest from the header, dispatch on "$@",
# install strictly into XDG / /opt / /usr-local, track installed files for
# clean --uninstall, set LD_LIBRARY_PATH for bundled libs.
echo "Installer-BS package stub — runtime not implemented yet (WP2)." >&2
exit 1
