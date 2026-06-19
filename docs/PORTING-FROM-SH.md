# Переход с Installer-SH на Installer-BS

Краткая карта «грех оригинала → как у нас» и шпаргалка по миграции пакета.
Развёрнутый разбор с номерами строк — в [`docs/dev/ANTIPATTERNS.md`](dev/ANTIPATTERNS.md) (40 пунктов)
и [`docs/MUSEUM.md`](MUSEUM.md) (23 зала).

## Грех → как у нас

| Installer-SH | Installer-BS |
|---|---|
| монолит `installer.sh` ~2000 строк | `bs` + модули `lib/*.sh` |
| `_SCREAMING_FUNC`, баннеры `##### ----` | `lower_snake_case`, комментарии по делу |
| настройки и MD5 правятся внутри скрипта | декларативный `manifest`, данные вне кода |
| `sed` переписывает сам скрипт | программа свой код не трогает |
| MD5 как «защита» | опц. `sha256` (докачка) + OpenPGP-подпись `bs sign`/`bs verify` (подлинность) |
| `source` локали/`user-dirs`/`ish-settings` | парсинг как данных, без `eval`/`source` |
| 8 бинарей `ExeFile-*` в пакете | 1 пакет = 1 арх (в имени файла) |
| вкомпиленный 7-Zip в git | системный `xz`/`tar`, ноль бинарей в репо |
| `/portsoft` в корне ФС | XDG / `/opt` / `/usr/local` |
| дубль-ветка FreeBSD в каждой функции | Linux-цель; платформа за `lib/platform/` |
| `LD_32/64_LIBRARY_PATH` (несуществующие) | реальный `LD_LIBRARY_PATH` |
| деинсталлятор через `sed`-инъекцию | список `.bs-files`, читается построчно |
| `printf '\033[8;..t'` ресайзит твой терминал | геометрию окна не трогаем |
| `Terminal=true` в `.desktop` по умолчанию | `Terminal` берётся из манифеста (дефолт false) |
| тест = tmpfs в виртуалке руками | `tests/e2e.sh`, автоматом, без рута |

## Миграция пакета: settings → manifest

В оригинале параметры пакета жили переменными в теле `installer.sh`. В Installer-BS они переезжают
в маленький `manifest`:

| Installer-SH (переменная в installer.sh) | Installer-BS (`manifest`) |
|---|---|
| `Unique_App_Folder_Name` | `name` |
| `AppVersion` | `version` |
| `Program_Architecture` (`multi` → конкретная) | `arch` (одна арх на пакет) |
| — (предполагался Linux/FreeBSD) | `os` (`linux`) |
| путь к `launcher`/`ExeFile` | `exec` (путь к бинарю внутри пакета) |
| `Program_Name_In_Menu` | `pretty_name` |
| `Additional_Categories` | `categories` |
| `Menu_Directory_Icon` | `icon` |
| `Install_Configs="PortSoft"` (изоляция конфигов) | `isolate_home = true` |
| `UseExtraLibs` + `libs64/` | `bundle_libs = true` (собирается из `ldd`) |

Раскладка исходника пакета:

```
my-app/
├── manifest
├── bin/<exec>        # основной бинарь (и прочие исполняемые)
├── lib/              # опц.; либо положи сам, либо bundle_libs=true соберёт
└── share/            # иконки, ассеты
```

Затем:

```sh
bs build my-app          # -> my-app-<version>-<arch>.bs
./my-app-*.bs            # запуск; --install / --uninstall / --info / --extract
```

Полная спецификация — [`docs/PACKAGE-FORMAT.md`](PACKAGE-FORMAT.md).
