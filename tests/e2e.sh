#!/usr/bin/env bash
# End-to-end lifecycle test: build examples/hello, run it portably, --install into
# an isolated XDG prefix, run the launcher, --uninstall, verify cleanup, plus an
# injection regression. Runs entirely in temp dirs; needs no root; writes nothing
# to the real system. Exit 0 only if every check passes.
#
# No `set -e`: we want to run all checks and report. No pipes in conditions
# (captured output is matched with `case`) to dodge grep -q + pipefail + SIGPIPE.
set -u

ROOT="$(cd -- "$(dirname -- "$(readlink -f -- "$0")")/.." && pwd)"
BS="$ROOT/bs"

pass=0; fail=0
ok() { printf '  ok   %s\n' "$1"; pass=$((pass + 1)); }
no() { printf '  FAIL %s\n' "$1"; fail=$((fail + 1)); }
want_file() { if [[ -e "$1" ]]; then ok "$2"; else no "$2"; fi; }
want_gone() { if [[ ! -e "$1" ]]; then ok "$2"; else no "$2"; fi; }
file_has()  { if grep -q -- "$1" "$2" 2>/dev/null; then ok "$3"; else no "$3"; fi; }
file_lacks(){ if grep -q -- "$1" "$2" 2>/dev/null; then no "$3"; else ok "$3"; fi; }
contains()  { case "$1" in *"$2"*) return 0 ;; *) return 1 ;; esac; }

bsrun() { LANG=C NO_COLOR=1 bash "$BS" "$@"; }

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# Isolate HOME/XDG so install and run touch only the temp tree.
export HOME="$WORK/home"
export XDG_CACHE_HOME="$HOME/.cache" XDG_DATA_HOME="$HOME/.local/share"
export XDG_CONFIG_HOME="$HOME/.config" XDG_STATE_HOME="$HOME/.local/state"
mkdir -p "$HOME"

out="$WORK/hello.bs"

printf '== build ==\n'
if bsrun build "$ROOT/examples/hello" -o "$out" >/dev/null 2>&1; then ok "build exits 0"; else no "build exits 0"; fi
want_file "$out" "package file produced"
if command -v sha256sum >/dev/null 2>&1; then
	if ( cd "$WORK" && sha256sum -c "$(basename "$out").sha256" ) >/dev/null 2>&1; then
		ok "sha256 sidecar verifies"
	else
		no "sha256 sidecar verifies"
	fi
fi

printf '== metadata ==\n'
info_out="$(bsrun info "$out" 2>/dev/null)"
if contains "$info_out" "hello 1.0.0"; then ok "bs info shows name/version"; else no "bs info shows name/version"; fi

printf '== portable run ==\n'
run_out="$(bash "$out" 2>/dev/null)"
if contains "$run_out" "Hello from a real"; then ok "portable run prints app output"; else no "portable run prints app output"; fi
if bash "$out" >/dev/null 2>&1; then ok "second run (cache) exits 0"; else no "second run (cache) exits 0"; fi
want_file "$XDG_CACHE_HOME/installer-bs/hello-1.0.0/.bs-ok" "run cache populated once"

printf '== extract ==\n'
bash "$out" --extract "$WORK/unpacked" >/dev/null 2>&1
want_file "$WORK/unpacked/manifest" "extract: manifest present"
want_file "$WORK/unpacked/bin/hello" "extract: exec present"

printf '== install (user) ==\n'
launcher="$HOME/.local/bin/hello"
desktop="$XDG_DATA_HOME/applications/hello.desktop"
appdir="$XDG_DATA_HOME/installer-bs/hello"
bash "$out" --install >/dev/null 2>&1
want_file "$launcher" "install: launcher created in ~/.local/bin"
want_file "$desktop"  "install: .desktop created in XDG applications"
want_file "$appdir/.bs-files" "install: uninstall list written"
launch_out="$(bash "$launcher" 2>/dev/null)"
if contains "$launch_out" "Hello from a real"; then ok "install: launcher runs the app"; else no "install: launcher runs the app"; fi
file_has  "Terminal=true" "$desktop" "install: .desktop carries manifest Terminal"
file_lacks "/portsoft"    "$desktop" "install: no /portsoft anywhere"

printf '== uninstall ==\n'
bash "$out" --uninstall >/dev/null 2>&1
want_gone "$appdir"   "uninstall: app dir removed"
want_gone "$launcher" "uninstall: launcher removed"
want_gone "$desktop"  "uninstall: .desktop removed"

printf '== injection regression ==\n'
evil="$WORK/evil"; mkdir -p "$evil/bin"
printf '#!/usr/bin/env bash\necho hi\n' > "$evil/bin/x"; chmod +x "$evil/bin/x"
# A malicious comment value: must be stored/printed as data, never executed.
# shellcheck disable=SC2016  # the $(...) must stay literal in the manifest
printf 'name = evil\nversion = 1\narch = x86_64\nos = linux\nexec = bin/x\ncomment = $(touch %s/PWNED)\n' "$WORK" > "$evil/manifest"
bsrun build "$evil" -o "$WORK/evil.bs" >/dev/null 2>&1
bash "$WORK/evil.bs" --info >/dev/null 2>&1
want_gone "$WORK/PWNED" "manifest value is data, not executed"

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[[ "$fail" -eq 0 ]]
