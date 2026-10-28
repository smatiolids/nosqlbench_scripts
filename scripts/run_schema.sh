#!/usr/bin/env bash
set -euo pipefail

# ==============================================================================
# Phase 1: Create Table Schema (Astra DB or open-source Cassandra)
# ==============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/common.sh"

validate_env
set_conn_args

echo "=============================================================================="
echo "Creating Schema"
echo "Target:      $(target_endpoint)"
echo "Keyspace:    ${KEYSPACE}"
echo "Table:       ${TABLE}"
echo "Index Type:  ${INDEX_TYPE}"
echo "Note:        Keyspace '${KEYSPACE}' must already exist."
echo "=============================================================================="

# nb5 rejects parameters the workload never references, so only pass index_type if it is used
SCHEMA_ARGS=()
if grep -q 'TEMPLATE(index_type' "${WORKLOAD_FILE}"; then
    SCHEMA_ARGS+=(index_type="${INDEX_TYPE}")
fi

# Use scenario 'schema' with TEMPLATE parameter substitution
run_nb "${WORKLOAD_FILE}" schema \
    "${CONN_ARGS[@]}" \
    keyspace="${KEYSPACE}" \
    table="${TABLE}" \
    ${SCHEMA_ARGS[@]+"${SCHEMA_ARGS[@]}"}

echo "Schema creation completed successfully."
