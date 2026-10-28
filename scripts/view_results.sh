#!/usr/bin/env bash
set -euo pipefail

# ==============================================================================
# Helper: Summarize throughput and latency from the nb5 histostats metrics
#
# Usage:
#   ./view_results.sh                  # current TARGET (metrics/<target>)
#   ./view_results.sh --all            # every target under the metrics dir (astra, cassandra)
#   ./view_results.sh --timeline       # also show ops/s and p99 per interval
#   ./view_results.sh <dir|file> ...   # specific metrics dirs or *_histostats.csv files
# ==============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/common.sh"

PY_ARGS=()
PATHS=()
ALL_TARGETS=0
for arg in "$@"; do
    case "${arg}" in
        --timeline) PY_ARGS+=("--timeline") ;;
        --all) ALL_TARGETS=1 ;;
        -h|--help)
            sed -n '5,11p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
            exit 0
            ;;
        *) PATHS+=("${arg}") ;;
    esac
done

if [[ ${ALL_TARGETS} -eq 1 ]]; then
    # METRICS_DIR already ends with /<TARGET>; look at all its siblings
    for dir in "$(dirname "${METRICS_DIR}")"/*/; do
        PATHS+=("${dir%/}")
    done
fi

if [[ ${#PATHS[@]} -eq 0 ]]; then
    PATHS=("${METRICS_DIR}")
fi

for path in "${PATHS[@]}"; do
    if [[ ! -e "${path}" ]]; then
        echo "Metrics path '${path}' not found." >&2
        echo "Run the benchmark first, or pass the metrics directory (e.g. ./view_results.sh metrics/astra)." >&2
        exit 1
    fi
done

python3 "${SCRIPT_DIR}/summarize_metrics.py" ${PY_ARGS[@]+"${PY_ARGS[@]}"} "${PATHS[@]}"
