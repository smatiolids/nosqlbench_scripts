#!/usr/bin/env bash
set -euo pipefail

# ==============================================================================
# Phase 2: Rampup / Data Pre-population
# ==============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/common.sh"

validate_env
set_conn_args

echo "=============================================================================="
echo "Starting Rampup Phase"
echo "Target:         $(target_endpoint)"
echo "Keyspace:       ${KEYSPACE}"
echo "Table:          ${TABLE}"
echo "Rampup Cycles:  ${RAMPUP_CYCLES}"
echo "Rampup Threads: ${RAMPUP_THREADS}"
echo "Keycount:       ${KEYCOUNT}"
echo "Write CL:       ${WRITE_CL}"
if [[ "${REPORT_CSV}" == "true" || "${LOG_HISTOSTATS}" == "true" ]]; then
    echo "Metrics Output: ${METRICS_DIR}"
fi
echo "=============================================================================="

METRIC_ARGS=($(get_metric_flags "rampup"))

run_nb "${METRIC_ARGS[@]}" "${WORKLOAD_FILE}" rampup \
    "${CONN_ARGS[@]}" \
    keyspace="${KEYSPACE}" \
    table="${TABLE}" \
    keycount="${KEYCOUNT}" \
    rampup-cycles="${RAMPUP_CYCLES}" \
    rampup-threads="${RAMPUP_THREADS}" \
    write_cl="${WRITE_CL}" \
    instrument-all="${INSTRUMENT_OPS}"

echo "Rampup completed successfully."
