#!/usr/bin/env bash

# ==============================================================
# TOOL        : diagnose-toolkit
# DESCRIPTION : Collects diagnostic information from the system.
# AUTHOR      : Lucas Cruz
# CREATED     : 2026-04-20
# VERSION     : 0.0.1
# ==============================================================

set -uo pipefail

FULL_TOOLNAME="Diagnose Toolkit"
TOOLNAME="diagnose-toolkit"
VERSION="0.0.1"

TIMESTAMP="$(date +%Y%m%d_%H%M%S)"
HOST="$(hostname -s 2>/dev/null || hostname)"
OUTPUTDIR="${TOOLNAME}_${HOST}_${TIMESTAMP}"
ARCHIVE="${OUTPUTDIR}.tar.gz"

OS="$(awk -F '"' '/^PRETTY_NAME=/{print $2}' /etc/os-release 2>/dev/null)"
STATUSLOG="${OUTPUTDIR}/logs/command-status.log"

GREEN="\033[0;32m"
RED="\033[0;31m"
WHITE="\033[1;37m"
COLOR_END="\033[0m"

if [[ ${EUID} -ne 0 ]]; then
    echo "This script must be run as root" >&2
    exit 1
fi

if [[ "${1:-}" == "--version" || "${1:-}" == "-v" ]]; then
    echo "${FULL_TOOLNAME} :: version ${VERSION}"
    exit 0
fi

mkdir -p "${OUTPUTDIR}"/{meta,hardware,network,storage,security,packages,cluster,logs}

echo -e ${YELLOW}
printf "\n======================================================\n"
echo "= Toolkit        : ${FULL_TOOLNAME}"
echo "= Version        : ${VERSION}"
echo "= Hostname       : ${HOST}"
echo "= Operating Sys. : ${OS:-Unknown}"
echo "= Date           : $(date)"
echo "= Profile        : ${MODE}"
printf "======================================================\n\n"
echo -e ${COLOR_END}

cat > "${OUTPUTDIR}/meta/tool-info.txt" <<EOF
TOOLNAME=${TOOLNAME}
FULL_TOOLNAME=${FULL_TOOLNAME}
VERSION=${VERSION}
HOST=${HOST}
TIMESTAMP=${TIMESTAMP}
OS=${OS:-Unknown}
EOF

# Formato:
# "categoria|nome_arquivo|comando"
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

log_status() {
    local rc="$1"
    local cmd="$2"
    local outfile="$3"
    local extra="${4:-}"
    local status="FAIL"

    if [[ "${rc}" -eq 0 ]]; then
        status="OK"
    fi

    printf '%s | %-4s | %s\t | %s' \
        "$(date --iso-8601=seconds)" \
        "${status}" \
        "${cmd}" \
        "${outfile}" >> "${STATUSLOG}"

    if [[ -n "${extra}" ]]; then
        printf ' | %s' "${extra}" >> "${STATUSLOG}"
    fi

    printf '\n' >> "${STATUSLOG}"
}

run_cmd() {
    local category="$1"
    local name="$2"
    local cmd="$3"

    local filepath="${OUTPUTDIR}/${category}/${name}.txt"
    local rc=0

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

for entry in "${commands[@]}"; do
    IFS='|' read -r category name cmd <<< "${entry}"
    run_cmd "${category}" "${name}" "${cmd}"
done

tar -czf "${ARCHIVE}" "${OUTPUTDIR}"

echo
echo "Output directory : ${OUTPUTDIR}"
echo "Archive          : ${ARCHIVE}"
echo "Status log       : ${STATUSLOG}"
