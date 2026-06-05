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
terminal     = false
bundle_libs  = false           # true → собрать .so через ldd (см. Путь 3)
isolate_home = false           # true → конфиги приложения держать внутри пакета
```

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

**А) Через `source_url` + `source_type`** (`appimage` | `tar` | `file`) и (желательно) `source_sha256`:

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
- `bs_appimage_extract FILE DESTDIR` — распаковать AppImage (нужен Linux нужной архитектуры);
- `$srcdir` — рабочий каталог, `$pkgdir` — что попадёт в пакет, `$RECIPE_DIR` — каталог самого рецепта.

```sh
./bs make examples/krita/recipe       # реальный пример: офиц. AppImage Krita + проверка KDE sha256
```

Реальный пример с проверкой целостности по опубликованному upstream-хешу —
[`examples/krita/recipe`](../examples/krita/recipe).

---

## Путь 3 — скомпилированный бинарь + зависимости (бандлинг)

Самый честный и самый трудоёмкий. Программа линкует библиотеки, которых на цели может не быть.

**3.1. Автоматический бандлинг (`bundle_libs = true`).** При сборке `bs` прогоняет `ldd` по
бинарю, копирует не-системные `.so` в `lib/` пакета (базовый `libc`/loader **не** трогает —
как AppImage), а раннтайм добавляет `lib/` в `LD_LIBRARY_PATH`. Работает, если `exec` —
ELF-бинарь, а хост — той же архитектуры (`ldd` резолвит хостовым загрузчиком).

Рабочий пример: [`examples/greeter`](../examples/greeter) — C-приложение со **своей** `libgreet.so`.
Проверено: на системе, где библиотеки нет, пакет всё равно запускается — `.so` берётся из бандла.

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
./my-app-*.bs --info                # метаданные (читает только manifest)
./my-app-*.bs --extract DIR         # просто распаковать
```

Управляющие флаги действуют только как **первый** аргумент; всё остальное уходит приложению.

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
| `version 'GLIBC_2.x' not found` при запуске | Пакет собран на более новом glibc, чем на цели. glibc мы не бандлим (он связан с загрузчиком и совместим только вперёд). Собирай на **самом старом** целевом дистрибутиве / старом базовом образе — как AppImage/manylinux. |
| `exec not found in source: …` | В каталоге/после prepare нет файла, указанного в `exec`. Проверь путь. |
| `manifest is missing required field` | Нет `name/version/arch/os/exec`. Добавь. |
| `invalid name '…'` | Имя не по `^[a-z0-9][a-z0-9._-]*$`. Только строчные, цифры, `._-`. |
| `exec is not an ELF binary; nothing to bundle` | `bundle_libs=true`, а `exec` — скрипт. Бандлить нечего — это норм, либо укажи реальный бинарь. |
| `bundle_libs needs a native build host` | Кросс-арх + бандлинг. `ldd` работает только на родной архитектуре. |
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
