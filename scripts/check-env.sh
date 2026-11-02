#!/usr/bin/env bash
# Refuse to start with credentials that were published in earlier versions of
# this repo (or with none at all when the monitoring stack is started).
#
#   scripts/check-env.sh              # node only: reject known-public values
#   scripts/check-env.sh --monitoring # node + monitoring: also require values
#
# Values come from the environment (the Makefile exports .env) and fall back to
# reading .env directly, so the script also works when run by hand.
set -euo pipefail

monitoring=0
[[ "${1:-}" == "--monitoring" ]] && monitoring=1

# bcrypt hash of "canopy" that shipped as the default in older versions.
OLD_HASH='$2a$14$0IP2/ZvbwWQ0JsJp6B8IpOYxME/6KSuPY3l4Hpj8phNTMdjMdh8aa'

env_file="${ENV_FILE:-.env}"

# Last assignment of $1 in the .env file, if any.
from_file() {
	[[ -f "$env_file" ]] || return 0
	grep -E "^[[:space:]]*(export[[:space:]]+)?$1=" "$env_file" | tail -n1 | cut -d= -f2- || true
}

# Strip surrounding quotes and undo compose's $$ escaping.
normalize() {
	local v="$1"
	v="${v#\"}"; v="${v%\"}"
	v="${v#\'}"; v="${v%\'}"
	printf '%s' "${v//\$\$/\$}"
}

value() {
	local name="$1"
	if [[ -n "${!name+x}" ]]; then
		normalize "${!name}"
	else
		normalize "$(from_file "$name")"
	fi
}

errors=0
fail() {
	echo "ERROR: $*" >&2
	errors=$((errors + 1))
}

hash="$(value AUTH_PASSWORDHASH)"
gf_pass="$(value GF_ADMIN_PASSWORD)"

if [[ "$hash" == "$OLD_HASH" ]]; then
	fail "AUTH_PASSWORDHASH is the publicly known example hash (password \"canopy\"). Run 'make hash-password' and put the result in .env."
elif [[ $monitoring -eq 1 && -z "$hash" ]]; then
	fail "AUTH_PASSWORDHASH is empty. Run 'make hash-password' and put the result in .env."
fi

if [[ "$gf_pass" == "canopy" ]]; then
	fail "GF_ADMIN_PASSWORD is the publicly known default \"canopy\". Set a strong password in .env (see README \"Monitoring\" to change it in an existing Grafana)."
elif [[ $monitoring -eq 1 && -z "$gf_pass" ]]; then
	fail "GF_ADMIN_PASSWORD is empty. Set a strong password in .env."
fi

if [[ $errors -gt 0 ]]; then
	echo "Refusing to start. Fix .env and try again." >&2
	exit 1
fi
