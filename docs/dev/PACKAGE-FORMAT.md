# Спецификация формата `.bs` и манифеста (черновик)

Версия формата: `1`. Это рабочий черновик; при стабилизации переезжает в `docs/PACKAGE-FORMAT.md`.

---

## 1. Файл пакета `.bs`

Самодостаточный исполняемый bash-файл. Структура сверху вниз:

```
#!/usr/bin/env bash
# --- stub.sh: раннтайм (run / install / uninstall / extract / info) ---
# ... код раннтайма ...

# --- встроенный манифест (читается парсером, НЕ исполняется) ---
# BS-MANIFEST-BEGIN
# name = hello
# version = 1.0.0
# arch = x86_64
# os = linux
# exec = bin/hello
# ...
# BS-MANIFEST-END

__BS_PAYLOAD__
<здесь сырой поток tar.xz — бинарь, до конца файла>
```

Принципы:
- Раннтайм находит начало payload по строке-маркеру `__BS_PAYLOAD__`:
  `offset=$(grep -an '^__BS_PAYLOAD__$' "$0" | head -1 | cut -d: -f1)`,
  затем `tail -n +$((offset+1)) "$0" | xz -dc | tar -x -C "$dest"`.
- Манифест продублирован в шапке как строки-комментарии `# key = value` между маркерами
  `BS-MANIFEST-BEGIN`/`BS-MANIFEST-END`, чтобы раннтайм знал метаданные без распаковки payload.
- Внутри payload лежит каноничный `manifest` (тот же контент) — источник правды при сборке.
- Имя файла по умолчанию: `<name>-<version>-<arch>.bs`.

## 2. Манифест

Декларативный текст. Парсится построчно, **не** исполняется как bash.

Правила парсинга:
- Кодировка UTF-8, переводы строк LF.
- Пустые строки и строки, начинающиеся с `#`, игнорируются.
- Формат строки: `key = value`. Разделитель — первый `=`. Пробелы вокруг ключа и значения тримятся.
- Значение берётся как есть до конца строки (кавычки не обязательны; если есть — снимается одна пара).
- Неизвестные ключи → предупреждение, не ошибка (forward-compat).
- Парсер обязан игнорировать любые shell-метасимволы (никакого eval). Тест: значение
  `exec = bin/h; rm -rf ~` должно дать строку `bin/h; rm -rf ~`, а не выполниться.

### Обязательные поля

| ключ      | пример          | смысл                                              |
|-----------|-----------------|----------------------------------------------------|
| `name`    | `hello`         | имя пакета (lowercase, `[a-z0-9-]`)                |
| `version` | `1.0.0`         | версия приложения                                  |
| `arch`    | `x86_64`        | целевая архитектура (`uname -m`-совместимая)        |
| `os`      | `linux`         | `linux` или `freebsd`                              |
| `exec`    | `bin/hello`     | путь к основному бинарю внутри payload              |

### Необязательные поля

| ключ            | дефолт        | смысл                                                          |
|-----------------|---------------|---------------------------------------------------------------|
| `format`        | `1`           | версия формата пакета                                          |
| `pretty_name`   | = `name`      | человекочитаемое имя для меню/`.desktop`                       |
| `comment`       | пусто         | описание (поле `Comment` в `.desktop`)                         |
| `categories`    | `Utility`     | XDG-категории через `;`                                        |
| `icon`          | пусто         | путь к иконке внутри payload (png/svg)                         |
| `terminal`      | `false`       | запускать в терминале (`Terminal=` в `.desktop`)              |
| `bundle_libs`   | `false`       | при сборке собрать не-системные `.so` через `ldd`             |
| `isolate_home`  | `false`       | перенаправлять `XDG_*`/`HOME` в data-каталог приложения        |
| `args`          | пусто         | доп. аргументы по умолчанию к `exec`                           |
| `maintainer`    | пусто         | кто собрал пакет                                               |
| `homepage`      | пусто         | URL проекта                                                   |

### Пример (`template/manifest.example`)

```
# Installer-BS package manifest (format 1)
name         = hello
pretty_name  = Hello BS
version      = 1.0.0
arch         = x86_64
os           = linux
exec         = bin/hello
comment      = Минимальный пример пакета Installer-BS
categories   = Utility;
icon         = share/hello.svg
bundle_libs  = false
isolate_home = false
```

## 3. Раскладка payload (внутри tar.xz)

```
payload/
├── manifest            # каноничный манифест
├── bin/<exec>          # основной бинарь и прочие исполняемые
├── lib/                # бандл-либы (если bundle_libs=true)
├── share/              # иконки, ассеты, .desktop-шаблон если нужен
└── ...                 # любые файлы приложения
```

## 4. Каталоги на целевой машине

Портативный запуск (кэш, чистится по `--clean-cache`):
```
$XDG_CACHE_HOME/installer-bs/<name>-<version>/
```

`--install` (user, дефолт):
```
$XDG_DATA_HOME/installer-bs/<name>/        # payload
~/.local/bin/<name>                        # лаунчер (exec → payload)
~/.local/share/applications/<name>.desktop # ярлык
~/.local/share/icons/.../<name>.<ext>      # иконка
$XDG_DATA_HOME/installer-bs/<name>/.bs-files  # список установленных путей для uninstall
```

`--install --system` (root, опц.):
```
/opt/<name>/                               # payload
/usr/local/bin/<name>                      # лаунчер
/usr/local/share/applications/<name>.desktop  # (или /usr/share/... если доступно)
```

**Никаких** `/portsoft` и прочих каталогов в корне. FHS/XDG строго.

## 5. Целостность

- Опционально рядом с пакетом кладётся `<file>.bs.sha256` (через `sha256sum`).
- Назначение — обнаружить битую копию/докачку. Это **не** «защита», и мы честно так и пишем.
- MD5 из оригинала не используем нигде.

## 6. Совместимость (бандлинг)

- `bundle_libs=true`: при сборке `ldd <exec>` → копируем зависимые `.so`, **исключая**
  системные базовые (`ld-linux*`, `libc`, `libm`, `libpthread`, `libdl`, `librt`, `libstdc++`*
  — по настраиваемому exclude-list, как делает linuxdeploy/AppImage).
- Раннтайм выставляет `LD_LIBRARY_PATH="$payload/lib:$LD_LIBRARY_PATH"` перед exec.
- Никаких sandbox/qemu в текущей версии. Чужая арх → внятная ошибка, не эмуляция.

(* `libstdc++` — спорный, выносим в настраиваемый список; по умолчанию не бандлим.)
