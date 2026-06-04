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
  `grep -an '^__BS_PAYLOAD__$' "$0" | head -1` and streams from there with `tail -n +N`.
- `bs build` forms a package as `cat stub.sh <marker is the stub's last line> payload > out.bs`.
- The stub `exit`s before the marker, so the binary payload is never parsed as code.
- Default file name: `<name>-<version>-<arch>.bs`.

### Compression

The payload is a tar compressed with **xz** (default) or **gzip** (fallback when
`xz` is absent at build time). The runtime does not rely on tar autodetecting
compression from a pipe (not portable); it reads the payload's magic bytes
(`fd 37 7a 58 5a 00` = xz, `1f 8b` = gzip) and decompresses explicitly, then pipes
to plain `tar`.

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
| `arch`    | `x86_64`    | target architecture (`uname -m` style)  |
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
| `terminal`     | `false`   | `Terminal=` in the `.desktop`                      |
| `bundle_libs`  | `false`   | builder collects non-system `.so` via `ldd`        |
| `isolate_home` | `false`   | runtime redirects `HOME`/`XDG_*` into the app dir  |
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
| `./app.bs --info`                | print metadata (reads only the manifest)           |
| `./app.bs --help`                | usage                                              |

Run-time environment: `PATH` gets `…/bin`; if `lib/` exists, `LD_LIBRARY_PATH`
gets it prepended; if `isolate_home = true`, `HOME` and `XDG_*` are redirected
into `<appdir>/home` so configs stay with the app.

### Install destinations

Portable run cache:
```
${XDG_CACHE_HOME:-~/.cache}/installer-bs/<name>-<version>/
```

`--install` (user, default — no root):
```
${XDG_DATA_HOME:-~/.local/share}/installer-bs/<name>/      # payload
~/.local/bin/<name>                                        # generated launcher
${XDG_DATA_HOME:-~/.local/share}/applications/<name>.desktop
${XDG_DATA_HOME:-~/.local/share}/icons/<name>.<ext>        # if icon set
<appdir>/.bs-files                                         # paths to remove on uninstall
```

`--install --system` (root):
```
/opt/<name>/                              # payload
/usr/local/bin/<name>                     # launcher
/usr/local/share/applications/<name>.desktop
/usr/local/share/icons/<name>.<ext>
```

**Never** a directory in the filesystem root. FHS / XDG only.

Uninstall reads `<appdir>/.bs-files` (a plain list written at install time — no
sed-injection into a script, unlike the original) and removes those paths, then
the app dir.

---

## 4. Integrity and authenticity

Two independent, optional sidecars — both honestly labeled:

- `<file>.bs.sha256` (`sha256sum`): detects a corrupted/partial copy. **Not** a
  security signature. Written automatically by `bs build`. MD5 is not used anywhere.
- `<file>.bs.sig` (OpenPGP detached, armored): real authenticity. Created by
  `bs sign <pkg> [-k KEYID]` and checked by `bs verify <pkg>` via `gpg`. The
  checksum proves the bytes are intact; the signature proves **who** built them.

## 5. Compatibility (library bundling)

With `bundle_libs = true`, the builder runs `ldd` on the executable and copies
dependent `.so` files into `lib/`, excluding the base loader/libc set
(`ld-linux*`, `libc`, `libm`, `libpthread`, `libdl`, `librt`; `libstdc++`
optional), as linuxdeploy/AppImage do. The runtime prepends `lib/` to
`LD_LIBRARY_PATH`. No sandbox, no qemu in format 1; a foreign architecture fails
with a clear message rather than emulating.

## 6. Recipes (`bs make`)

A recipe builds a package from an upstream artifact instead of a pre-laid-out
directory. It is a small bash file authored by the packager — trusted, like a
PKGBUILD or a Homebrew formula — sourced in a scoped way by `bs make <recipe>`.

Because the recipe is sourced as bash, quote any value containing spaces
(`comment="A nice app"`). It can read `$RECIPE_DIR` (its own directory) to find
bundled sources.

A recipe sets the manifest fields (`name`, `version`, `arch`, `os`, `exec`, and
the optional ones) and obtains the files in one of two ways:

- declare `source_url` + `source_type` (`appimage` | `tar` | `file`) and,
  ideally, `source_sha256` — the default flow fetches, verifies and lays out the
  payload; or
- define a `prepare()` function that populates `$pkgdir`, using helpers:
  - `bs_fetch URL DEST [SHA256]` — download (or copy a local path / `file://`),
    verifying the checksum when given;
  - `bs_appimage_extract FILE DESTDIR` — extract an AppImage's tree (Linux host
    of the matching architecture).

`bs make` then writes the manifest from the recipe fields and hands the staged
directory to `bs build`. Example: [`examples/krita/recipe`](../examples/krita/recipe)
repackages the official Krita AppImage, verified against KDE's published sha256.
