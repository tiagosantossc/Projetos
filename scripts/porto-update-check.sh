#!/usr/bin/env bash

set -u

readonly CACHE_FILE=${PORTO_UPDATE_CACHE:-/var/cache/porto-banner/updates}
readonly TIMEOUT_SECONDS=${PORTO_UPDATE_TIMEOUT:-60}
readonly CACHE_DIR=${CACHE_FILE%/*}

command_exists() {
	command -v "$1" >/dev/null 2>&1
}

ID='unknown'
ID_LIKE=''
if [[ -r /etc/os-release ]]; then
	# shellcheck disable=SC1091
	. /etc/os-release
fi

OS_FAMILY='unknown'
case "$ID $ID_LIKE" in
	*sles*|*suse*|*opensuse*) OS_FAMILY='suse' ;;
	*rhel*|*rocky*|*almalinux*|*centos*|*fedora*|*oracle*) OS_FAMILY='rpm' ;;
esac

count=''
status=0
output=''
last_update='N/D'

if ! command_exists timeout; then
	printf 'timeout nao encontrado\n' >&2
	exit 1
fi

case "$OS_FAMILY" in
	rpm)
		if command_exists dnf; then
			output=$(LC_ALL=C timeout --signal=TERM "${TIMEOUT_SECONDS}s" dnf -q list --upgrades 2>/dev/null) || status=$?
			last_update=$(LC_ALL=C timeout --signal=TERM 5s dnf -q history info last 2>/dev/null \
				| awk -F': ' 'tolower($1) ~ /^(start|begin)/ {print $2; exit}')
		elif command_exists yum; then
			output=$(LC_ALL=C timeout --signal=TERM "${TIMEOUT_SECONDS}s" yum -q check-update 2>/dev/null) || status=$?
			last_update=$(LC_ALL=C timeout --signal=TERM 5s yum -q history info last 2>/dev/null \
				| awk -F': ' 'tolower($1) ~ /^(start|begin)/ {print $2; exit}')
		fi
		if [[ "$status" -eq 0 || "$status" -eq 100 ]]; then
			count=$(printf '%s\n' "$output" \
				| awk 'NF >= 3 && $1 !~ /^(Installed|Available|Loaded|Last|Obsoleting|Updating|Security:)/ {total++} END {print total + 0}')
		fi
		;;
	suse)
		if command_exists zypper; then
			output=$(LC_ALL=C timeout --signal=TERM "${TIMEOUT_SECONDS}s" zypper --non-interactive --quiet list-updates 2>/dev/null) || status=$?
			count=$(printf '%s\n' "$output" \
				| awk -F'|' '/^[[:space:]]*[v>][[:space:]]*\|/ {total++} END {print total + 0}')
			[[ -r /var/log/zypp/history ]] && last_update=$(awk -F'|' '$2 ~ /^(install|update|remove|patch|dup)/ {last = $1} END {print last}' /var/log/zypp/history)
		fi
		;;
esac

if [[ ! "$count" =~ ^[0-9]+$ ]]; then
	printf 'falha ao consultar updates (status %s)\n' "$status" >&2
	exit 1
fi

mkdir -p "$CACHE_DIR"
tmp_file=$(mktemp "${CACHE_FILE}.tmp.XXXXXX")
printf '%s|%s\n' "$count" "${last_update:-N/D}" > "$tmp_file"
chmod 0644 "$tmp_file"
mv -f "$tmp_file" "$CACHE_FILE"

printf 'Cache atualizado: %s update(s); ultima atualizacao: %s\n' "$count" "${last_update:-N/D}"