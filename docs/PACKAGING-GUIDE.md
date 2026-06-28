# Сборка пакета `.bs` своими руками — от А до Я

Практическое руководство для авторов пакетов. Формальная спецификация формата —
в [`PACKAGE-FORMAT.md`](PACKAGE-FORMAT.md); здесь — как этим пользоваться на деле.

`.bs` — это один исполняемый файл: bash-раннтайм + сжатый `tar`-хвост. Запустил —
программа работает портативно; `--install` кладёт ярлык в меню по XDG; `--uninstall`
убирает. Никаких папок в корне ФС.

Есть три пути сборки — от простого к сложному. Выбирай по ситуации.

---

## 0. Что нужно

- Для **сборки**: `bash`, `coreutils`, `tar`, `xz` (или `gzip`). Для бандлинга — `ldd`. Для подписи — `gpg`.
- Для **запуска пакета** на целевой машине: `bash`, `tar` и тот распаковщик, которым сжат пакет
  (`xz` по умолчанию — он есть на всех нормальных дистрибутивах; иначе собери с `--gzip`).

```sh
git clone https://github.com/NeonCatRC/Installer-BS && cd Installer-BS
./bs --help     # понимает русский по $LANG
```

---

## Путь 1 — готовый каталог + манифест (`bs build`)

Самый простой. У тебя уже есть собранная программа — разложи её и опиши манифестом.

**1.1. Разложи файлы.** Каталог пакета — корень будущего `tar`, без `./`-обёрток:

```
my-app/
├── manifest
├── bin/my-app          # основной исполняемый файл
├── lib/                # опц.: .so рядом (или bundle_libs=true их добавит)
└── share/my-app.svg    # опц.: иконка, ассеты
```

**1.2. Напиши `manifest`** (формат — `key = value`, парсится как **данные**, без выполнения):

```ini
name         = my-app          # ^[a-z0-9][a-z0-9._-]*$
version      = 1.0.0
arch         = x86_64          # как uname -m
os           = linux
exec         = bin/my-app      # путь к бинарю внутри пакета
pretty_name  = My App          # имя в меню
comment      = Short description
categories   = Utility;        # XDG-категории
icon         = share/my-app.svg
icon_size    = 256             # для растровой иконки (hicolor NxN); svg → scalable
terminal     = false
bundle_libs  = false           # true → собрать .so через ldd (см. Путь 3)
isolate_home = false           # true → конфиги приложения держать внутри пакета

# extra_exec      = bin/my-tool      # доп. бинари: лаунчер на каждый basename
# mime_types      = text/x-my;       # MimeType= в .desktop
# bash_completion = share/completions/my-app.bash
```

`bs build` сам допишет `min_glibc` (для ELF) и `build_id` (контент-хэш дерева —
ключ кэша распаковки). На GNU tar сборка **воспроизводима**: тот же входной
каталог → бит-в-бит тот же `.bs` (эпоха mtime — `SOURCE_DATE_EPOCH`, по умолчанию 0).

**1.3. Собери:**

```sh
./bs build my-app
#   ok   built my-app-1.0.0-x86_64.bs
#   ::   size: ...
```

На выходе — `my-app-1.0.0-x86_64.bs` и `.sha256` рядом. Исходный каталог **не меняется**
(сборка идёт в копии). Минимальный рабочий пример — [`examples/hello`](../examples/hello).

---

## Путь 2 — рецепт (`bs make`): скачать апстрим и переупаковать

Когда исходник — это апстрим-артефакт (AppImage, tarball). Рецепт — маленький bash-файл
(как PKGBUILD), его сорсит `bs make`.

**Важно:** рецепт сорсится как bash — **кавычь значения с пробелами или `;`**
(`comment="A nice app"`, `categories="Graphics;2DGraphics;"`).

Рецепт объявляет те же поля, что и манифест, и получает файлы одним из двух способов:

**А) Через `source_url` + `source_type`** (`appimage` | `tar` | `zip` | `deb` | `file`)
и (желательно) `source_sha256`. `.deb` читается обычным `ar` из binutils — dpkg не нужен:

```ini
name=foo
version=1.0
arch=x86_64
os=linux
exec=bin/foo
source_type=tar
source_url=https://example.org/foo-1.0.tar.gz
source_sha256=<hash>      # пусто → скачается без проверки (предупредит)
```

**Б) Через функцию `prepare()`** — для нетривиальной раскладки. Доступны хелперы и переменные:
- `bs_fetch URL DEST [SHA256]` — скачать (или скопировать локальный путь / `file://`), проверить sha256;
- `bs_fetch_all` — скачать все URL из массивов `sources=()` / `sha256s=()` в `$srcdir` (мульти-источники);
- `bs_appimage_extract FILE DESTDIR` — распаковать AppImage (нужен Linux нужной архитектуры);
- `bs_zip_extract FILE DESTDIR`, `bs_deb_extract FILE DESTDIR` — zip / deb;
- `$srcdir` — рабочий каталог, `$pkgdir` — что попадёт в пакет, `$RECIPE_DIR` — каталог самого рецепта.

Скачанное с указанным `sha256` кэшируется по этому хэшу
(`~/.cache/installer-bs/downloads/`): повторный `bs make` работает офлайн.
Без хэша — не кэшируется (честно). Отключить: `BS_NO_FETCH_CACHE=1`.

```sh
./bs make examples/krita/recipe       # реальный пример: офиц. AppImage Krita + проверка KDE sha256
```

Реальные примеры:
- [`examples/krita`](../examples/krita) — офиц. AppImage + проверка по опубликованному KDE sha256, иконка из hicolor-дерева, MIME;
- [`examples/ripgrep`](../examples/ripgrep) — upstream `.deb` без dpkg: распаковка `ar`-ом, man и bash-completion подключаются при `--install`;
- [`examples/fzf`](../examples/fzf) — мульти-источники (`sources=()` + `bs_fetch_all`): бинарь из tar.gz, man-страницы и completion из тегнутого дерева, второй лаунчер `fzf-tmux` через `extra_exec`;
- [`examples/lazygit`](../examples/lazygit) — один статический Go-бинарь, ноль зависимостей (анти-блоб);
- [`examples/helix`](../examples/helix) — бинарь + его `runtime/` рядом, тонкий лаунчер выставляет `HELIX_RUNTIME` (данные ездят с программой, не вкомпилены);
- [`examples/godot`](../examples/godot) — весь движок/редактор в одном самодостаточном бинаре;
- [`examples/vscodium`](../examples/vscodium) — честный Electron-блоб: свои `.so` через `$ORIGIN`-rpath, два лаунчера (GUI + CLI через `extra_exec`), иконка + theming;
- [`examples/blender`](../examples/blender) — офиц. prebuilt-tarball со своим `lib/` (авто на `LD_LIBRARY_PATH`) и data-деревом, `min_glibc` авто, svg-иконка + MIME; GPU/дисплей — с хоста;
- [`examples/openssl-legacy`](../examples/openssl-legacy) — бандл осиротевших `.so` + `LD_LIBRARY_PATH`: OpenSSL 1.1 (его `libssl.so.1.1`/`libcrypto.so.1.1` выпилены из современных дистров) оживает за счёт вложенных в `lib/` библиотек из архивного пакета — ручной бандл, который `bundle_libs` авто не закроет (либы нет на хосте);
- [`examples/xonotic`](../examples/xonotic) — офиц. prebuilt-zip игры, `min_glibc`-страж, кросс-проверка по опубликованному SHA-512 («ответка» на 1.26 ГБ-блоб оригинала);
- [`examples/appimage`](../examples/appimage) — обёртка над любым локальным AppImage (офлайн).

---

## Путь 3 — скомпилированный бинарь + зависимости (бандлинг)

Самый честный и самый трудоёмкий. Программа линкует библиотеки, которых на цели может не быть.

**3.1. Автоматический бандлинг (`bundle_libs = true`).** При сборке `bs` прогоняет `ldd` по
бинарю, копирует не-системные `.so` в `lib/` пакета (базовый `libc`/loader **не** трогает —
как AppImage), а раннтайм добавляет `lib/` в `LD_LIBRARY_PATH`. Работает, если `exec` —
ELF-бинарь, а хост — той же архитектуры (`ldd` резолвит хостовым загрузчиком).

Рабочий пример: [`examples/greeter`](../examples/greeter) — C-приложение со **своей** `libgreet.so`.
Проверено: на системе, где библиотеки нет, пакет всё равно запускается — `.so` берётся из бандла.

Когда нужной `.so` нет даже на **билд-хосте** (классика — осиротевшая `libssl.so.1.1`: современные
дистрибутивы несут только OpenSSL 3), авто-сборщик бессилен: `ldd` нечего копировать. Тогда библиотеку
кладут в `lib/` вручную в `prepare()` (вытащив из архивного пакета), а раннтайм всё равно подхватит её
через `LD_LIBRARY_PATH`. Живой пример — [`examples/openssl-legacy`](../examples/openssl-legacy): бинарь
OpenSSL 1.1 без бандла падает с «`libssl.so.1.1: cannot open shared object file`», а из `.bs` работает.

**3.2. Сложные GUI-приложения (Qt/GTK).** Тут `ldd` мало: фреймворки догружают плагины через
`dlopen` (Qt platform-плагины и т.п.), которые `ldd` не видит. Их копируют отдельно и задают
`QT_PLUGIN_PATH`/`QT_QPA_PLATFORM_PLUGIN_PATH` в обёртке-`exec`. Это делается в `prepare()` рецепта.
Развёрнутый эксперимент (Krita из исходников) — [`examples/krita-src`](../examples/krita-src).

**Честная граница:** завернуть библиотеки — механика. Но GUI-приложению нужен **дисплей-стек**
хоста (X/Wayland) — его не бандлит никто (AppImage тоже опирается на системный X). Поэтому GUI
тестируют на десктопе/в VM, а не в headless-контейнере.

---

## 4. Подпись и проверка

`sha256` (его пишет `bs build`) ловит битую докачку. Подлинность — это **OpenPGP** через `gpg`:

```sh
./bs sign   my-app-1.0.0-x86_64.bs           # -> .bs.sig (detached, armored)
./bs sign   my-app-1.0.0-x86_64.bs -k KEYID  # конкретным ключом
./bs verify my-app-1.0.0-x86_64.bs           # проверяет .sig (кто собрал) и .sha256 (целостность)
```

Распространяй `.bs` вместе с `.bs.sig` (и `.bs.sha256`). MD5 не используется нигде.

---

## 5. Запуск, установка, удаление

```sh
./my-app-*.bs                       # портативно (распаковка в XDG-кэш, без установки)
./my-app-*.bs --install             # в меню пользователя: ~/.local/{bin,share/applications}
sudo ./my-app-*.bs --install --system   # системно: /opt + /usr/local
./my-app-*.bs --uninstall [--system]    # снять подчистую (по списку .bs-files)
./my-app-*.bs --check               # самопроверка целостности (CRC контейнера + .sha256/.sig рядом)
./my-app-*.bs --info                # метаданные (читает только manifest)
./my-app-*.bs --extract DIR         # просто распаковать
```

Управляющие флаги действуют только как **первый** аргумент; всё остальное уходит приложению.
Не та архитектура или ОС — пакет откажется внятно (обход: `BS_NO_ARCH_CHECK=1`).
`--install` поверх старой версии = чистый апгрейд: файлы старой версии снимаются по списку,
`home/` с данными пользователя переживает.

Установленным управляет и сам `bs` — без исходного `.bs`-файла:

```sh
./bs list                  # что установлено (user и system)
./bs info my-app           # метаданные установленного по имени
./bs uninstall my-app      # удалить по имени (--system для системного)
./bs run my-app-*.bs       # фронтенд запуска файла
./bs cache                 # кэши портативных запусков и скачек: показать
./bs cache clean [my-app]  # почистить (всё или по имени)
```

---

## 6. Тестирование

- Локально: `./my-app-*.bs` (портативно) и `--install`/`--uninstall`.
- Чисто и без рута — во временном XDG-префиксе или одноразовом контейнере:
  ```sh
  docker run --rm -v "$PWD:/d:ro" debian:stable-slim bash -lc '
    apt-get update -qq && apt-get install -y -qq xz-utils >/dev/null
    cp /d/my-app-*.bs /tmp/a.bs && HOME=/tmp/h XDG_CACHE_HOME=/tmp/h/.cache /tmp/a.bs'
  ```
- Авто-цикл проекта: `bash tests/e2e.sh` (build → run → install → uninstall + регрессии).

---

## 7. Траблшутинг

| Симптом | Причина и решение |
|---|---|
| `this package needs 'xz' to unpack` | На цели нет `xz`. Поставь `xz-utils`, либо собери с `bs build --gzip`. |
| `version 'GLIBC_2.x' not found` при запуске | Пакет собран на более новом glibc, чем на цели. glibc мы не бандлим (он связан с загрузчиком и совместим только вперёд). Собирай на **самом старом** целевом дистрибутиве / старом базовом образе — как AppImage/manylinux. Теперь пакет сам предупреждает (диалог/сообщение) на слишком старом хосте: `min_glibc` определяется при сборке. Форсировать запуск: `BS_NO_GLIBC_CHECK=1`. |
| `exec not found in source: …` | В каталоге/после prepare нет файла, указанного в `exec`. Проверь путь. |
| `manifest is missing required field` | Нет `name/version/arch/os/exec`. Добавь. |
| `invalid name '…'` | Имя не по `^[a-z0-9][a-z0-9._-]*$`. Только строчные, цифры, `._-`. |
| `exec is not an ELF binary; nothing to bundle` | `bundle_libs=true`, а `exec` — скрипт. Бандлить нечего — это норм, либо укажи реальный бинарь. |
| `bundle_libs needs a native build host` | Кросс-арх + бандлинг. `ldd` работает только на родной архитектуре. |
| `this package is built for linux/x86_64, but…` | Пакет не для этой машины. Возьми сборку под свою платформу; форс — `BS_NO_ARCH_CHECK=1`. |
| `payload is corrupt or truncated` при `--check` | Битая/недокачанная копия. Скачай заново и проверь ещё раз. |
| `line N: … command not found` при `bs make` | Незакавыченное значение в рецепте (пробел/`;`). Возьми в кавычки. |
| GUI не стартует в контейнере (`could not connect to display`) | Нужен дисплей. Тестируй на десктопе/в VM, не headless. |

---

## 8. Чек-лист релиза пакета

- [ ] `manifest`: заполнены `name/version/arch/os/exec`; имя по правилу; `comment`/`icon`/`categories` на месте.
- [ ] `bs build` (или `bs make`) проходит без ошибок; размер вменяемый.
- [ ] Пакет запускается портативно; `--install` → ярлык в меню; `--uninstall` → чисто.
- [ ] Если есть зависимости — проверен запуск там, где их нет в системе (контейнер/VM).
- [ ] `bs sign` + `bs verify` проходят; рядом лежат `.bs.sig` и `.bs.sha256`.
- [ ] Для ультра-минимальных целей — собрано с `--gzip`.
```
