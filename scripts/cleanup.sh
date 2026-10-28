#!/usr/bin/env bash
set -euo pipefail

# ==============================================================================
# Cleanup: Drop Benchmark Table (Astra DB or open-source Cassandra)
#   -f / --force         skip confirmation
# ==============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/common.sh"

validate_env
set_conn_args

FORCE=0
for arg in "$@"; do
    if [[ "${arg}" == "-f" || "${arg}" == "--force" ]]; then
        FORCE=1
    fi
done

if [[ ${FORCE} -eq 0 ]]; then
    read -r -p "Are you sure you want to drop table '${KEYSPACE}.${TABLE}' on $(target_endpoint)? [y/N]: " confirm
    if [[ ! "${confirm}" =~ ^[Yy]$ ]]; then
        echo "Cleanup aborted."
        exit 0
    fi
fi

echo "=============================================================================="
echo "Dropping Table '${KEYSPACE}.${TABLE}'"
echo "=============================================================================="

run_nb "${WORKLOAD_FILE}" cleanup \
    "${CONN_ARGS[@]}" \
    keyspace="${KEYSPACE}" \
    table="${TABLE}"

echo "Table dropped successfully."
