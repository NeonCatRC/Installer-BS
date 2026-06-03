#!/usr/bin/env bash
# Run shellcheck across the project's shell sources. TODO(WP6): add bats + CI.
set -euo pipefail

root="$(cd -- "$(dirname -- "$(readlink -f -- "$0")")/.." && pwd)"

if ! command -v shellcheck >/dev/null 2>&1; then
	echo "shellcheck not found — install it to lint." >&2
	exit 127
fi

# Our shell sources: bs entry + *.sh modules. Exclude the legacy reference dump.
mapfile -d '' -t files < <(
	find "$root" \
		-path "$root/docs/legacy" -prune -o \
		-type f \( -name '*.sh' -o -name 'bs' \) -print0
)

shellcheck -x -- "${files[@]}"
echo "lint ok"
