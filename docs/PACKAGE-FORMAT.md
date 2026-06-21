# Installer-BS package format `.bs` — specification (format 1)

A `.bs` package is a self-extracting Bash script with a compressed tar payload
appended to it. It runs with only coreutils + tar + xz/gzip. No FUSE, no daemon,
no committed third-party binaries.

---

## 1. File layout

```
#!/usr/bin/env bash
<runtime stub: template/stub.sh>      # run / --install / --uninstall / --extract / --info / --help
exit $?
__BS_PAYLOAD__                        # marker: the ONLY whole line equal to this
<compressed tar stream to end of file>
```

- The payload begins on the line **after** the marker. The stub locates it with
  `grep -m1 -an '^__BS_PAYLOAD__$' "$0"` (stops at the marker; never scans the
  binary tail) and streams from there with `tail -n +N`. The offset and the
  payload's magic bytes are computed once per invocation and cached.
- `bs build` forms a package as `cat stub.sh <marker is the stub's last line> payload > out.bs`.
- The stub `exit`s before the marker, so the binary payload is never parsed as code.
- Default file name: `<name>-<version>-<arch>.bs`.

### Reproducibility

On GNU tar, `bs build` fixes the member order (`--sort=name`), owner (0:0) and
mtimes (`SOURCE_DATE_EPOCH`, default 0), so the same input tree produces a
**byte-identical** `.bs`. Combined with `build_id` (below) this also means an
unchanged rebuild keeps its extraction cache warm.

### Compression

The payload is a tar compressed with **xz** (default) or **gzip** (fallback when
`xz` is absent at build time, or forced with `bs build --gzip`). The runtime does
not rely on tar autodetecting compression from a pipe (not portable); it reads the
payload's magic bytes (`fd 37 7a 58 5a 00` = xz, `1f 8b` = gzip) and decompresses
explicitly, then pipes to plain `tar`.

The chosen decompressor must exist on the target. `xz` is a base package on every
mainstream desktop/server Linux; only ultra-minimal images omit it — for those,
build with `--gzip` (universal, at the cost of a larger file). If the needed tool
is missing, the runtime says so explicitly instead of failing obscurely.

### Payload contents

Created from the package source directory, members at the archive root:

```
manifest          # canonical manifest (source of truth)
bin/<exec>        # main executable and friends
lib/              # bundled .so files (only if bundle_libs = true)
share/            # icons, assets
...               # any application files
```

`--info` reads only the `manifest` member (`tar -xO manifest`) without unpacking
the rest.

---

## 2. Manifest

Declarative `key = value` text. Parsed as **data**, never `source`d or `eval`d:
shell metacharacters in values stay inert (verified by the injection test in
`tests/`). The builder uses `lib/manifest.sh`; the runtime carries a small
equivalent parser so a package is self-contained.

Parsing rules:
- UTF-8, LF line endings (CRLF tolerated on read).
- Blank lines and lines whose first non-space character is `#` are ignored.
- `key = value`, split on the first `=`; key and value are whitespace-trimmed.
- Value is taken verbatim to end of line. Unknown keys: warn, don't fail.

### Required fields

| key       | example     | meaning                                  |
|-----------|-------------|------------------------------------------|
| `name`    | `hello`     | package id, `^[a-z0-9][a-z0-9._-]*$`     |
| `version` | `1.0.0`     | application version                      |
| `arch`    | `x86_64`    | target architecture (`uname -m` style); `any` = arch-independent payload (pure scripts, no ELF) |
| `os`      | `linux`     | target OS (`linux`; `freebsd` reserved) |
| `exec`    | `bin/hello` | main executable path inside the payload |

### Optional fields

| key            | default   | meaning                                            |
|----------------|-----------|----------------------------------------------------|
| `format`       | `1`       | package format version                             |
| `pretty_name`  | = `name`  | human name for the menu / `.desktop`               |
| `comment`      | —         | `Comment=` in the `.desktop`                       |
| `categories`   | —         | XDG categories, `;`-separated                      |
| `icon`         | —         | icon path inside the payload (png/svg)             |
| `icon_size`    | `256`     | raster icon size (hicolor `NxN`); svg goes to `scalable` |
| `terminal`     | `false`   | `Terminal=` in the `.desktop`                      |
| `mime_types`   | —         | `MimeType=` in the `.desktop` (`;`-separated/terminated) |
| `extra_exec`   | —         | space-separated extra executables; one launcher per basename |
| `bash_completion` | —      | completion file inside the payload, installed as `completions/<name>` |
| `bundle_libs`  | `false`   | builder collects non-system `.so` via `ldd` (main + extra execs) |
| `isolate_home` | `false`   | runtime redirects `HOME`/`XDG_*` into the app dir  |
| `min_glibc`    | —         | minimum host glibc (e.g. `2.31`); auto-detected by `bs build` |
| `build_id`     | (auto)    | content hash of the payload tree, appended by `bs build`; cache key |
| `maintainer`   | —         | who built the package                              |
| `homepage`     | —         | project URL                                        |

---

## 3. Runtime behavior

Control verbs are recognized **only as the first argument**; anything else is
passed straight to the application (so app arguments never clash).

| invocation                       | action                                             |
|----------------------------------|----------------------------------------------------|
| `./app.bs [args...]`             | extract to cache (idempotent), set env, exec app   |
| `./app.bs --install`             | integrate into the user's XDG dirs                 |
| `sudo ./app.bs --install --system` | integrate system-wide (`/opt`, `/usr/local`)     |
| `./app.bs --uninstall [--system]`| remove an installed copy                           |
| `./app.bs --extract [DIR]`       | unpack the payload                                 |
| `./app.bs --check`               | integrity self-test (payload stream + sidecars)    |
| `./app.bs --info`                | print metadata (reads only the manifest)           |
| `./app.bs --help`                | usage                                              |

Run-time environment: `PATH` gets `…/bin`; if `lib/` exists, `LD_LIBRARY_PATH`
gets it prepended; if `isolate_home = true`, `HOME` and `XDG_*` are redirected
into `<appdir>/home` so configs stay with the app.

Before running or installing, the package compares its `os`/`arch` to the host
(same normalization as the builder) and refuses a foreign platform with a clear
message instead of the kernel's `Exec format error`. Bypass: `BS_NO_ARCH_CHECK=1`.
An `arch=any` package (a pure-script payload with no ELF — e.g. the GUI launcher)
skips the architecture comparison; the `os` field still applies.

### Install destinations

Portable run cache:
```
${XDG_CACHE_HOME:-~/.cache}/installer-bs/<name>-<version>/
```
The cache is keyed on the manifest's `build_id` (stored in the dir's `.bs-ok`):
a rebuilt package with the same name-version re-extracts instead of running
stale files. Extraction goes to a temp dir and is published with an atomic
rename, so concurrent first runs never see a half-extracted tree. Inspect and
prune the caches with `bs cache [list|clean]`.

`--install` (user, default — no root):
```
${XDG_DATA_HOME:-~/.local/share}/installer-bs/<name>/      # payload
~/.local/bin/<name>                                        # generated launcher (+ one per extra_exec basename)
${XDG_DATA_HOME:-~/.local/share}/applications/<name>.desktop
${XDG_DATA_HOME:-~/.local/share}/icons/hicolor/scalable/apps/<name>.svg   # svg icon
${XDG_DATA_HOME:-~/.local/share}/icons/hicolor/<N>x<N>/apps/<name>.<ext>  # raster icon (icon_size)
${XDG_DATA_HOME:-~/.local/share}/man/man<N>/...            # links to payload share/man pages
${XDG_DATA_HOME:-~/.local/share}/bash-completion/completions/<name>  # if bash_completion set
<appdir>/.bs-files                                         # paths to remove on uninstall
```

`--install --system` (root): same layout under `/opt/<name>/` (payload) and
`/usr/local/{bin,share/applications,share/icons,share/man,share/bash-completion}`.

Icons land in the **hicolor theme**, so the `.desktop`'s `Icon=` is the themed
name `<name>`, not an absolute path. Man pages found under the payload's
`share/man/man<N>/` are linked into the standard man path (man-db discovers it
next to the launcher's bin dir).

**Never** a directory in the filesystem root. FHS / XDG only.

Installing over an existing install is a clean upgrade: the old version's
recorded files and payload are removed first (no orphans from files the new
version dropped), while `<appdir>/home` — the isolated user data — survives.

Uninstall reads `<appdir>/.bs-files` (a plain list written at install time — no
sed-injection into a script, unlike the original) and removes those paths, then
the app dir. The same works without the original `.bs` file at all:
`bs list`, `bs info <name>`, `bs uninstall <name> [--system]`.

---

## 4. Integrity and authenticity

Two independent, optional sidecars — both honestly labeled:

- `<file>.bs.sha256` (`sha256sum`): detects a corrupted/partial copy. **Not** a
  security signature. Written automatically by `bs build`. MD5 is not used anywhere.
- `<file>.bs.sig` (OpenPGP detached, armored): real authenticity. Created by
  `bs sign <pkg> [-k KEYID]` and checked by `bs verify <pkg>` via `gpg`. The
  checksum proves the bytes are intact; the signature proves **who** built them.

`./app.bs --check` is the package's own integrity self-test. It deliberately
embeds **no** checksum (a hash stored inside the file it "protects" is the
original's MD5 theater with extra steps): the payload is streamed through the
decompressor, whose container checksums (xz CRC64 / gzip CRC32) catch
corruption and truncation; the `.sha256` and `.sig` sidecars are verified too
when they sit next to the file.

## 5. Compatibility (library bundling)

With `bundle_libs = true`, the builder runs `ldd` on the executable and copies
dependent `.so` files into `lib/`, excluding the base loader/libc set
(`ld-linux*`, `libc`, `libm`, `libpthread`, `libdl`, `librt`; `libstdc++`
optional), as linuxdeploy/AppImage do. The runtime prepends `lib/` to
`LD_LIBRARY_PATH`. No sandbox, no qemu in format 1; a foreign architecture fails
with a clear message rather than emulating.

**glibc is never bundled** — only excluded, as above. glibc is a matched set with its dynamic
loader `ld-linux.so` and is forward-compatible only: a package built against glibc X runs on hosts
with glibc ≥ X, never older. The right fix for reach is to build on the **oldest** glibc you intend
to support (as AppImage/manylinux do on ancient base images), not to bundle glibc — which would also
drag in its loader, `gconv` modules and `dlopen`'d NSS plugins. Symptom of too-new a build host:
`version 'GLIBC_2.x' not found` on an older target.

To make that failure legible, `bs build` records the minimum glibc as the optional
`min_glibc` manifest field — the highest `GLIBC_x.y` symbol across the payload's
ELF binaries (via `objdump`/`readelf`). At run/install time the package compares
it to the host and, if the host is older, prints a clear message (and a GUI
dialog via `zenity`/`kdialog`/`xmessage` when a display is present) instead of the
cryptic loader error. Bypass with `BS_NO_GLIBC_CHECK=1`.

## 6. Recipes (`bs make`)

A recipe builds a package from an upstream artifact instead of a pre-laid-out
directory. It is a small bash file authored by the packager — trusted, like a
PKGBUILD or a Homebrew formula — sourced in a scoped way by `bs make <recipe>`.

Because the recipe is sourced as bash, quote any value containing spaces or
shell metacharacters such as `;` (`comment="A nice app"`,
`categories="Graphics;2DGraphics;"`). It can read `$RECIPE_DIR` (its own
directory) to find bundled sources.

A recipe sets the manifest fields (`name`, `version`, `arch`, `os`, `exec`, and
the optional ones) and obtains the files in one of two ways:

- declare `source_url` + `source_type` (`appimage` | `tar` | `zip` | `deb` |
  `file`) and, ideally, `source_sha256` — the default flow fetches, verifies and
  lays out the payload (a `.deb` is read with binutils `ar`, no dpkg needed); or
- define a `prepare()` function that populates `$pkgdir`, using helpers:
  - `bs_fetch URL DEST [SHA256]` — download (or copy a local path / `file://`),
    verifying the checksum when given;
  - `bs_fetch_all` — fetch every URL of the recipe's `sources=()` array into
    `$srcdir`, verified against `sha256s=()` by index (multi-input recipes);
  - `bs_appimage_extract FILE DESTDIR` — extract an AppImage's tree (Linux host
    of the matching architecture);
  - `bs_zip_extract FILE DESTDIR`, `bs_deb_extract FILE DESTDIR`.

Checksummed downloads are kept in a content-addressed cache
(`$XDG_CACHE_HOME/installer-bs/downloads/sha256-<hash>`), so a repeated
`bs make` works offline; reuse is safe by construction because the key **is**
the verified hash. Unverified downloads are never cached. Disable with
`BS_NO_FETCH_CACHE=1`; prune with `bs cache clean`.

`bs make` then writes the manifest from the recipe fields and hands the staged
directory to `bs build`. Example: [`examples/krita/recipe`](../examples/krita/recipe)
repackages the official Krita AppImage, verified against KDE's published sha256.
