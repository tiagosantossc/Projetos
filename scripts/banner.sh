#!/usr/bin/env bash
# Banner de login para servidores Linux Red Hat/Rocky/Alma e SUSE.
# O script somente exibe informacoes; nao altera o ambiente da sessao.

readonly RESET='\033[0m'
readonly RED='\033[1;31m'
readonly GREEN='\033[1;32m'
readonly YELLOW='\033[1;33m'
readonly CYAN='\033[1;36m'
readonly WHITE='\033[1;37m'
readonly DIM='\033[2m'

if [[ -t 1 ]]; then
    color() { printf '%b%s%b' "$1" "$2" "$RESET"; }
else
    color() { printf '%s' "$2"; }
fi

command_exists() {
    command -v "$1" >/dev/null 2>&1
}

value_or_unknown() {
    local value=${1:-}
    [[ -n "$value" ]] && printf '%s' "$value" || printf '%s' 'N/D'
}

get_os_name() {
    if [[ -r /etc/os-release ]]; then
        # shellcheck disable=SC1091
        . /etc/os-release
        printf '%s' "${PRETTY_NAME:-${NAME:-Linux}}"
    else
        printf '%s' 'Linux'
    fi
}

get_ip_addresses() {
    if command_exists ip; then
        ip -o -4 addr show up scope global 2>/dev/null \
            | awk '{sub(/\/.*/, "", $4); print $4}' \
            | paste -sd ', ' -
    fi
}

get_timezone() {
    if command_exists timedatectl; then
        timedatectl show --property=Timezone --value 2>/dev/null
    elif [[ -L /etc/localtime ]]; then
        readlink /etc/localtime | sed 's#^.*/zoneinfo/##'
    fi
}

get_virtualization() {
    if command_exists systemd-detect-virt; then
        local virt
        virt=$(systemd-detect-virt 2>/dev/null || true)
        [[ -z "$virt" || "$virt" == 'none' ]] && printf '%s' 'Fisico' || printf 'Virtual (%s)' "$virt"
    elif [[ -r /sys/class/dmi/id/product_name ]]; then
        printf '%s' "Virtual/Indefinido ($(cat /sys/class/dmi/id/product_name 2>/dev/null))"
    else
        printf '%s' 'Indefinido'
    fi
}

get_memory() {
    if command_exists free; then
        free -h 2>/dev/null | awk '/^Mem:/ {printf "%s total | %s usado | %s livre", $2, $3, $4}'
    fi
}

get_memory_usage_percent() {
    if [[ -r /proc/meminfo ]]; then
        awk '
            /^MemTotal:/ {total = $2}
            /^MemAvailable:/ {available = $2}
            END {
                if (total > 0) printf "%d", ((total - available) / total) * 100
                else print "N/D"
            }
        ' /proc/meminfo
    else
        printf '%s' 'N/D'
    fi
}

get_swap() {
    if command_exists free; then
        free -h 2>/dev/null | awk '/^Swap:/ {printf "%s total | %s usado | %s livre", $2, $3, $4}'
    fi
}

get_disk_alerts() {
    if command_exists df; then
        df -PTh 2>/dev/null | awk '
            NR > 1 && $1 !~ /^(tmpfs|devtmpfs|proc|sysfs|cgroup|cgroup2|overlay|squashfs)$/ && $6 ~ /^[0-9]+%$/ {
                usage = $6 + 0
                if (usage >= 85) {
                    printf "%s %s usado (%s livres); ", $7, $6, $5
                    found = 1
                }
            }
            END {
                if (!found) print "OK - nenhum filesystem acima de 85%"
            }
        '
    fi
}

get_inode_alerts() {
    if command_exists df; then
        df -PThi 2>/dev/null | awk '
            NR > 1 && $1 !~ /^(tmpfs|devtmpfs|proc|sysfs|cgroup|cgroup2|overlay|squashfs)$/ && $6 ~ /^[0-9]+%$/ {
                usage = $6 + 0
                if (usage >= 85) {
                    printf "%s %s usados (%s livres); ", $7, $6, $5
                    found = 1
                }
            }
            END {
                if (!found) print "OK - nenhum filesystem com inodes acima de 85%"
            }
        '
    fi
}

get_disk_io() {
    if [[ -r /proc/diskstats ]]; then
        local devices=''
        if command_exists lsblk; then
            devices=$(lsblk -dn -o NAME 2>/dev/null | paste -sd ' ' -)
        fi

        awk -v devices="$devices" '
            BEGIN {
                split(devices, selected, " ")
                for (item in selected) {
                    if (selected[item] != "") disks[selected[item]] = 1
                }
            }
            {
                name = $3
                if ((length(devices) > 0 && !(name in disks)) || name ~ /^(loop|ram|fd|sr|dm-|md)/) next
                reads += $4
                read_sectors += $6
                writes += $8
                write_sectors += $10
                io_ms += $13
                found = 1
            }
            END {
                if (!found) {
                    print "N/D"
                } else {
                    printf "leituras %d | escritas %d | transferido %.1f MB | tempo I/O %d ms (acumulado)", reads, writes, (read_sectors + write_sectors) / 2048, io_ms
                }
            }
        ' /proc/diskstats
    fi
}

get_io_pressure() {
    if [[ -r /proc/pressure/io ]]; then
        awk '/^some / {some = $2 " " $3 " " $4} /^full / {full = $2 " " $3 " " $4} END {printf "some [%s] | full [%s] (avg10 avg60 avg300)", some, full}' /proc/pressure/io
    elif [[ -r /proc/stat ]]; then
        local iowait user_hz
        iowait=$(awk '/^cpu / {print $6; exit}' /proc/stat)
        user_hz=$(getconf CLK_TCK 2>/dev/null || printf '100')
        if [[ "$iowait" =~ ^[0-9]+$ && "$user_hz" =~ ^[0-9]+$ && "$user_hz" -gt 0 ]]; then
            awk -v ticks="$iowait" -v hz="$user_hz" 'BEGIN {printf "iowait %.1fs acumulado (PSI indisponivel)", ticks / hz}'
        fi
    fi
}

get_io_status() {
    if [[ -r /proc/pressure/io ]]; then
        local avg10
        avg10=$(awk '/^some / {for (i = 1; i <= NF; i++) if ($i ~ /^avg10=/) {sub("avg10=", "", $i); print $i; exit}}' /proc/pressure/io)
        awk -v pressure="${avg10:-0}" 'BEGIN {exit !(pressure >= 10)}'
        [[ $? -eq 0 ]] && printf '%s' 'problem' || printf '%s' 'ok'
    else
        printf '%s' 'ok'
    fi
}

get_zombie_count() {
    if [[ -r /proc ]]; then
        local count
        count=$(ps -eo stat= 2>/dev/null | awk '$1 ~ /^Z/ {total++} END {print total + 0}')
        [[ "$count" =~ ^[0-9]+$ ]] && printf '%s' "$count" || printf '%s' 'N/D'
    fi
}

get_network_health() {
    if [[ -r /proc/net/dev ]]; then
        awk -F'[: ]+' '
            NR > 2 && $2 != "lo" && $2 != "" {
                rx += $3; rx_errors += $5; rx_dropped += $6
                tx += $11; tx_errors += $13; tx_dropped += $14
                interfaces++
            }
            END {
                if (interfaces == 0) {
                    print "N/D"
                } else {
                    printf "%d iface(s) | RX %s | TX %s | erros %d/%d | drops %d/%d", interfaces, human(rx), human(tx), rx_errors, tx_errors, rx_dropped, tx_dropped
                }
            }
            function human(bytes) {
                if (bytes >= 1073741824) return sprintf("%.1fG", bytes / 1073741824)
                if (bytes >= 1048576) return sprintf("%.1fM", bytes / 1048576)
                if (bytes >= 1024) return sprintf("%.1fK", bytes / 1024)
                return sprintf("%dB", bytes)
            }
        ' /proc/net/dev
    fi
}

get_patch_count() {
    local cache_file=/var/cache/porto-banner/updates
    local count=''

    if [[ -r "$cache_file" ]]; then
        IFS='|' read -r count _ < "$cache_file"
        [[ "$count" =~ ^[0-9]+$ ]] && printf '%s' "$count" && return
    fi

    printf '%s' 'N/D - cache ainda nao atualizado'
}

get_last_os_update() {
    local cache_file=/var/cache/porto-banner/updates
    local count last_update

    if [[ -r "$cache_file" ]]; then
        IFS='|' read -r count last_update < "$cache_file"
        [[ -n "$last_update" ]] && printf '%s' "$last_update" && return
    fi

    printf '%s' 'N/D - cache ainda nao atualizado'
}

get_last_reboot() {
    if command_exists uptime; then
        local boot_time
        boot_time=$(uptime -s 2>/dev/null)
        [[ -n "$boot_time" ]] && printf '%s' "$boot_time" && return
    fi

    if command_exists who; then
        who -b 2>/dev/null | sed 's/^[^ ]*[[:space:]]*//'
    else
        printf '%s' 'N/D'
    fi
}

get_load() {
    if [[ -r /proc/loadavg ]]; then
        awk '{print $1 ", " $2 ", " $3 " (1, 5, 15 min)"}' /proc/loadavg
    elif command_exists uptime; then
        uptime
    fi
}

get_load_status() {
    if [[ -r /proc/loadavg ]]; then
        local load_one cpu_count
        load_one=$(awk '{print $1}' /proc/loadavg)
        cpu_count=$(getconf _NPROCESSORS_ONLN 2>/dev/null || printf '1')
        awk -v load_value="$load_one" -v cpus="$cpu_count" 'BEGIN {exit !(load_value >= cpus * 0.85)}'
        [[ $? -eq 0 ]] && printf '%s' 'problem' || printf '%s' 'ok'
    else
        printf '%s' 'ok'
    fi
}

get_uptime() {
    if [[ -r /proc/uptime ]]; then
        awk '{
            total = int($1)
            days = int(total / 86400)
            hours = int((total % 86400) / 3600)
            minutes = int((total % 3600) / 60)
            seconds = total % 60
            if (days > 0) printf "%d dias, %02dh%02dm%02ds", days, hours, minutes, seconds
            else printf "%02dh%02dm%02ds", hours, minutes, seconds
        }' /proc/uptime
    elif command_exists uptime; then
        uptime
    fi
}

print_line() {
    local label=$1
    local value=$2
    printf '  %b%-22s%b %b%s%b\n' "$WHITE" "$label" "$RESET" "$GREEN" "$(value_or_unknown "$value")" "$RESET"
}

print_status_line() {
    local label=$1
    local value=$2
    local status=$3
    local status_color=$RED

    [[ "$status" == 'ok' ]] && status_color=$GREEN
    printf '  %b%-22s%b %b%s%b\n' "$WHITE" "$label" "$RESET" "$status_color" "$(value_or_unknown "$value")" "$RESET"
}

# Carrega identificadores da distribuicao sem assumir uma familia especifica.
ID='unknown'
ID_LIKE=''
PRETTY_NAME=''
if [[ -r /etc/os-release ]]; then
    # shellcheck disable=SC1091
    . /etc/os-release
fi

OS_FAMILY='unknown'
case "$ID $ID_LIKE" in
    *sles*|*suse*|*opensuse*) OS_FAMILY='suse' ;;
    *rhel*|*rocky*|*almalinux*|*centos*|*fedora*|*oracle*) OS_FAMILY='rpm' ;;
esac

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    PORTO_CHECK_UPDATES=${PORTO_CHECK_UPDATES:-1}
else
    PORTO_CHECK_UPDATES=${PORTO_CHECK_UPDATES:-0}
fi

OS_NAME=$(get_os_name)
HOSTNAME_VALUE=$(hostname -s 2>/dev/null || uname -n)
IP_ADDRESSES=$(get_ip_addresses)
TIMEZONE=$(get_timezone)
VIRTUALIZATION=$(get_virtualization)
UPTIME_VALUE=$(get_uptime)
LOAD_VALUE=$(get_load)
MEMORY_VALUE=$(get_memory)
SWAP_VALUE=$(get_swap)
DISK_ALERTS=$(get_disk_alerts)
INODE_ALERTS=$(get_inode_alerts)
DISK_IO=$(get_disk_io)
IO_PRESSURE=$(get_io_pressure)
ZOMBIE_COUNT=$(get_zombie_count)
NETWORK_HEALTH=$(get_network_health)
LAST_REBOOT=$(get_last_reboot)
KERNEL=$(uname -r 2>/dev/null)
CPU_COUNT=$(getconf _NPROCESSORS_ONLN 2>/dev/null || printf '%s' 'N/D')
CPU_MODEL=$(awk -F': ' '/^model name/ {print $2; exit}' /proc/cpuinfo 2>/dev/null)
MEMORY_USAGE_PERCENT=$(get_memory_usage_percent)
LOAD_STATUS=$(get_load_status)
IO_STATUS=$(get_io_status)

printf '\n'
color "$CYAN" '============================================================'; printf '\n'
color "$CYAN" '              PORTO | UNIX / LINUX / CLOUD'; printf '\n'
color "$CYAN" '============================================================'; printf '\n'
color "$RED" '  ATENCAO: siga o processo de mudanca antes de alterar o servidor.'; printf '\n'
printf '\n'

print_line 'HOSTNAME' "$HOSTNAME_VALUE"
print_line 'IP(S)' "$IP_ADDRESSES"
print_line 'SISTEMA OPERACIONAL' "$OS_NAME"
print_line 'KERNEL' "$KERNEL"
print_line 'TIPO' "$VIRTUALIZATION"
print_line 'DATA / TIMEZONE' "$(date '+%d/%m/%Y %H:%M:%S') / $(value_or_unknown "$TIMEZONE")"
print_line 'UPTIME' "$UPTIME_VALUE"
print_line 'CPU' "${CPU_MODEL:-N/D} (${CPU_COUNT} core(s))"
print_status_line 'LOAD AVERAGE' "$LOAD_VALUE" "$LOAD_STATUS"
if [[ "$MEMORY_USAGE_PERCENT" =~ ^[0-9]+$ && "$MEMORY_USAGE_PERCENT" -lt 85 ]]; then
    print_status_line 'MEMORIA' "$MEMORY_VALUE (${MEMORY_USAGE_PERCENT}% usado)" 'ok'
else
    print_status_line 'MEMORIA' "$MEMORY_VALUE (${MEMORY_USAGE_PERCENT}% usado)" 'problem'
fi
print_line 'SWAP' "$SWAP_VALUE"
if [[ "$DISK_ALERTS" == OK* ]]; then
    print_status_line 'DISCO > 85%' "$DISK_ALERTS" 'ok'
else
    print_status_line 'DISCO > 85%' "$DISK_ALERTS" 'problem'
fi
if [[ "$INODE_ALERTS" == OK* ]]; then
    print_status_line 'INODES > 85%' "$INODE_ALERTS" 'ok'
else
    print_status_line 'INODES > 85%' "$INODE_ALERTS" 'problem'
fi
if [[ "$DISK_ALERTS" == OK* && "$INODE_ALERTS" == OK* && "$IO_STATUS" == 'ok' ]]; then
    print_status_line 'DISK I/O' "$DISK_IO" 'ok'
    print_status_line 'IO PRESSURE' "$IO_PRESSURE" 'ok'
else
    print_status_line 'DISK I/O' "$DISK_IO" 'problem'
    print_status_line 'IO PRESSURE' "$IO_PRESSURE" 'problem'
fi
if [[ "$NETWORK_HEALTH" =~ erros[[:space:]]+0/0.*drops[[:space:]]+0/0 ]]; then
    print_status_line 'REDE' "$NETWORK_HEALTH" 'ok'
else
    print_status_line 'REDE' "$NETWORK_HEALTH" 'problem'
fi

if [[ "$ZOMBIE_COUNT" == '0' ]]; then
    print_status_line 'PROCESSOS ZUMBIS' '0' 'ok'
else
    print_status_line 'PROCESSOS ZUMBIS' "$ZOMBIE_COUNT - investigar processos pais" 'problem'
fi

PATCH_COUNT=$(get_patch_count)
LAST_OS_UPDATE=$(get_last_os_update)

if [[ "$PATCH_COUNT" == '0' ]]; then
    print_status_line 'UPDATES PENDENTES' '0 - sistema atualizado' 'ok'
else
    if [[ "$PATCH_COUNT" == N/D* ]]; then
        print_status_line 'UPDATES PENDENTES' "$PATCH_COUNT" 'problem'
    else
        print_status_line 'UPDATES PENDENTES' "$PATCH_COUNT pacote(s) disponivel(is)" 'problem'
    fi
fi
print_status_line 'ULTIMA ATUALIZACAO SO' "$LAST_OS_UPDATE" 'problem'
print_status_line 'ULTIMO REBOOT' "$LAST_REBOOT" 'problem'

printf '\n'
color "$DIM" "Banner informativo | $(date '+%d/%m/%Y %H:%M:%S')"; printf '\n'
printf '\n'

if [[ "${BASH_SOURCE[0]}" != "$0" ]]; then
    return 0
fi
