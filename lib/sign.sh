# shellcheck shell=bash
# Sign: real OpenPGP detached signatures for .bs packages (via gpg). This is
# actual cryptography for authenticity — as opposed to the original's MD5, which
# was paraded as "integrity protection". The optional .sha256 sidecar only
# catches corruption; the .sig proves who built the package.

# sign::sign PKG [-k KEYID]
sign::sign() {
	local pkg="" key=""
	while (($#)); do
		case "$1" in
			-k|--key) shift; key="${1:-}" ;;
			-*) ui::error "unknown sign option: $1"; return 2 ;;
			*) if [[ -z "$pkg" ]]; then pkg="$1"; else ui::error "unexpected argument: $1"; return 2; fi ;;
		esac
		shift
	done
	[[ -n "$pkg" ]] || { ui::error "$(i18n::t err_sign_usage)"; return 2; }
	[[ -f "$pkg" ]] || { ui::error "$(i18n::t err_not_found "$pkg")"; return 1; }
	command -v gpg >/dev/null 2>&1 || { ui::error "$(i18n::t err_no_gpg)"; return 127; }

	local args=(--batch --yes --armor --detach-sign --output "$pkg.sig")
	[[ -n "$key" ]] && args+=(--local-user "$key")
	if gpg "${args[@]}" "$pkg"; then
		ui::ok "$(i18n::t sign_done "$pkg.sig")"
	else
		ui::error "$(i18n::t sign_fail)"; return 1
	fi
}

# sign::verify PKG
# Checks the .sha256 sidecar (corruption) and the .sig (authenticity) if present.
sign::verify() {
	local pkg="${1:-}"
	[[ -n "$pkg" ]] || { ui::error "$(i18n::t err_verify_usage)"; return 2; }
	[[ -f "$pkg" ]] || { ui::error "$(i18n::t err_not_found "$pkg")"; return 1; }
	local rc=0 checked=0

	if [[ -f "$pkg.sha256" ]] && command -v sha256sum >/dev/null 2>&1; then
		checked=1
		if ( cd "$(dirname -- "$pkg")" && sha256sum -c "$(basename -- "$pkg").sha256" ) >/dev/null 2>&1; then
			ui::ok "$(i18n::t verify_sha_ok)"
		else
			ui::error "$(i18n::t verify_sha_bad)"; rc=1
		fi
	fi

	if [[ -f "$pkg.sig" ]]; then
		checked=1
		command -v gpg >/dev/null 2>&1 || { ui::error "$(i18n::t err_no_gpg)"; return 127; }
		local vout
		if vout="$(gpg --verify "$pkg.sig" "$pkg" 2>&1)"; then
			ui::ok "$(i18n::t verify_sig_ok)"
			local who; who="$(printf '%s\n' "$vout" | grep -i 'good signature' | head -1)"
			[[ -n "$who" ]] && ui::info "$who"
		else
			ui::error "$(i18n::t verify_sig_bad)"; rc=1
		fi
	fi

	((checked == 1)) || ui::warn "$(i18n::t verify_nothing)"
	return "$rc"
}
