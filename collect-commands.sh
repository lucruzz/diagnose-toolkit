#!/usr/bin/env bash

# ==============================================================
# TOOL: diagnose-toolkit
# DESCRIPTION: Collects diagnostic information from the system.
# AUTHOR: Lucas Cruz
# CREATED: 2026-04-20
# VERSION: 0.0.2
# ==============================================================

set -uo pipefail

FULL_TOOLNAME="Diagnose Toolkit"
TOOLNAME="diagnose-toolkit"
VERSION="0.0.2"

TIMESTAMP="$(date +%Y%m%d_%H%M%S)"
HOST="$(hostname -s 2>/dev/null || hostname)"
OUTPUTDIR="${TOOLNAME}_${HOST}_${TIMESTAMP}"
ARCHIVE="${OUTPUTDIR}.tar.gz"
OS="$(awk -F '"' '/^PRETTY_NAME=/{print $2}' /etc/os-release 2>/dev/null)"
STATUSLOG="${OUTPUTDIR}/logs/command-status.log"

MODE="${1:-full}"
OUTPUTDIR="${2:-}"

GREEN="\033[0;32m"
RED="\033[0;31m"
WHITE="\033[1;37m"
COLOR_END="\033[0m"

if [[ ${EUID} -ne 0 ]]; then
    echo "This script must be run as root" >&2
    exit 1
fi

print_help() {
    cat <<EOF
Usage: $0 [profile] [options]

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
  --no-archive          Do not create tar.gz archive

Examples:
  $0
  $0 basic
  $0 cluster --no-archive
  $0 gpu
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

while [[ $# -gt 0 ]]; do
    case "$1" in
        basic|full|cluster|gpu|packages|network|storage)
            MODE="$1"
            shift
            ;;
        --list-profiles)
            print_profiles
            exit 0
            ;;
        -v|--version)
            echo "${FULL_TOOLNAME} :: version ${VERSION}"
            exit 0
            ;;
        -h|--help)
            print_help
            exit 0
            ;;
        *)
            echo "Unknown argument: $1" >&2
            echo
            print_help
            exit 1
            ;;
    esac
done

mkdir -p "${OUTPUTDIR}"/{meta,hardware,network,storage,security,packages,cluster,logs}

printf "\n======================================================\n"
echo "= Toolkit        : ${FULL_TOOLNAME}"
echo "= Version        : ${VERSION}"
echo "= Hostname       : ${HOST}"
echo "= Operating Sys. : ${OS:-Unknown}"
echo "= Date           : $(date)"
echo "= Profile        : ${MODE}"
printf "======================================================\n\n"

cat > "${OUTPUTDIR}/meta/tool-info.txt" <<EOF
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

    local filepath="${OUTPUTDIR}/${category}/${name}.txt"
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
        echo "[SKIP] ${category}/${name} :: command not found"
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
        # echo "[FAIL] ${category}/${name} :: ${cmd}"
        echo -e "${WHITE}[${COLOR_END}${RED}FAIL${COLOR_END}${WHITE}] ${category}/${name} :: ${cmd}${COLOR_END}"
    else
        # echo "[ OK ] ${category}/${name}"
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
        "packages|module_avail|module avail"

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
        "packages|module_avail|module avail"
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
        "packages|module_avail|module avail"
    )
}

load_packages_profile() {
    commands=(
        "meta|hostname|hostname"
        "meta|uname|uname -a"

        "packages|yum_installed|yum list installed"
        "packages|rpm_qa|rpm -qa"
        "packages|yum_history|yum history"
        "packages|module_avail|module avail"
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

    # before_lines="$(wc -l < "${STATUSLOG}" 2>/dev/null || echo 0)"
    before_lines=0
    [[ -f "${STATUSLOG}" ]] && before_lines="$(wc -l < "${STATUSLOG}")"


    run_cmd "${category}" "${name}" "${cmd}"
    # after_lines="$(wc -l < "${STATUSLOG}" 2>/dev/null || echo 0)"
    after_lines=0
    [[ -f "${STATUSLOG}" ]] && after_lines="$(wc -l < "${STATUSLOG}")"

    if [[ "${after_lines}" -gt "${before_lines}" ]]; then
        last_status="$(tail -n 1 "${STATUSLOG}")"
        if grep -q ' | OK[[:space:]]*|' <<< "${last_status}"; then
            ((OK_COUNT+=1))
        elif grep -q 'rc=127' <<< "${last_status}"; then
            ((SKIP_COUNT+=1))
        else
            ((FAIL_COUNT+=1))
        fi
    fi
done

cat > "${OUTPUTDIR}/meta/summary.txt" <<EOF
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

if [[ "${CREATE_ARCHIVE}" == "yes" ]]; then
    tar -czf "${ARCHIVE}" "${OUTPUTDIR}"
fi

echo
echo "Output directory : ${OUTPUTDIR}"
if [[ "${CREATE_ARCHIVE}" == "yes" ]]; then
    echo "Archive          : ${ARCHIVE}"
fi
echo "Status log       : ${STATUSLOG}"
echo "Summary          : ${OUTPUTDIR}/meta/summary.txt"
echo
echo "Commands OK      : ${OK_COUNT}"
echo "Commands FAIL    : ${FAIL_COUNT}"
echo "Commands SKIP    : ${SKIP_COUNT}"