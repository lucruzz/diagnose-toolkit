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

MODE="full"
CREATE_ARCHIVE="yes"

GREEN="\033[0;32m"
RED="\033[0;31m"
YELLOW="\033[1;33m"
WHITE="\033[1;37m"
COLOR_END="\033[0m"

HOST="$(hostname -s 2>/dev/null || hostname)"
TIMESTAMP="$(date +%Y%m%d_%H%M%S)"
OUTPUTDIR="${TOOLNAME}_${HOST}_${TIMESTAMP}"
ARCHIVE="${OUTPUTDIR}.tar.gz"
OS="$(awk -F '"' '/^PRETTY_NAME=/{print $2}' /etc/os-release 2>/dev/null)"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COLLECT_COMMANDS="${SCRIPT_DIR}/collect-commands.sh"
COLLECT_FILES="${SCRIPT_DIR}/collect-files.sh"
COLLECT_LOGS="${SCRIPT_DIR}/collect-logs.sh"
COLLECT_HEALTH="${SCRIPT_DIR}/collect-health.sh"

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
  -h, --help          Show this help
  -v, --version       Show version
  --list-profiles     List available profiles
  --no-archive        Do not create tar.gz archive

Examples:
  $0
  $0 cluster
  $0 basic --no-archive
EOF
}

print_profiles() {
    cat <<EOF
Available profiles:
  basic
  full
  cluster
  gpu
  packages
  network
  storage
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        basic|full|cluster|gpu|packages|network|storage)
            MODE="$1"
            shift
            ;;
        --no-archive)
            CREATE_ARCHIVE="no"
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

if [[ ! -x "${COLLECT_COMMANDS}" ]]; then
    echo "Missing or non-executable: ${COLLECT_COMMANDS}" >&2
    exit 1
fi

if [[ ! -x "${COLLECT_FILES}" ]]; then
    echo "Missing or non-executable: ${COLLECT_FILES}" >&2
    exit 1
fi

if [[ ! -x "${COLLECT_LOGS}" ]]; then
    echo "Missing or non-executable: ${COLLECT_LOGS}" >&2
    exit 1
fi

if [[ ! -x "${COLLECT_HEALTH}" ]]; then
    echo "Missing or non-executable: ${COLLECT_HEALTH}" >&2
    exit 1
fi

mkdir -p "${OUTPUTDIR}"/{meta,logs,commands,files,system-logs}

cat > "${OUTPUTDIR}/meta/tool-info.txt" <<EOF
TOOLNAME=${TOOLNAME}
FULL_TOOLNAME=${FULL_TOOLNAME}
VERSION=${VERSION}
HOST=${HOST}
TIMESTAMP=${TIMESTAMP}
OS=${OS:-Unknown}
PROFILE=${MODE}
EOF

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

echo "Running command collection..."
"${COLLECT_COMMANDS}" "${MODE}" "${OUTPUTDIR}"
COMMANDS_RC=$?

echo
echo "Running file collection..."
"${COLLECT_FILES}" "${MODE}" "${OUTPUTDIR}"
FILES_RC=$?

echo
echo "Running log collection..."
"${COLLECT_LOGS}" "${MODE}" "${OUTPUTDIR}"
LOGS_RC=$?

echo
echo "Running health checks..."
"${COLLECT_HEALTH}" "${MODE}" "${OUTPUTDIR}"
HEALTH_RC=$?

cat > "${OUTPUTDIR}/meta/summary.txt" <<EOF
Toolkit             : ${FULL_TOOLNAME}
Version             : ${VERSION}
Hostname            : ${HOST}
Operating Sys.      : ${OS:-Unknown}
Date                : $(date)
Profile             : ${MODE}

collect-commands rc : ${COMMANDS_RC}
collect-files rc    : ${FILES_RC}
collect-logs rc     : ${LOGS_RC}
collect-health rc   : ${HEALTH_RC}

Commands summary    : ${OUTPUTDIR}/meta/commands-summary.txt
Files summary       : ${OUTPUTDIR}/meta/files-summary.txt
System logs summary : ${OUTPUTDIR}/meta/logs-summary.txt
Health summary      : ${OUTPUTDIR}/meta/health-summary.txt
EOF

if [[ "${CREATE_ARCHIVE}" == "yes" ]]; then
    tar -czf "${ARCHIVE}" "${OUTPUTDIR}"
fi

echo
echo "Output directory  : ${OUTPUTDIR}"
if [[ "${CREATE_ARCHIVE}" == "yes" ]]; then
    echo "Archive           : ${ARCHIVE}"
fi
echo "Toolkit summary   : ${OUTPUTDIR}/meta/summary.txt"

if [[ "${COMMANDS_RC}" -ne 0 || "${FILES_RC}" -ne 0 || "${LOGS_RC}" -ne 0 || "${HEALTH_RC}" -ne 0 ]]; then
    exit 1
fi
