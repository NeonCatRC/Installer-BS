#!/usr/bin/env bash
# Run shellcheck across the project's shell sources.
# Override the binary with SHELLCHECK=/path/to/shellcheck (handy on machines
# where it isn't on PATH). Sourced fragments carry `# shellcheck shell=bash`;
# the entrypoint is linted with -x so cross-file globals resolve.
set -uo pipefail

root="$(cd -- "$(dirname -- "$(readlink -f -- "$0")")/.." && pwd)"
sc="${SHELLCHECK:-shellcheck}"

if ! command -v "$sc" >/dev/null 2>&1; then
	echo "shellcheck not found (set SHELLCHECK=/path/to/shellcheck)" >&2
	exit 127
fi

files=(
	bs
	lib/core.sh lib/ui.sh lib/i18n.sh lib/manifest.sh lib/pack.sh lib/bundle.sh
	lib/sign.sh lib/recipe.sh lib/installed.sh lib/platform/linux.sh
	locales/en.sh locales/ru.sh
	template/stub.sh
	tests/lint.sh tests/e2e.sh
	examples/hello/bin/hello
)

rc=0
for f in "${files[@]}"; do
	"$sc" -x -- "$root/$f" || rc=1
done

((rc == 0)) && echo "lint ok"
exit "$rc"
