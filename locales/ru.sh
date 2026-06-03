# Русская локаль. Ключи берутся из кода через i18n::t.
# TODO(WP1): заполнить полный набор пользовательских строк.
# shellcheck disable=SC2034  # используется i18n после реализации WP1.

declare -gA BS_STR_RU=(
	[app_tagline]="Bundled Software. Мы не решили ад зависимостей — мы его завернули."
	[err_unsupported_platform]="Неподдерживаемая платформа: %s"
)
