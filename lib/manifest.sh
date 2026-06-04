# shellcheck shell=bash
# Manifest: parse the declarative package manifest as DATA — never source/eval it.
# Used by the builder (bs build). The runtime stub carries its own tiny copy so a
# package stays self-contained. Format reference: docs/PACKAGE-FORMAT.md.

declare -gA BS_MANIFEST=()

# Trim leading/trailing whitespace.
manifest::_trim() {
	local s="$1"
	s="${s#"${s%%[![:space:]]*}"}"
	s="${s%"${s##*[![:space:]]}"}"
	printf '%s' "$s"
}

# manifest::parse FILE
# Fills BS_MANIFEST from `key = value` lines. Comments (#) and blanks ignored.
# Values are taken verbatim and never executed: shell metacharacters stay inert.
manifest::parse() {
	local file="$1" line key val
	[[ -f "$file" ]] || { ui::error "manifest not found: $file"; return 1; }
	BS_MANIFEST=()
	while IFS= read -r line || [[ -n "$line" ]]; do
		line="${line%$'\r'}"                       # tolerate CRLF
		[[ -z "${line//[[:space:]]/}" ]] && continue
		[[ "$(manifest::_trim "$line")" == \#* ]] && continue
		[[ "$line" != *=* ]] && continue
		key="$(manifest::_trim "${line%%=*}")"
		val="$(manifest::_trim "${line#*=}")"
		[[ -n "$key" ]] && BS_MANIFEST["$key"]="$val"
	done < "$file"
}

# manifest::validate
# Ensures required fields are present and the name is a safe slug.
manifest::validate() {
	local k missing=()
	for k in name version arch os exec; do
		[[ -n "${BS_MANIFEST[$k]:-}" ]] || missing+=("$k")
	done
	if ((${#missing[@]})); then
		ui::error "manifest is missing required field(s): ${missing[*]}"
		return 1
	fi
	if [[ ! "${BS_MANIFEST[name]}" =~ ^[a-z0-9][a-z0-9._-]*$ ]]; then
		ui::error "invalid name '${BS_MANIFEST[name]}' (use lowercase a-z0-9._-)"
		return 1
	fi
}
