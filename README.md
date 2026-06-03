## Installer-SH [![Github Releases](https://img.shields.io/github/downloads/Shedou/Installer-SH/total.svg)](https://github.com/Shedou/Installer-SH/releases)

Installer-SH is a standalone installation package for Linux and FreeBSD applications, allowing you to distribute and install programs even on standalone computers with different architectures.

```
У нас было две большие папочки с форками apt, pacman, brew и nix на GitHub, но это не главное... У нас было также 75 готовых функций для парсинга выводов пакет-менеджеров, 200 гигабайт кэша с каждой версией glibc когда-либо скомпилированной, четыре системных блока с миллионом строк bash-кода, половину документации из StackOverflow 2015 года, 2 VPN чтобы скачать исходники с мёртвых сайтов, и огромный файл конфига с 500 строками sed регулярных выражений...
Честно говоря, я не помню как мы вообще смогли это всё заткнуть в один скрипт на 15 килобайт. Но главное — у нас была АБСОЛЮТНАЯ, СВЯЩЕННАЯ убежденность в том, что мы наконец РАЗЛОМАЛИ проблему зависимостей Linux. Что если мы просто проигнорируем конфликты версий, заставим LD_LIBRARY_PATH указывать на 47 разных директорий одновременно и добавим функцию fuck_it_just_recompile() — тогда система СТАНЕТ работать.
Это был наш Святой Грааль. Нерешаемая задача в одном bash-скрипте. Когда мы запустили его в первый раз и получили Segmentation fault — мы знали, что мы на правильном пути.
```

![Preview.](https://github.com/Shedou/Installer-SH/blob/main/Installer-SH/Preview.jpg)

The current repository is for active development of Installer-SH, it contains the latest version of the installation package, however it may be unstable.

Stable and archived versions are available on the [downloads page](https://github.com/Shedou/Installer-SH/releases) or in the "[Installer-SH-Archive](https://github.com/Shedou/Installer-SH-Archive)" repository.

### Usage: Run "installer.sh" and follow the instructions, or run with "installer.sh -silent" for a silent installation. Run "installer.sh -help" for help.

Applications packaged in Installer-SH format can be found in the "[Chimbalix-Software-Catalog](https://github.com/Shedou/Chimbalix-Software-Catalog)" repository.

Comparison of software distribution formats [tested in different Linux and FreeBSD](https://overclockers.ru/blog/Hard-Workshop/show/256127/Bol-shoe-sravnenie-i-testirovanie-formatov-ustanovki-PO-v-distributivah-Linux-i-FreeBSD-x86-x64) distributions (installing and running the [game "2048"](https://github.com/Shedou/Chimbalix-Software-Catalog/releases/tag/2048c103mpa)):

![Preview.](https://github.com/Shedou/Installer-SH/blob/main/Installer-SH/field-testing-of-formats-2026-05-24.png)

## Features of Installer-SH:

* Ease of use: Installing programs using Installer-SH does not require root privileges by default. Root privileges may be required when installing software in system mode for all users.

* Easy management: Installed applications can be easily removed at any time.

* Reliability: The installation package contains several independent data integrity checks, which allows detecting archives damaged during copying before they are installed on the system.

* Independence: you can distribute and install software without an internet connection.

* Isolation: The default format stores configuration files and other junk generated during software use in a separate directory next to the program. It's also possible to switch to the classic mode, using the user's home directory for storing configuration files.

* Portability: You can easily make a backup copy of the program with all settings and data (menu shortcuts are not saved) if it was installed in standard mode with the configuration files moved to a dedicated directory.

* Compatibility: The installation package does not require any specific dependencies or system libraries. Basic system utilities such as bash, tar, and Coreutils are required.

* Multiplatform: A single installation package can install the program on various Linux and FreeBSD distributions.

* Multi-architecture: A single installation package can install the program on distributions of different architectures (x86, x86_64, amd64, aarch64, and others).

* Different versions: Installer-SH can install different versions of the same program on the same system.

* Flexible: Depending on the needs, the software developer or packager can customize the installation package as required.

* Specifications: For maximum compatibility and convenience, the installation format complies with the PortSoft (https://github.com/Shedou/PortSoft) and XDG Desktop (https://specifications.freedesktop.org) specifications.

* Self-sufficiency: Installer-SH can independently prepare the necessary foundation for further work in accordance with specifications.

* Compression formats: By default, the most compatible compression format tar.xz is used, but at the discretion of the packer, the much more powerful 7-Zip format can be used to compress the program.

* Silent Mode: You can perform a bulk installation of multiple programs in Installer-SH format using the "-silent" parameter.

* Help: You can run "installer.sh" with the "-h" parameter for help with additional usage options. Also, please refer to the developer instructions in the README file in the installer directory if you plan to package your application in Installer-SH format.

Note: It is recommended to use the latest versions of the format when creating new software installation packages. Multiplatform and multiarchitecture support in a single package begins with Installer-SH 2.8. FreeBSD support begins with Installer-SH 2.6. Silent mode support begins with Installer-SH 2.3. Isolation may not solve all the problems of very poorly designed software. Software compatibility depends on the software developer, not the installation package.

## License Installer-SH
```
MIT License

Copyright (c) 2024-2026 Андрей Цымбалов (Chimbal)

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

## License 7-Zip
Detailed information about the 7-Zip license can be found in the file at "Installer-SH/installer-data/tools/7zip/License.txt"
```
  ~~~~~~~~~~~~~~~~~~~~~~~~~
  License for use and distribution
  ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

  7-Zip Copyright (C) 1999-2024 Igor Pavlov.

  The licenses for 7zz and 7zzs files are:

         - The "GNU LGPL" as main license for most of the code
         - The "GNU LGPL" with "unRAR license restriction" for some code
         - The "BSD 3-clause License" for some code
         - The "BSD 2-clause License" for some code

  Redistributions in binary form must reproduce related license information from this file.

  Note:
    You can use 7-Zip on any computer, including a computer in a commercial
    organization. You don't need to register or pay for 7-Zip.
```
