#!/usr/bin/env bash

# ==============================================================
# TOOL        : collect-health
# DESCRIPTION : Performs general health checks for services and cluster applications.
# AUTHOR      : Lucas Cruz
# CREATED     : 2026-04-24
# VERSION     : 0.0.1
# ==============================================================

set -uo pipefail

FULL_TOOLNAME="Diagnose Toolkit - Health Checker"
TOOLNAME="collect-health"
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

HEALTH_ROOT="${OUTPUTDIR}/health"
STATUSLOG="${OUTPUTDIR}/logs/health-status.log"
SUMMARY="${OUTPUTDIR}/meta/health-summary.txt"
REPORT="${HEALTH_ROOT}/health-report.txt"

mkdir -p "${HEALTH_ROOT}"/{system,services,cluster,storage,network,gpu,security}
mkdir -p "${OUTPUTDIR}/logs" "${OUTPUTDIR}/meta"
: > "${STATUSLOG}"
: > "${REPORT}"

echo -e ${YELLOW}
printf "\n======================================================\n"
echo "= Toolkit        : ${FULL_TOOLNAME}"
echo "= Version        : ${VERSION}"
echo "= Operating Sys. : ${OS:-Unknown}"
echo "= Date           : $(date)"
echo "= Profile        : ${MODE}"
printf "======================================================\n\n"
echo -e ${COLOR_END}

log_status() {
    local severity="$1"
    local check_name="$2"
    local message="$3"
    local outfile="$4"

    printf '%s | %-8s | %s | %s | %s\n' \
        "$(date --iso-8601=seconds)" \
        "${severity}" \
        "${check_name}" \
        "${message}" \
        "${outfile}" >> "${STATUSLOG}"

    printf '%-8s | %-35s | %s\n' \
        "${severity}" \
        "${check_name}" \
        "${message}" >> "${REPORT}"
}

print_result() {
    local severity="$1"
    local check_name="$2"
    local message="$3"

    case "${severity}" in
        OK)
            echo -e "${WHITE}[${COLOR_END} ${GREEN}OK${COLOR_END}${WHITE} ] ${check_name} :: ${message}${COLOR_END}"
            ;;
        WARN)
            echo -e "${WHITE}[${COLOR_END}${YELLOW}WARN${COLOR_END}${WHITE}] ${check_name} :: ${message}${COLOR_END}"
            ;;
        CRITICAL)
            echo -e "${WHITE}[${COLOR_END}${RED}CRIT${COLOR_END}${WHITE}] ${check_name} :: ${message}${COLOR_END}"
            ;;
        SKIP)
            echo -e "${WHITE}[${COLOR_END}${YELLOW}SKIP${COLOR_END}${WHITE}] ${check_name} :: ${message}${COLOR_END}"
            ;;
        *)
            echo "[${severity}] ${check_name} :: ${message}"
            ;;
    esac
}

record_check() {
    local severity="$1"
    local check_name="$2"
    local message="$3"
    local outfile="$4"

    log_status "${severity}" "${check_name}" "${message}" "${outfile}"
    print_result "${severity}" "${check_name}" "${message}"
}

command_exists() {
    command -v "$1" >/dev/null 2>&1
}

run_capture() {
    local outfile="$1"
    shift

    {
        echo "# COMMAND: $*"
        echo "# DATE: $(date --iso-8601=seconds)"
        echo
        "$@"
    } > "${outfile}" 2>&1
}

check_systemd_failed_units() {
    local outfile="${HEALTH_ROOT}/services/systemd-failed-units.txt"

    if ! command_exists systemctl; then
        record_check "SKIP" "systemd_failed_units" "systemctl not found" "${outfile}"
        return 0
    fi

    systemctl --failed --no-pager > "${outfile}" 2>&1
    local failed_count
    failed_count="$(systemctl --failed --no-legend 2>/dev/null | wc -l)"

    if [[ "${failed_count}" -eq 0 ]]; then
        record_check "OK" "systemd_failed_units" "no failed units" "${outfile}"
    else
        record_check "CRITICAL" "systemd_failed_units" "${failed_count} failed unit(s)" "${outfile}"
    fi
}

check_important_services() {
    local services=("$@")
    local outfile="${HEALTH_ROOT}/services/important-services.txt"
    : > "${outfile}"

    if ! command_exists systemctl; then
        record_check "SKIP" "important_services" "systemctl not found" "${outfile}"
        return 0
    fi

    local svc
    local failures=0
    local skipped=0

    for svc in "${services[@]}"; do
        {
            echo "======================================================"
            echo "SERVICE: ${svc}"
            echo "------------------------------------------------------"
            systemctl status "${svc}" --no-pager
            echo
        } >> "${outfile}" 2>&1

        if systemctl list-unit-files "${svc}.service" >/dev/null 2>&1 || systemctl status "${svc}" >/dev/null 2>&1; then
            if ! systemctl is-active --quiet "${svc}"; then
                ((failures+=1))
            fi
        else
            ((skipped+=1))
        fi
    done

    if [[ "${failures}" -eq 0 ]]; then
        record_check "OK" "important_services" "all checked services are active; skipped=${skipped}" "${outfile}"
    else
        record_check "CRITICAL" "important_services" "${failures} inactive/failed service(s); skipped=${skipped}" "${outfile}"
    fi
}

check_disk_usage() {
    local outfile="${HEALTH_ROOT}/storage/disk-usage.txt"
    local warn="${DISK_WARN:-85}"
    local crit="${DISK_CRIT:-95}"

    df -PTh > "${outfile}" 2>&1

    local critical_count=0
    local warn_count=0

    while read -r usage mountpoint; do
        usage="${usage%\%}"

        if [[ "${usage}" -ge "${crit}" ]]; then
            ((critical_count+=1))
        elif [[ "${usage}" -ge "${warn}" ]]; then
            ((warn_count+=1))
        fi
    done < <(df -P | awk 'NR>1 {print $5, $6}')

    if [[ "${critical_count}" -gt 0 ]]; then
        record_check "CRITICAL" "disk_usage" "${critical_count} filesystem(s) >= ${crit}%" "${outfile}"
    elif [[ "${warn_count}" -gt 0 ]]; then
        record_check "WARN" "disk_usage" "${warn_count} filesystem(s) >= ${warn}%" "${outfile}"
    else
        record_check "OK" "disk_usage" "all filesystems below ${warn}%" "${outfile}"
    fi
}

check_memory_usage() {
    local outfile="${HEALTH_ROOT}/system/memory-usage.txt"
    local warn="${MEM_WARN:-85}"
    local crit="${MEM_CRIT:-95}"

    free -h > "${outfile}" 2>&1

    local mem_percent
    mem_percent="$(free | awk '/^Mem:/ {printf "%.0f", ($3/$2)*100}')"

    if [[ "${mem_percent}" -ge "${crit}" ]]; then
        record_check "CRITICAL" "memory_usage" "memory usage ${mem_percent}% >= ${crit}%" "${outfile}"
    elif [[ "${mem_percent}" -ge "${warn}" ]]; then
        record_check "WARN" "memory_usage" "memory usage ${mem_percent}% >= ${warn}%" "${outfile}"
    else
        record_check "OK" "memory_usage" "memory usage ${mem_percent}%" "${outfile}"
    fi
}

check_load_average() {
    local outfile="${HEALTH_ROOT}/system/load-average.txt"
    local warn_factor="${LOAD_WARN_FACTOR:-2}"
    local crit_factor="${LOAD_CRIT_FACTOR:-4}"

    uptime > "${outfile}" 2>&1
    nproc > "${outfile}.nproc" 2>&1

    local cores load1 warn crit
    cores="$(nproc 2>/dev/null || echo 1)"
    load1="$(awk '{print $(NF-2)}' /proc/loadavg)"

    warn="$(awk -v c="${cores}" -v f="${warn_factor}" 'BEGIN {printf "%.2f", c*f}')"
    crit="$(awk -v c="${cores}" -v f="${crit_factor}" 'BEGIN {printf "%.2f", c*f}')"

    if awk -v l="${load1}" -v c="${crit}" 'BEGIN {exit !(l >= c)}'; then
        record_check "CRITICAL" "load_average" "load1=${load1}, threshold=${crit}" "${outfile}"
    elif awk -v l="${load1}" -v w="${warn}" 'BEGIN {exit !(l >= w)}'; then
        record_check "WARN" "load_average" "load1=${load1}, threshold=${warn}" "${outfile}"
    else
        record_check "OK" "load_average" "load1=${load1}, cores=${cores}" "${outfile}"
    fi
}

check_zombie_processes() {
    local outfile="${HEALTH_ROOT}/system/zombie-processes.txt"

    ps -eo pid,ppid,stat,comm,args | awk '$3 ~ /Z/' > "${outfile}" 2>&1
    local count
    count="$(awk 'END {print NR}' "${outfile}")"

    if [[ "${count}" -eq 0 ]]; then
        record_check "OK" "zombie_processes" "no zombie processes" "${outfile}"
    else
        record_check "WARN" "zombie_processes" "${count} zombie process(es)" "${outfile}"
    fi
}

check_multipath() {
    local outfile="${HEALTH_ROOT}/storage/multipath-health.txt"

    if ! command_exists multipath; then
        record_check "SKIP" "multipath" "multipath command not found" "${outfile}"
        return 0
    fi

    multipath -ll > "${outfile}" 2>&1
    local bad_count
    bad_count="$(grep -Eic 'failed|faulty|undef|offline' "${outfile}" || true)"

    if [[ "${bad_count}" -eq 0 ]]; then
        record_check "OK" "multipath" "no obvious failed/faulty paths" "${outfile}"
    else
        record_check "CRITICAL" "multipath" "${bad_count} suspicious path state(s)" "${outfile}"
    fi
}

check_slurm() {
    local outfile="${HEALTH_ROOT}/cluster/slurm-health.txt"

    if ! command_exists sinfo; then
        record_check "SKIP" "slurm" "sinfo not found" "${outfile}"
        return 0
    fi

    {
        echo "# sinfo"
        sinfo
        echo
        echo "# sinfo -R"
        sinfo -R
        echo
        echo "# squeue"
        squeue
    } > "${outfile}" 2>&1

    local bad_nodes
    bad_nodes="$(sinfo -h -o '%T' 2>/dev/null | grep -Eic 'down|drain|fail|maint|unknown' || true)"

    if [[ "${bad_nodes}" -eq 0 ]]; then
        record_check "OK" "slurm" "no DOWN/DRAIN/FAIL/UNKNOWN node states detected" "${outfile}"
    else
        record_check "WARN" "slurm" "${bad_nodes} problematic node state entries detected" "${outfile}"
    fi
}

check_pcs() {
    local outfile="${HEALTH_ROOT}/cluster/pcs-health.txt"

    if ! command_exists pcs; then
        record_check "SKIP" "pcs" "pcs not found" "${outfile}"
        return 0
    fi

    pcs status > "${outfile}" 2>&1
    local bad_count
    bad_count="$(grep -Eic 'failed|failure|stopped|unclean|offline|blocked|error' "${outfile}" || true)"

    if [[ "${bad_count}" -eq 0 ]]; then
        record_check "OK" "pcs" "no obvious cluster failures detected" "${outfile}"
    else
        record_check "CRITICAL" "pcs" "${bad_count} suspicious cluster status line(s)" "${outfile}"
    fi
}

check_beegfs() {
    local outfile="${HEALTH_ROOT}/cluster/beegfs-health.txt"

    if ! command_exists beegfs-ctl; then
        record_check "SKIP" "beegfs" "beegfs-ctl not found" "${outfile}"
        return 0
    fi

    {
        echo "# beegfs-ctl --listnodes --nodetype=meta"
        beegfs-ctl --listnodes --nodetype=meta
        echo
        echo "# beegfs-ctl --listnodes --nodetype=storage"
        beegfs-ctl --listnodes --nodetype=storage
        echo
        echo "# beegfs-ctl --listtargets --nodetype=storage --state"
        beegfs-ctl --listtargets --nodetype=storage --state
    } > "${outfile}" 2>&1

    local bad_count
    bad_count="$(grep -Eic 'offline|bad|needs-resync|error|failed' "${outfile}" || true)"

    if [[ "${bad_count}" -eq 0 ]]; then
        record_check "OK" "beegfs" "no obvious BeeGFS target/node failures detected" "${outfile}"
    else
        record_check "CRITICAL" "beegfs" "${bad_count} suspicious BeeGFS line(s)" "${outfile}"
    fi
}

check_ib() {
    local outfile="${HEALTH_ROOT}/network/infiniband-health.txt"

    if ! command_exists ibstat; then
        record_check "SKIP" "infiniband" "ibstat not found" "${outfile}"
        return 0
    fi

    ibstat > "${outfile}" 2>&1

    local down_count
    down_count="$(grep -Eic 'State: Down|Physical state: Disabled|Physical state: Polling' "${outfile}" || true)"

    if [[ "${down_count}" -eq 0 ]]; then
        record_check "OK" "infiniband" "no down/disabled IB ports detected by ibstat" "${outfile}"
    else
        record_check "CRITICAL" "infiniband" "${down_count} problematic IB state line(s)" "${outfile}"
    fi
}

check_gpu() {
    local outfile="${HEALTH_ROOT}/gpu/nvidia-health.txt"

    if ! command_exists nvidia-smi; then
        record_check "SKIP" "gpu" "nvidia-smi not found" "${outfile}"
        return 0
    fi

    nvidia-smi -q > "${outfile}" 2>&1

    local bad_count
    bad_count="$(grep -Eic 'Error|Failed|Unknown Error|Retired Pages.*: [1-9]' "${outfile}" || true)"

    if [[ "${bad_count}" -eq 0 ]]; then
        record_check "OK" "gpu" "nvidia-smi did not report obvious errors" "${outfile}"
    else
        record_check "WARN" "gpu" "${bad_count} suspicious GPU line(s)" "${outfile}"
    fi
}

check_sssd() {
    local outfile="${HEALTH_ROOT}/security/sssd-health.txt"

    if ! command_exists systemctl; then
        record_check "SKIP" "sssd" "systemctl not found" "${outfile}"
        return 0
    fi

    systemctl status sssd --no-pager > "${outfile}" 2>&1
    if systemctl is-active --quiet sssd; then
        record_check "OK" "sssd" "sssd is active" "${outfile}"
    else
        record_check "WARN" "sssd" "sssd is not active" "${outfile}"
    fi
}

check_time_sync() {
    local outfile="${HEALTH_ROOT}/system/time-sync.txt"

    if command_exists chronyc; then
        chronyc tracking > "${outfile}" 2>&1
        local leap
        leap="$(awk -F ': ' '/Leap status/ {print $2}' "${outfile}" 2>/dev/null)"

        if [[ "${leap}" == "Normal" ]]; then
            record_check "OK" "time_sync" "chrony leap status normal" "${outfile}"
        else
            record_check "WARN" "time_sync" "chrony leap status: ${leap:-unknown}" "${outfile}"
        fi
    elif command_exists timedatectl; then
        timedatectl > "${outfile}" 2>&1
        if grep -qi 'System clock synchronized: yes' "${outfile}"; then
            record_check "OK" "time_sync" "system clock synchronized" "${outfile}"
        else
            record_check "WARN" "time_sync" "system clock may not be synchronized" "${outfile}"
        fi
    else
        record_check "SKIP" "time_sync" "chronyc/timedatectl not found" "${outfile}"
    fi
}

run_basic_checks() {
    check_systemd_failed_units
    check_disk_usage
    check_memory_usage
    check_load_average
    check_zombie_processes
    check_time_sync
}

run_full_checks() {
    run_basic_checks
    check_important_services \
        sshd crond chronyd sssd firewalld NetworkManager \
        slurmd slurmctld munge \
        beegfs-client beegfs-meta beegfs-storage beegfs-mgmtd \
        pcsd pve-cluster zabbix-agent zabbix-agent2
    check_multipath
    check_slurm
    check_pcs
    check_beegfs
    check_ib
    check_gpu
    check_sssd
}

run_cluster_checks() {
    run_basic_checks
    check_important_services \
        sshd crond chronyd sssd NetworkManager \
        slurmd slurmctld munge \
        beegfs-client beegfs-meta beegfs-storage beegfs-mgmtd \
        pcsd
    check_multipath
    check_slurm
    check_pcs
    check_beegfs
    check_ib
    check_sssd
}

run_gpu_checks() {
    run_basic_checks
    check_important_services sshd crond chronyd sssd nvidia-persistenced
    check_gpu
}

run_packages_checks() {
    run_basic_checks
    check_important_services sshd crond chronyd
}

run_network_checks() {
    run_basic_checks
    check_important_services sshd chronyd sssd NetworkManager
    check_ib
    check_sssd
}

run_storage_checks() {
    run_basic_checks
    check_multipath
    check_beegfs
}


cat > "${REPORT}" <<EOF
Diagnose Toolkit - Health Report
Date    : $(date)
Profile : ${MODE}

Severity | Check                               | Message
---------|-------------------------------------|-------------------------------
EOF

case "${MODE}" in
    basic)    run_basic_checks ;;
    full)     run_full_checks ;;
    cluster)  run_cluster_checks ;;
    gpu)      run_gpu_checks ;;
    packages) run_packages_checks ;;
    network)  run_network_checks ;;
    storage)  run_storage_checks ;;
    *)
        echo "Invalid profile: ${MODE}" >&2
        exit 1
        ;;
esac

OK_COUNT="$(grep -c ' | OK[[:space:]]*|' "${STATUSLOG}" 2>/dev/null || echo 0)"
WARN_COUNT="$(grep -c ' | WARN[[:space:]]*|' "${STATUSLOG}" 2>/dev/null || echo 0)"
CRITICAL_COUNT="$(grep -c ' | CRITICAL[[:space:]]*|' "${STATUSLOG}" 2>/dev/null || echo 0)"
SKIP_COUNT="$(grep -c ' | SKIP[[:space:]]*|' "${STATUSLOG}" 2>/dev/null || echo 0)"

cat > "${SUMMARY}" <<EOF
Toolkit          : ${FULL_TOOLNAME}
Version          : ${VERSION}
Profile          : ${MODE}
Date             : $(date)

Health OK        : ${OK_COUNT}
Health WARN      : ${WARN_COUNT}
Health CRITICAL  : ${CRITICAL_COUNT}
Health SKIP      : ${SKIP_COUNT}

Health report    : ${REPORT}
Status log       : ${STATUSLOG}
EOF

echo
echo "Health root      : ${HEALTH_ROOT}"
echo "Status log       : ${STATUSLOG}"
echo "Summary          : ${SUMMARY}"
echo "Report           : ${REPORT}"
echo
echo "Health OK        : ${OK_COUNT}"
echo "Health WARN      : ${WARN_COUNT}"
echo "Health CRITICAL  : ${CRITICAL_COUNT}"
echo "Health SKIP      : ${SKIP_COUNT}"
