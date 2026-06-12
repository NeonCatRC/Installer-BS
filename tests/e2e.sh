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
# The example packages declare linux/x86_64; let them run on any test host.
# The platform-guard test below re-enables the check explicitly.
export BS_NO_ARCH_CHECK=1

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

printf '== registry (bs list / info / uninstall by name) ==\n'
bash "$out" --install >/dev/null 2>&1
list_out="$(bsrun list 2>/dev/null)"
if contains "$list_out" "hello"; then ok "bs list shows the installed package"; else no "bs list shows the installed package"; fi
name_info="$(bsrun info hello 2>/dev/null)"
if contains "$name_info" "installed"; then ok "bs info <name> works without the .bs file"; else no "bs info <name> works without the .bs file"; fi
if bsrun -y uninstall hello >/dev/null 2>&1; then ok "bs uninstall <name> exits 0"; else no "bs uninstall <name> exits 0"; fi
want_gone "$appdir"   "registry uninstall: app dir removed"
want_gone "$launcher" "registry uninstall: launcher removed"
want_gone "$desktop"  "registry uninstall: .desktop removed"
if bsrun -y uninstall hello >/dev/null 2>&1; then no "uninstalling a missing name fails"; else ok "uninstalling a missing name fails"; fi

printf '== bs run ==\n'
run2_out="$(bsrun run "$out" 2>/dev/null)"
if contains "$run2_out" "Hello from a real"; then ok "bs run executes a package"; else no "bs run executes a package"; fi

printf '== self-check (--check) ==\n'
if bash "$out" --check >/dev/null 2>&1; then ok "--check passes on an intact package"; else no "--check passes on an intact package"; fi
total=$(wc -c < "$out")
head -c "$((total - 200))" "$out" > "$WORK/trunc.bs" 2>/dev/null
if bash "$WORK/trunc.bs" --check >/dev/null 2>&1; then no "--check rejects a truncated package"; else ok "--check rejects a truncated package"; fi

printf '== platform guard ==\n'
alien="$WORK/alien"; mkdir -p "$alien/bin"
printf '#!/usr/bin/env bash\necho alien\n' > "$alien/bin/a"; chmod +x "$alien/bin/a"
printf 'name = alien\nversion = 1\narch = fakearch\nos = linux\nexec = bin/a\n' > "$alien/manifest"
bsrun build "$alien" -o "$WORK/alien.bs" >/dev/null 2>&1
guard_rc=0
guard_out="$(BS_NO_ARCH_CHECK='' bash "$WORK/alien.bs" 2>&1)" || guard_rc=$?
if [[ "$guard_rc" -ne 0 ]] && contains "$guard_out" "built for"; then ok "wrong arch fails with a clear message"; else no "wrong arch fails with a clear message"; fi
if bash "$WORK/alien.bs" --info >/dev/null 2>&1; then ok "--info ignores the platform guard"; else no "--info ignores the platform guard"; fi

printf '== overwrite confirmation ==\n'
if bsrun build "$alien" -o "$WORK/alien.bs" </dev/null >/dev/null 2>&1; then
	no "overwrite without --yes and tty is refused"
else
	ok "overwrite without --yes and tty is refused"
fi
if bsrun -y build "$alien" -o "$WORK/alien.bs" >/dev/null 2>&1; then ok "overwrite with --yes proceeds"; else no "overwrite with --yes proceeds"; fi

printf '== stale cache invalidation (build_id) ==\n'
sc="$WORK/sc"; mkdir -p "$sc/bin"
printf '#!/usr/bin/env bash\necho VARIANT-A\n' > "$sc/bin/app"; chmod +x "$sc/bin/app"
printf 'name = scache\nversion = 9.9\narch = x86_64\nos = linux\nexec = bin/app\n' > "$sc/manifest"
bsrun -y build "$sc" -o "$WORK/sc.bs" >/dev/null 2>&1
sc_out="$(bash "$WORK/sc.bs" 2>/dev/null)"
printf '#!/usr/bin/env bash\necho VARIANT-B\n' > "$sc/bin/app"; chmod +x "$sc/bin/app"
bsrun -y build "$sc" -o "$WORK/sc.bs" >/dev/null 2>&1
sc_out2="$(bash "$WORK/sc.bs" 2>/dev/null)"
if contains "$sc_out" "VARIANT-A" && contains "$sc_out2" "VARIANT-B"; then
	ok "rebuilt same name-version re-extracts (no stale cache)"
else
	no "rebuilt same name-version re-extracts (no stale cache)"
fi

printf '== reproducible build ==\n'
if tar --version 2>/dev/null | grep -q GNU; then
	bsrun build "$ROOT/examples/hello" -o "$WORK/r1.bs" >/dev/null 2>&1
	bsrun build "$ROOT/examples/hello" -o "$WORK/r2.bs" >/dev/null 2>&1
	if cmp -s "$WORK/r1.bs" "$WORK/r2.bs"; then ok "two builds are byte-identical"; else no "two builds are byte-identical"; fi
else
	printf '  skip: non-GNU tar\n'
fi

printf '== desktop integration (icon/mime/man/completion) ==\n'
dx="$WORK/dx"; mkdir -p "$dx/bin" "$dx/share/man/man1" "$dx/share/completions"
printf '#!/usr/bin/env bash\necho dx ok\n' > "$dx/bin/dx"; chmod +x "$dx/bin/dx"
printf '<svg xmlns="http://www.w3.org/2000/svg"/>\n' > "$dx/share/dx.svg"
printf '.TH DX 1\n' > "$dx/share/man/man1/dx.1"
printf 'complete -W "go" dx\n' > "$dx/share/completions/dx.bash"
cat > "$dx/manifest" <<'MF'
name = dx
version = 1
arch = x86_64
os = linux
exec = bin/dx
icon = share/dx.svg
mime_types = text/x-dx;
bash_completion = share/completions/dx.bash
MF
bsrun build "$dx" -o "$WORK/dx.bs" >/dev/null 2>&1
bash "$WORK/dx.bs" --install >/dev/null 2>&1
dxdesk="$XDG_DATA_HOME/applications/dx.desktop"
want_file "$XDG_DATA_HOME/icons/hicolor/scalable/apps/dx.svg" "icon lands in the hicolor theme"
file_has  "Icon=dx" "$dxdesk" "desktop uses the themed icon name"
file_has  "MimeType=text/x-dx;" "$dxdesk" "desktop carries MimeType"
want_file "$XDG_DATA_HOME/man/man1/dx.1" "man page linked into the user man path"
want_file "$XDG_DATA_HOME/bash-completion/completions/dx" "bash completion installed"
bash "$WORK/dx.bs" --uninstall >/dev/null 2>&1
want_gone "$XDG_DATA_HOME/icons/hicolor/scalable/apps/dx.svg" "uninstall removes the themed icon"
want_gone "$XDG_DATA_HOME/man/man1/dx.1" "uninstall removes the man link"
want_gone "$XDG_DATA_HOME/bash-completion/completions/dx" "uninstall removes the completion"

printf '== extra_exec + clean upgrade ==\n'
up="$WORK/up"; mkdir -p "$up/bin"
printf '#!/usr/bin/env bash\necho upapp v1\n' > "$up/bin/upapp"; chmod +x "$up/bin/upapp"
printf '#!/usr/bin/env bash\necho xtool here\n' > "$up/bin/xtool"; chmod +x "$up/bin/xtool"
printf 'name = upapp\nversion = 1\narch = x86_64\nos = linux\nexec = bin/upapp\nextra_exec = bin/xtool\n' > "$up/manifest"
bsrun build "$up" -o "$WORK/up1.bs" >/dev/null 2>&1
bash "$WORK/up1.bs" --install >/dev/null 2>&1
want_file "$HOME/.local/bin/xtool" "extra_exec gets its own launcher"
xt_out="$(bash "$HOME/.local/bin/xtool" 2>/dev/null)"
if contains "$xt_out" "xtool here"; then ok "extra launcher runs the extra exec"; else no "extra launcher runs the extra exec"; fi
# v2 drops the extra tool; --install over v1 must not leave its launcher behind.
rm -f "$up/bin/xtool"
printf 'name = upapp\nversion = 2\narch = x86_64\nos = linux\nexec = bin/upapp\n' > "$up/manifest"
bsrun build "$up" -o "$WORK/up2.bs" >/dev/null 2>&1
bash "$WORK/up2.bs" --install >/dev/null 2>&1
want_gone "$HOME/.local/bin/xtool" "upgrade removes the dropped extra launcher"
file_has "version = 2" "$XDG_DATA_HOME/installer-bs/upapp/manifest" "upgrade replaced the payload"
bash "$WORK/up2.bs" --uninstall >/dev/null 2>&1

printf '== recipe build (deb) ==\n'
if command -v ar >/dev/null 2>&1; then
	debroot="$WORK/debroot"; mkdir -p "$debroot/usr/bin"
	printf '#!/usr/bin/env bash\necho debby ok\n' > "$debroot/usr/bin/debby"; chmod +x "$debroot/usr/bin/debby"
	( cd "$debroot" && tar -czf "$WORK/data.tar.gz" . )
	printf '2.0\n' > "$WORK/debian-binary"
	tar -czf "$WORK/control.tar.gz" --files-from /dev/null
	( cd "$WORK" && ar rc fake.deb debian-binary control.tar.gz data.tar.gz )
	debsum="$(sha256sum "$WORK/fake.deb" | cut -d' ' -f1)"
	cat > "$WORK/recipe_deb" <<RECIPE
name=debby
version=1.0
arch=x86_64
os=linux
exec=usr/bin/debby
source_type=deb
source_url=$WORK/fake.deb
source_sha256=$debsum
RECIPE
	if bsrun make "$WORK/recipe_deb" -o "$WORK/debby.bs" >/dev/null 2>&1; then ok "recipe build (deb) exits 0"; else no "recipe build (deb) exits 0"; fi
	deb_out="$(bash "$WORK/debby.bs" 2>/dev/null)"
	if contains "$deb_out" "debby ok"; then ok "deb-sourced package runs"; else no "deb-sourced package runs"; fi
else
	printf '  skip: no ar (binutils)\n'
fi

printf '== cache command ==\n'
cache_list="$(bsrun cache 2>/dev/null)"
if contains "$cache_list" "installer-bs"; then ok "bs cache lists extraction dirs"; else no "bs cache lists extraction dirs"; fi
if bsrun -y cache clean scache >/dev/null 2>&1; then ok "bs cache clean <name> exits 0"; else no "bs cache clean <name> exits 0"; fi
want_gone "$XDG_CACHE_HOME/installer-bs/scache-9.9" "named cache dir removed"
want_file "$XDG_CACHE_HOME/installer-bs/hello-1.0.0" "other cache dirs survive a named clean"
bsrun -y cache clean >/dev/null 2>&1
want_gone "$XDG_CACHE_HOME/installer-bs/hello-1.0.0" "full clean removes the rest"

printf '== injection regression ==\n'
evil="$WORK/evil"; mkdir -p "$evil/bin"
printf '#!/usr/bin/env bash\necho hi\n' > "$evil/bin/x"; chmod +x "$evil/bin/x"
# A malicious comment value: must be stored/printed as data, never executed.
# shellcheck disable=SC2016  # the $(...) must stay literal in the manifest
printf 'name = evil\nversion = 1\narch = x86_64\nos = linux\nexec = bin/x\ncomment = $(touch %s/PWNED)\n' "$WORK" > "$evil/manifest"
bsrun build "$evil" -o "$WORK/evil.bs" >/dev/null 2>&1
bash "$WORK/evil.bs" --info >/dev/null 2>&1
want_gone "$WORK/PWNED" "manifest value is data, not executed"

printf '== recipe build (tar) ==\n'
app="$WORK/app"; mkdir -p "$app/bin"
printf '#!/usr/bin/env bash\necho recipe app ok\n' > "$app/bin/demo"; chmod +x "$app/bin/demo"
( cd "$app" && tar -czf "$WORK/demo.tgz" -- * )
sum="$(sha256sum "$WORK/demo.tgz" | cut -d' ' -f1)"
cat > "$WORK/recipe" <<RECIPE
name=demo
version=2.0
arch=x86_64
os=linux
exec=bin/demo
source_type=tar
source_url=$WORK/demo.tgz
source_sha256=$sum
RECIPE
if bsrun make "$WORK/recipe" -o "$WORK/demo.bs" >/dev/null 2>&1; then ok "recipe build (tar) exits 0"; else no "recipe build (tar) exits 0"; fi
want_file "$WORK/demo.bs" "recipe produced package"
rout="$(bash "$WORK/demo.bs" 2>/dev/null)"
if contains "$rout" "recipe app ok"; then ok "recipe package runs"; else no "recipe package runs"; fi
# A wrong checksum must abort the build.
sed 's/^source_sha256=.*/source_sha256=deadbeef/' "$WORK/recipe" > "$WORK/recipe_bad"
if bsrun make "$WORK/recipe_bad" -o "$WORK/bad.bs" >/dev/null 2>&1; then no "recipe rejects bad sha256"; else ok "recipe rejects bad sha256"; fi

printf '== bundling (compiled binary + custom .so) ==\n'
if [[ "$(uname -s)" == Linux ]] && { command -v cc >/dev/null 2>&1 || command -v gcc >/dev/null 2>&1; }; then
	if bsrun make "$ROOT/examples/greeter/recipe" -o "$WORK/greeter.bs" >/dev/null 2>&1; then ok "greeter recipe builds (ldd bundling)"; else no "greeter recipe builds (ldd bundling)"; fi
	# The custom library now exists ONLY inside the package; running it proves the
	# bundle is found via the runtime's LD_LIBRARY_PATH.
	gout="$(bash "$WORK/greeter.bs" 2>/dev/null)"
	if contains "$gout" "greetings from a bundled shared library"; then ok "bundled .so resolved at runtime"; else no "bundled .so resolved at runtime"; fi
	bash "$WORK/greeter.bs" --extract "$WORK/gx" >/dev/null 2>&1
	want_file "$WORK/gx/lib/libgreet.so" "package carries the bundled libgreet.so"
else
	printf '  skip: no C compiler\n'
fi

printf '== sign / verify ==\n'
if command -v gpg >/dev/null 2>&1; then
	export GNUPGHOME="$WORK/gnupg"; mkdir -p "$GNUPGHOME"; chmod 700 "$GNUPGHOME"
	cat > "$WORK/keyparams" <<'KEY'
%no-protection
Key-Type: eddsa
Key-Curve: ed25519
Name-Real: BS Test
Name-Email: test@bs.local
Expire-Date: 0
%commit
KEY
	if gpg --batch --gen-key "$WORK/keyparams" >/dev/null 2>&1; then
		if bsrun sign "$out" >/dev/null 2>&1; then ok "sign creates a signature"; else no "sign creates a signature"; fi
		want_file "$out.sig" "signature file produced"
		if bsrun verify "$out" >/dev/null 2>&1; then ok "verify accepts a good signature"; else no "verify accepts a good signature"; fi
		cp "$out" "$WORK/tampered.bs"; printf 'x' >> "$WORK/tampered.bs"; cp "$out.sig" "$WORK/tampered.bs.sig"
		if bsrun verify "$WORK/tampered.bs" >/dev/null 2>&1; then no "verify rejects a tampered package"; else ok "verify rejects a tampered package"; fi
	else
		printf '  skip: gpg key generation failed\n'
	fi
else
	printf '  skip: gpg not installed\n'
fi

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[[ "$fail" -eq 0 ]]
