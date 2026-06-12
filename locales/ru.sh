# shellcheck shell=bash
# Русская локаль. Строки — данные, берутся через i18n::t.
# Значения могут содержать спецификаторы printf (напр. %s).
# shellcheck disable=SC2034  # используется i18n::load через косвенное обращение.

declare -gA BS_STR_RU=(
	[app_tagline]="installer-bs — Bundled Software. Ад зависимостей мы не победили; мы завернули его в tar.xz и пошли дальше."

	[help_usage]="Использование: bs <команда> [опции]"
	[help_commands]="Команды:"
	[help_build]="Собрать пакет .bs из каталога + манифеста."
	[help_info]="Показать манифест пакета .bs."
	[help_version]="Версия и определённая платформа."
	[help_help]="Показать эту справку."
	[help_options]="Опции:"
	[help_opt_yes]="Считать всё за «да»; не спрашивать (для скриптов)."
	[help_opt_lang]="Принудительный язык интерфейса (напр. en, ru)."
	[help_opt_nocolor]="Отключить цветной вывод."
	[help_opt_debug]="Подробный отладочный вывод."
	[help_opt_help]="Показать эту справку."
	[help_opt_version]="Показать версию."
	[help_footer]="План: docs/dev/AGENT-TASKS.md  -  Музей грехов оригинала: docs/MUSEUM.md"

	[version_quip]="Папка /portsoft в корне твоей ФС не создана. Не благодари."

	[err_unknown_command]="Неизвестная команда: %s. Попробуй 'bs --help'."
	[err_unknown_flag]="Неизвестная опция: %s. Попробуй 'bs --help'."
	[err_info_usage]="Использование: bs info <пакет.bs | имя установленного>"
	[err_build_usage]="Использование: bs build <каталог> [-o out.bs] [--gzip]"
	[err_is_recipe]="похоже на рецепт — собирай через: bs make %s"
	[err_not_found]="Файл или каталог не найден: %s"

	[build_done]="собрано %s"
	[build_size]="размер: %s"
	[build_overwrite]="Перезаписать %s?"
	[build_cancelled]="сборка отменена"

	[help_make]="Собрать пакет из рецепта (скачать, проверить, упаковать)."
	[help_sign]="Подписать пакет через OpenPGP (gpg)."
	[help_verify]="Проверить подпись и контрольную сумму пакета."
	[err_make_usage]="Использование: bs make <рецепт> [-o out.bs]"
	[err_sign_usage]="Использование: bs sign <пакет.bs> [-k KEYID]"
	[err_verify_usage]="Использование: bs verify <пакет.bs>"
	[err_no_gpg]="gpg не найден (установи GnuPG для подписи/проверки)"
	[sign_done]="подписано -> %s"
	[sign_fail]="подпись не удалась"
	[verify_sha_ok]="контрольная сумма ок (sha256)"
	[verify_sha_bad]="КОНТРОЛЬНАЯ СУММА НЕ СОВПАЛА (sha256)"
	[verify_sig_ok]="подпись верна (OpenPGP)"
	[verify_sig_bad]="ПОДПИСЬ НЕВЕРНА (OpenPGP)"
	[verify_nothing]="нечего проверять (рядом нет .sig или .sha256)"

	[help_run]="Запустить пакет .bs (то же, что выполнить его напрямую)."
	[help_list]="Список установленного (user и system)."
	[help_uninstall]="Удалить пакет по имени — файл .bs не нужен."
	[help_cache]="Показать или почистить кэши портативных запусков."
	[err_run_usage]="Использование: bs run <пакет.bs> [аргументы...]"
	[err_uninstall_usage]="Использование: bs uninstall <имя> [--system]"
	[err_cache_usage]="Использование: bs cache [list | clean [имя]]"
	[err_not_installed]="не установлено: %s (смотри 'bs list')"
	[list_empty]="ничего не установлено. Корень твоей ФС по-прежнему чист."
	[uninstall_confirm]="Удалить %s %s (%s)?"
	[uninstall_cancelled]="удаление отменено"
	[uninstall_done]="удалено: %s"
	[cache_empty]="кэш пуст — ничего не распаковано, ничего не копится"
	[cache_confirm]="Удалить эти кэш-каталоги (%s шт.)?"
	[cache_cancelled]="чистка кэша отменена"
	[cache_cleaned]="удалено кэш-каталогов: %s"
)
