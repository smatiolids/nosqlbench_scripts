#!/usr/bin/env bash
set -euo pipefail

# ==============================================================================
# Phase 3: Main Mixed Read/Write Workload (ratio from READ_RATIO / WRITE_RATIO)
# ==============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/common.sh"

validate_env
set_conn_args

READ_PCT=$(( 100 * READ_RATIO / (READ_RATIO + WRITE_RATIO) ))

echo "=============================================================================="
echo "Starting Main Benchmark (${READ_PCT}% Reads / $((100 - READ_PCT))% Writes)"
echo "Target:       $(target_endpoint)"
echo "Keyspace:     ${KEYSPACE}"
echo "Table:        ${TABLE}"
echo "Main Cycles:  ${MAIN_CYCLES}"
echo "Main Threads: ${MAIN_THREADS}"
echo "Target Rate:  ${MAIN_RATE} ops/s"
echo "Keycount:     ${KEYCOUNT}"
echo "Read Ratio:   ${READ_RATIO} / Write Ratio: ${WRITE_RATIO}"
echo "Read CL:      ${READ_CL} / Write CL: ${WRITE_CL}"
if [[ "${REPORT_CSV}" == "true" || "${LOG_HISTOSTATS}" == "true" ]]; then
    echo "Metrics Output: ${METRICS_DIR}"
fi
echo "=============================================================================="

METRIC_ARGS=($(get_metric_flags "main"))

run_nb "${METRIC_ARGS[@]}" "${WORKLOAD_FILE}" main \
    "${CONN_ARGS[@]}" \
    keyspace="${KEYSPACE}" \
    table="${TABLE}" \
    keycount="${KEYCOUNT}" \
    main-cycles="${MAIN_CYCLES}" \
    main-threads="${MAIN_THREADS}" \
    main-rate="${MAIN_RATE}" \
    read_ratio="${READ_RATIO}" \
    write_ratio="${WRITE_RATIO}" \
    read_cl="${READ_CL}" \
    write_cl="${WRITE_CL}" \
    instrument-all="${INSTRUMENT_OPS}"

echo "Main benchmark run completed successfully."
