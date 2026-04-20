#!/usr/bin/env bash

# ==============================================================
# TOOL        : collect-commands
# DESCRIPTION : Collects diagnostic information from the system.
# AUTHOR      : Lucas Cruz
# CREATED     : 2026-04-20
# VERSION     : 0.0.1
# ==============================================================

set -uo pipefail

FULL_TOOLNAME="Diagnose Toolkit - Command Collector"
TOOLNAME="collect-commands"
VERSION="0.0.1"

MODE="${1:-full}"
OUTPUTDIR="${2:-}"

TIMESTAMP="$(date +%Y%m%d_%H%M%S)"
HOST="$(hostname -s 2>/dev/null || hostname)"
OS="$(awk -F '"' '/^PRETTY_NAME=/{print $2}' /etc/os-release 2>/dev/null)"

COMMANDS_ROOT="${OUTPUTDIR}/commands"
STATUSLOG="${OUTPUTDIR}/logs/command-status.log"
SUMMARY="${OUTPUTDIR}/meta/commands-summary.txt"

GREEN="\033[0;32m"
RED="\033[0;31m"
YELLOW="\033[1;33m"
WHITE="\033[1;37m"
COLOR_END="\033[0m"

if [[ ${EUID} -ne 0 ]]; then
    echo "This script must be run as root" >&2
    exit 1
fi

print_help() {
    cat <<EOF
Usage: $0 [profile] [outputdir]

Profiles:
  basic
  full
  cluster
  gpu
  packages
  network
  storage

Options:
  -v, --version         Show version
  -h, --help            Show this help
  --list-profiles       List available profiles

Examples:
  $0 full /tmp/diagnose-toolkit_host_20260420_180000
  $0 cluster /var/tmp/diag_out
EOF
}

print_profiles() {
    cat <<EOF
Available profiles:
  basic     - Minimal diagnostic collection
  full      - Full diagnostic collection
  cluster   - HPC/cluster focused collection
  gpu       - GPU focused collection
  packages  - Packages/modules focused collection
  network   - Network focused collection
  storage   - Storage focused collection
EOF
}

if [[ "${MODE}" == "-h" || "${MODE}" == "--help" ]]; then
    print_help
    exit 0
fi

if [[ "${MODE}" == "--list-profiles" ]]; then
    print_profiles
    exit 0
fi

if [[ "${MODE}" == "-v" || "${MODE}" == "--version" ]]; then
    echo "${FULL_TOOLNAME} :: version ${VERSION}"
    exit 0
fi

if [[ -z "${OUTPUTDIR}" ]]; then
    echo "Usage: $0 [profile] [outputdir]" >&2
    exit 1
fi

mkdir -p "${COMMANDS_ROOT}"/{meta,hardware,network,storage,security,packages,cluster}
mkdir -p "${OUTPUTDIR}/logs" "${OUTPUTDIR}/meta"
: > "${STATUSLOG}"

printf "\n======================================================\n"
echo "= Toolkit        : ${FULL_TOOLNAME}"
echo "= Version        : ${VERSION}"
echo "= Hostname       : ${HOST}"
echo "= Operating Sys. : ${OS:-Unknown}"
echo "= Date           : $(date)"
echo "= Profile        : ${MODE}"
printf "======================================================\n\n"

cat > "${OUTPUTDIR}/meta/commands-tool-info.txt" <<EOF
TOOLNAME=${TOOLNAME}
FULL_TOOLNAME=${FULL_TOOLNAME}
VERSION=${VERSION}
HOST=${HOST}
TIMESTAMP=${TIMESTAMP}
OS=${OS:-Unknown}
PROFILE=${MODE}
EOF

log_status() {
    local rc="$1"
    local cmd="$2"
    local outfile="$3"
    local extra="${4:-}"
    local status="FAIL"

    if [[ "${rc}" -eq 0 ]]; then
        status="OK"
    elif [[ "${rc}" -eq 127 ]]; then
        status="SKIP"
    fi

    printf '%s | %-4s | %s | %s' \
        "$(date --iso-8601=seconds)" \
        "${status}" \
        "${cmd}" \
        "${outfile}" >> "${STATUSLOG}"

    if [[ -n "${extra}" ]]; then
        printf ' | %s' "${extra}" >> "${STATUSLOG}"
    fi

    printf '\n' >> "${STATUSLOG}"
}

command_exists_for_entry() {
    local cmd="$1"
    local first_word

    first_word="$(awk '{print $1}' <<< "${cmd}")"

    case "${first_word}" in
        ulimit|mount)
            return 0
            ;;
    esac

    command -v "${first_word}" >/dev/null 2>&1
}

run_cmd() {
    local category="$1"
    local name="$2"
    local cmd="$3"

    local filepath="${COMMANDS_ROOT}/${category}/${name}.txt"
    local rc=0

    if ! command_exists_for_entry "${cmd}"; then
        {
            echo "# CATEGORY: ${category}"
            echo "# NAME: ${name}"
            echo "# COMMAND: ${cmd}"
            echo "# DATE: $(date --iso-8601=seconds)"
            echo
            echo "Command not found: $(awk '{print $1}' <<< "${cmd}")"
        } > "${filepath}"

        log_status 127 "${cmd}" "${filepath}" "rc=127"
        echo -e "${WHITE}[${COLOR_END}${YELLOW}SKIP${COLOR_END}${WHITE}] ${category}/${name} :: command not found${COLOR_END}"
        return 0
    fi

    {
        echo "# CATEGORY: ${category}"
        echo "# NAME: ${name}"
        echo "# COMMAND: ${cmd}"
        echo "# DATE: $(date --iso-8601=seconds)"
        echo
        bash -c "${cmd}"
    } > "${filepath}" 2>&1 || rc=$?

    log_status "${rc}" "${cmd}" "${filepath}" "rc=${rc}"

    if [[ "${rc}" -ne 0 ]]; then
        echo -e "${WHITE}[${COLOR_END}${RED}FAIL${COLOR_END}${WHITE}] ${category}/${name} :: ${cmd}${COLOR_END}"
    else
        echo -e "${WHITE}[${COLOR_END} ${GREEN}OK${COLOR_END}${WHITE} ] ${category}/${name}${COLOR_END}"
    fi
}

load_basic_profile() {
    commands=(
        "meta|hostname|hostname"
        "meta|uptime_since|uptime -s"
        "meta|uname|uname -a"
        "meta|hostnamectl|hostnamectl"
        "meta|timedatectl|timedatectl"

        "hardware|lscpu|lscpu"
        "hardware|lsmem|lsmem"
        "hardware|free|free -h"

        "storage|df|df -h"
        "storage|lsblk|lsblk"
        "storage|mount|mount"

        "network|ip_address|ip a"
        "network|ip_route|ip r"
        "network|ss_tulpn|ss -tulpn"

        "security|sestatus|sestatus -v"
    )
}

load_full_profile() {
    commands=(
        "meta|hostname|hostname"
        "meta|uptime_since|uptime -s"
        "meta|uname|uname -a"
        "meta|hostnamectl|hostnamectl"
        "meta|timedatectl|timedatectl"
        "meta|ulimit|ulimit -a"

        "hardware|lscpu|lscpu"
        "hardware|lsmem|lsmem"
        "hardware|free|free -h"
        "hardware|nvidia_smi|nvidia-smi"

        "storage|df|df -h"
        "storage|lsblk|lsblk"
        "storage|fdisk|fdisk -l"
        "storage|multipath|multipath -l"
        "storage|mount|mount"
        "storage|sys_block|ls -lisa /sys/block/*"

        "network|ip_address|ip a"
        "network|ip_route|ip r"
        "network|ss_tulpn|ss -tulpn"
        "network|ibstat|ibstat"
        "network|ofed_info|ofed_info | head -1"

        "security|sestatus|sestatus -v"

        "packages|yum_installed|yum list installed"
        "packages|rpm_qa|rpm -qa"
        "packages|yum_history|yum history"
        "packages|module_avail|source /etc/profile >/dev/null 2>&1; module avail"

        "cluster|pcs_status|pcs status"
    )
}

load_cluster_profile() {
    commands=(
        "meta|hostname|hostname"
        "meta|uname|uname -a"
        "meta|hostnamectl|hostnamectl"
        "meta|timedatectl|timedatectl"

        "hardware|lscpu|lscpu"
        "hardware|lsmem|lsmem"
        "hardware|free|free -h"

        "storage|df|df -h"
        "storage|lsblk|lsblk"
        "storage|fdisk|fdisk -l"
        "storage|multipath|multipath -l"
        "storage|mount|mount"
        "storage|sys_block|ls -lisa /sys/block/*"

        "network|ip_address|ip a"
        "network|ip_route|ip r"
        "network|ss_tulpn|ss -tulpn"
        "network|ibstat|ibstat"
        "network|ofed_info|ofed_info | head -1"

        "cluster|pcs_status|pcs status"
        "packages|module_avail|source /etc/profile >/dev/null 2>&1; module avail"
    )
}

load_gpu_profile() {
    commands=(
        "meta|hostname|hostname"
        "meta|uname|uname -a"

        "hardware|lscpu|lscpu"
        "hardware|lsmem|lsmem"
        "hardware|free|free -h"
        "hardware|nvidia_smi|nvidia-smi"

        "packages|rpm_qa|rpm -qa"
        "packages|module_avail|source /etc/profile >/dev/null 2>&1; module avail"
    )
}

load_packages_profile() {
    commands=(
        "meta|hostname|hostname"
        "meta|uname|uname -a"

        "packages|yum_installed|yum list installed"
        "packages|rpm_qa|rpm -qa"
        "packages|yum_history|yum history"
        "packages|module_avail|source /etc/profile >/dev/null 2>&1; module avail"
    )
}

load_network_profile() {
    commands=(
        "meta|hostname|hostname"
        "meta|uname|uname -a"

        "network|ip_address|ip a"
        "network|ip_route|ip r"
        "network|ss_tulpn|ss -tulpn"
        "network|ibstat|ibstat"
        "network|ofed_info|ofed_info | head -1"
    )
}

load_storage_profile() {
    commands=(
        "meta|hostname|hostname"
        "meta|uname|uname -a"

        "storage|df|df -h"
        "storage|lsblk|lsblk"
        "storage|fdisk|fdisk -l"
        "storage|multipath|multipath -l"
        "storage|mount|mount"
        "storage|sys_block|ls -lisa /sys/block/*"
    )
}

commands=()
case "${MODE}" in
    basic)    load_basic_profile ;;
    full)     load_full_profile ;;
    cluster)  load_cluster_profile ;;
    gpu)      load_gpu_profile ;;
    packages) load_packages_profile ;;
    network)  load_network_profile ;;
    storage)  load_storage_profile ;;
    *)
        echo "Invalid profile: ${MODE}" >&2
        exit 1
        ;;
esac

OK_COUNT=0
FAIL_COUNT=0
SKIP_COUNT=0

for entry in "${commands[@]}"; do
    IFS='|' read -r category name cmd <<< "${entry}"

    before_lines=0
    [[ -f "${STATUSLOG}" ]] && before_lines="$(wc -l < "${STATUSLOG}")"

    run_cmd "${category}" "${name}" "${cmd}"

    after_lines=0
    [[ -f "${STATUSLOG}" ]] && after_lines="$(wc -l < "${STATUSLOG}")"

    if [[ "${after_lines}" -gt "${before_lines}" ]]; then
        last_status="$(tail -n 1 "${STATUSLOG}")"
        if grep -q ' | OK[[:space:]]*|' <<< "${last_status}"; then
            ((OK_COUNT+=1))
        elif grep -q ' | SKIP[[:space:]]*|' <<< "${last_status}" || grep -q 'rc=127' <<< "${last_status}"; then
            ((SKIP_COUNT+=1))
        else
            ((FAIL_COUNT+=1))
        fi
    fi
done

cat > "${SUMMARY}" <<EOF
Toolkit        : ${FULL_TOOLNAME}
Version        : ${VERSION}
Hostname       : ${HOST}
Operating Sys. : ${OS:-Unknown}
Date           : $(date)
Profile        : ${MODE}

Commands OK    : ${OK_COUNT}
Commands FAIL  : ${FAIL_COUNT}
Commands SKIP  : ${SKIP_COUNT}
EOF

echo
echo "Commands root    : ${COMMANDS_ROOT}"
echo "Status log       : ${STATUSLOG}"
echo "Summary          : ${SUMMARY}"
echo
echo "Commands OK      : ${OK_COUNT}"
echo "Commands FAIL    : ${FAIL_COUNT}"
echo "Commands SKIP    : ${SKIP_COUNT}"