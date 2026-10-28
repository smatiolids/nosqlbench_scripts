#!/usr/bin/env bash
set -euo pipefail

# ==============================================================================
# End-to-End Orchestrator: Schema -> Rampup -> Main Benchmark
# ==============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/common.sh"

validate_env

echo "=============================================================================="
echo "Running Full Benchmark Pipeline"
echo "Target:   $(target_endpoint)"
echo "Workload: $(basename "${WORKLOAD_FILE}") (Read ${READ_RATIO} : Write ${WRITE_RATIO})"
echo "=============================================================================="

echo ""
echo "[Step 1/3] Creating Table Schema..."
"${SCRIPT_DIR}/run_schema.sh"

echo ""
echo "[Step 2/3] Executing Rampup (Pre-populating ${RAMPUP_CYCLES} rows)..."
"${SCRIPT_DIR}/run_rampup.sh"

echo ""
echo "[Step 3/3] Executing Main Workload (${MAIN_CYCLES} operations)..."
"${SCRIPT_DIR}/run_main.sh"

echo ""
echo "=============================================================================="
echo "All benchmark stages completed successfully!"
echo "=============================================================================="
