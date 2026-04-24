#!/usr/bin/env bash

# ==============================================================
# TOOL        : collect-logs
# DESCRIPTION : Collects system and service logs.
# AUTHOR      : Lucas Cruz
# CREATED     : 2026-04-24
# VERSION     : 0.0.1
# ==============================================================

set -uo pipefail

FULL_TOOLNAME="Diagnose Toolkit - Log Collector"
TOOLNAME="collect-logs"
VERSION="0.0.1"

MODE="${1:-full}"
OUTPUTDIR="${2:-}"

GREEN="\033[0;32m"
RED="\033[0;31m"
YELLOW="\033[1;33m"
WHITE="\033[1;37m"
COLOR_END="\033[0m"

if [[ ${EUID} -ne 0 ]]; then
    echo "This script must be run as root" >&2
    exit 1
fi

if [[ -z "${OUTPUTDIR}" ]]; then
    echo "Usage: $0 [profile] [outputdir]" >&2
    exit 1
fi

LOGS_ROOT="${OUTPUTDIR}/system-logs"
STATUSLOG="${OUTPUTDIR}/logs/log-status.log"
MANIFEST="${OUTPUTDIR}/meta/logs-manifest.txt"
SUMMARY="${OUTPUTDIR}/meta/logs-summary.txt"

mkdir -p "${LOGS_ROOT}" "${OUTPUTDIR}/logs" "${OUTPUTDIR}/meta"
: > "${STATUSLOG}"
: > "${MANIFEST}"

echo -e ${YELLOW}
printf "\n======================================================\n"
echo "= Toolkit        : ${FULL_TOOLNAME}"
echo "= Version        : ${VERSION}"
echo "= Operating Sys. : ${OS:-Unknown}"
echo "= Date           : $(date)"
echo "= Profile        : ${MODE}"
printf "======================================================\n\n"
echo -e ${COLOR_END}

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
EOF
}

print_profiles() {
    cat <<EOF
Available profiles:
  basic     - Minimal log collection
  full      - Full /var/log collection
  cluster   - HPC/cluster related logs
  gpu       - GPU related logs
  packages  - Package manager logs
  network   - Network/auth/system logs
  storage   - Storage related logs
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

log_status() {
    local rc="$1"
    local item="$2"
    local dest="$3"
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
        "${item}" \
        "${dest}" >> "${STATUSLOG}"

    if [[ -n "${extra}" ]]; then
        printf ' | %s' "${extra}" >> "${STATUSLOG}"
    fi

    printf '\n' >> "${STATUSLOG}"
}

copy_log_entry() {
    local match="$1"
    local relpath="${match#/}"
    local dest="${LOGS_ROOT}/${relpath}"
    local dest_parent
    local rc=0

    dest_parent="$(dirname "${dest}")"

    mkdir -p "${dest_parent}" || {
        log_status 1 "${match}" "${dest}" "failed to create destination directory"
        echo -e "${WHITE}[${COLOR_END}${RED}FAIL${COLOR_END}${WHITE}] ${match} :: mkdir failed${COLOR_END}"
        return 0
    }

    cp -a "${match}" "${dest}" 2>/dev/null || rc=$?

    if [[ "${rc}" -eq 0 ]]; then
        echo "${match}" >> "${MANIFEST}"
        log_status 0 "${match}" "${dest}"
        echo -e "${WHITE}[${COLOR_END} ${GREEN}OK${COLOR_END}${WHITE} ] ${match}${COLOR_END}"
    else
        log_status "${rc}" "${match}" "${dest}" "rc=${rc}"
        echo -e "${WHITE}[${COLOR_END}${RED}FAIL${COLOR_END}${WHITE}] ${match}${COLOR_END}"
    fi
}

collect_log_path() {
    local pattern="$1"
    local found=0

    while IFS= read -r match; do
        found=1
        copy_log_entry "${match}"
    done < <(compgen -G "${pattern}" || true)

    if [[ "${found}" -eq 0 ]]; then
        log_status 127 "${pattern}" "${LOGS_ROOT}" "no matches"
        echo -e "${WHITE}[${COLOR_END}${YELLOW}SKIP${COLOR_END}${WHITE}] ${pattern} :: no matches${COLOR_END}"
    fi
}

load_basic_logs() {
    logs=(
        "/var/log/messages"
        "/var/log/secure"
        "/var/log/dmesg"
        "/var/log/boot.log"
        "/var/log/cron"
    )
}

load_full_logs() {
    logs=(
        "/var/log/messages*"
        "/var/log/secure*"
        "/var/log/dmesg*"
        "/var/log/cron*"
        "/var/log/maillog*"
        "/var/log/spooler*"
        "/var/log/audit"
        "/var/log/journal"
        "/var/log/yum.log*"
        "/var/log/dnf*"
        "/var/log/hawkey.log*"
        "/var/log/slurm"
        "/var/log/slurm*"
        "/var/log/beegfs*"
        "/var/log/pacemaker"
        "/var/log/cluster"
        "/var/log/sssd"
        "/var/log/tuned"
        "/var/log/chrony"
        "/var/log/sa"
        "/var/log/gpu-manager*"
        "/var/log/nvidia*"
        "/var/log/aide"
    )
}

load_cluster_logs() {
    logs=(
        "/var/log/messages*"
        "/var/log/secure*"
        "/var/log/dmesg*"
        "/var/log/slurm"
        "/var/log/slurm*"
        "/var/log/beegfs*"
        "/var/log/pcsd"
        "/var/log/pacemaker"
        "/var/log/cluster"
        "/var/log/sssd"
        "/var/log/chrony"
        "/var/log/audit"
    )
}

load_gpu_logs() {
    logs=(
        "/var/log/messages*"
        "/var/log/dmesg*"
        "/var/log/secure*"
        "/var/log/gpu-manager*"
        "/var/log/nvidia*"
    )
}

load_packages_logs() {
    logs=(
        "/var/log/messages*"
        "/var/log/yum.log*"
        "/var/log/dnf*"
        "/var/log/hawkey.log*"
    )
}

load_network_logs() {
    logs=(
        "/var/log/messages*"
        "/var/log/secure*"
        "/var/log/sssd"
        "/var/log/chrony"
        "/var/log/audit"
    )
}

load_storage_logs() {
    logs=(
        "/var/log/messages*"
        "/var/log/dmesg*"
        "/var/log/multipath*"
        "/var/log/beegfs*"
        "/var/log/audit"
    )
}

logs=()
case "${MODE}" in
    basic)    load_basic_logs ;;
    full)     load_full_logs ;;
    cluster)  load_cluster_logs ;;
    gpu)      load_gpu_logs ;;
    packages) load_packages_logs ;;
    network)  load_network_logs ;;
    storage)  load_storage_logs ;;
    *)
        echo "Invalid profile: ${MODE}" >&2
        exit 1
        ;;
esac

OK_COUNT=0
FAIL_COUNT=0
SKIP_COUNT=0

for log_entry in "${logs[@]}"; do
    before_lines=0
    [[ -f "${STATUSLOG}" ]] && before_lines="$(wc -l < "${STATUSLOG}")"

    collect_log_path "${log_entry}"

    after_lines=0
    [[ -f "${STATUSLOG}" ]] && after_lines="$(wc -l < "${STATUSLOG}")"

    if [[ "${after_lines}" -gt "${before_lines}" ]]; then
        while IFS= read -r line; do
            if grep -q ' | OK[[:space:]]*|' <<< "${line}"; then
                ((OK_COUNT+=1))
            elif grep -q ' | SKIP[[:space:]]*|' <<< "${line}"; then
                ((SKIP_COUNT+=1))
            else
                ((FAIL_COUNT+=1))
            fi
        done < <(tail -n "$((after_lines - before_lines))" "${STATUSLOG}")
    fi
done

cat > "${SUMMARY}" <<EOF
Toolkit        : ${FULL_TOOLNAME}
Version        : ${VERSION}
Profile        : ${MODE}
Date           : $(date)

Logs OK        : ${OK_COUNT}
Logs FAIL      : ${FAIL_COUNT}
Logs SKIP      : ${SKIP_COUNT}
Manifest       : ${MANIFEST}
EOF

echo
echo "Logs root        : ${LOGS_ROOT}"
echo "Status log       : ${STATUSLOG}"
echo "Manifest         : ${MANIFEST}"
echo "Summary          : ${SUMMARY}"
echo
echo "Logs OK          : ${OK_COUNT}"
echo "Logs FAIL        : ${FAIL_COUNT}"
echo "Logs SKIP        : ${SKIP_COUNT}"
