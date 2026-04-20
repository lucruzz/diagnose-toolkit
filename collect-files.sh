#!/usr/bin/env bash

# ==============================================================
# TOOL        : diagnose-toolkit
# DESCRIPTION : Collects diagnostic information from the system.
# AUTHOR      : Lucas Cruz
# CREATED     : 2026-04-20
# VERSION     : 0.0.1
# ==============================================================


set -uo pipefail

FULL_TOOLNAME="Diagnose Toolkit - File Collector"
TOOLNAME="collect-files"
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

FILES_ROOT="${OUTPUTDIR}/files"
STATUSLOG="${OUTPUTDIR}/logs/file-status.log"
MANIFEST="${OUTPUTDIR}/meta/files-manifest.txt"
SUMMARY="${OUTPUTDIR}/meta/files-summary.txt"

mkdir -p "${FILES_ROOT}" "${OUTPUTDIR}/logs" "${OUTPUTDIR}/meta"
: > "${STATUSLOG}"
: > "${MANIFEST}"

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
  basic     - Minimal config collection
  full      - Full config collection
  cluster   - HPC/cluster focused config collection
  gpu       - GPU node related config collection
  packages  - Package/repository related config collection
  network   - Network related config collection
  storage   - Storage related config collection
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

copy_entry() {
    local match="$1"
    local relpath="${match#/}"
    local dest="${FILES_ROOT}/${relpath}"
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
        echo -e "${WHITE}[${COLOR_END} ${GREEN}OK${COLOR_END}${WHITE} ] ${match}${COLOR_END}"
        log_status 0 "${match}" "${dest}"
    else
        echo -e "${WHITE}[${COLOR_END}${RED}FAIL${COLOR_END}${WHITE}] ${match}${COLOR_END}"
        log_status "${rc}" "${match}" "${dest}" "rc=${rc}"
    fi
}

collect_path() {
    local pattern="$1"
    local found=0

    while IFS= read -r match; do
        found=1
        copy_entry "${match}"
    done < <(compgen -G "${pattern}" || true)

    if [[ "${found}" -eq 0 ]]; then
        echo -e "${WHITE}[${COLOR_END}${YELLOW}SKIP${COLOR_END}${WHITE}] ${pattern} :: no matches${COLOR_END}"
        log_status 127 "${pattern}" "${FILES_ROOT}" "no matches"
    fi
}

load_basic_paths() {
    paths=(
        "/etc/hosts"
        "/etc/fstab"
        "/usr/lib/os-release"
        "/etc/redhat-release"
    )
}

load_full_paths() {
    paths=(
        "/etc/beegfs"
        "/etc/exports"
        "/etc/fstab"
        "/etc/hosts"
        "/etc/slurm"
        "/usr/lib/os-release"
        "/etc/redhat-release"
        "/etc/yum.repos.d"
        "/etc/multipath*"
        "/etc/chrony.conf"
        "/etc/resolv.conf"
        "/etc/selinux/config"
        "/etc/security/limits.conf"
        "/etc/ssh/sshd_config"
        "/etc/sysctl.conf"
        "/etc/sysctl.d"
        "/etc/modules-load.d"
        "/etc/modprobe.d"
    )
}

load_cluster_paths() {
    paths=(
        "/etc/beegfs"
        "/etc/exports"
        "/etc/fstab"
        "/etc/hosts"
        "/etc/slurm"
        "/usr/lib/os-release"
        "/etc/redhat-release"
        "/etc/yum.repos.d"
        "/etc/multipath*"
        "/etc/chrony.conf"
        "/etc/resolv.conf"
        "/etc/selinux/config"
        "/etc/security/limits.conf"
        "/etc/ssh/sshd_config"
        "/etc/sysctl.conf"
        "/etc/sysctl.d"
        "/etc/modules-load.d"
        "/etc/modprobe.d"
    )
}

load_gpu_paths() {
    paths=(
        "/etc/hosts"
        "/etc/fstab"
        "/usr/lib/os-release"
        "/etc/redhat-release"
        "/etc/modprobe.d"
        "/etc/modules-load.d"
        "/etc/yum.repos.d"
    )
}

load_packages_paths() {
    paths=(
        "/etc/yum.repos.d"
        "/usr/lib/os-release"
        "/etc/redhat-release"
    )
}

load_network_paths() {
    paths=(
        "/etc/hosts"
        "/etc/resolv.conf"
        "/etc/chrony.conf"
        "/etc/sysctl.conf"
        "/etc/sysctl.d"
        "/etc/ssh/sshd_config"
    )
}

load_storage_paths() {
    paths=(
        "/etc/fstab"
        "/etc/exports"
        "/etc/multipath*"
        "/etc/modprobe.d"
        "/etc/modules-load.d"
    )
}

paths=()
case "${MODE}" in
    basic)    load_basic_paths ;;
    full)     load_full_paths ;;
    cluster)  load_cluster_paths ;;
    gpu)      load_gpu_paths ;;
    packages) load_packages_paths ;;
    network)  load_network_paths ;;
    storage)  load_storage_paths ;;
    *)
        echo "Invalid profile: ${MODE}" >&2
        exit 1
        ;;
esac

OK_COUNT=0
FAIL_COUNT=0
SKIP_COUNT=0

for path_entry in "${paths[@]}"; do
    before_lines=0
    [[ -f "${STATUSLOG}" ]] && before_lines="$(wc -l < "${STATUSLOG}")"

    collect_path "${path_entry}"

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

Files OK       : ${OK_COUNT}
Files FAIL     : ${FAIL_COUNT}
Files SKIP     : ${SKIP_COUNT}
Manifest       : ${MANIFEST}
EOF

echo
echo "Files root       : ${FILES_ROOT}"
echo "Status log       : ${STATUSLOG}"
echo "Manifest         : ${MANIFEST}"
echo "Summary          : ${SUMMARY}"
echo
echo "Files OK         : ${OK_COUNT}"
echo "Files FAIL       : ${FAIL_COUNT}"
echo "Files SKIP       : ${SKIP_COUNT}"