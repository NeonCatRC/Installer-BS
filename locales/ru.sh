# Русская локаль. Строки — данные, берутся через i18n::t.
# Значения могут содержать спецификаторы printf (напр. %s).
# shellcheck disable=SC2034  # используется i18n::load через косвенное обращение.

declare -gA BS_STR_RU=(
	[app_tagline]="installer-bs — Bundled Software. Ад зависимостей мы не победили; мы завернули его в tar.xz и пошли дальше."

	[help_usage]="Использование: bs <команда> [опции]"
	[help_commands]="Команды:"
	[help_build]="Собрать пакет .bs из каталога + манифеста (WP3)."
	[help_info]="Показать манифест пакета .bs (WP2)."
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

	[err_unsupported_platform]="Неподдерживаемая платформа: %s"
	[err_unknown_command]="Неизвестная команда: %s. Попробуй 'bs --help'."
	[err_unknown_flag]="Неизвестная опция: %s. Попробуй 'bs --help'."
	[err_info_usage]="Использование: bs info <пакет.bs>"
	[err_build_usage]="Использование: bs build <каталог> [-o out.bs] [--gzip]"
	[err_not_found]="Файл или каталог не найден: %s"

	[build_done]="собрано %s"
	[build_size]="размер: %s"
)
