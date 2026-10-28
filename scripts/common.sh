#!/usr/bin/env bash
# ==============================================================================
# Helper module for NoSQLBench Benchmark Scripts (Astra DB or open-source Cassandra)
# ==============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Load config.env if present
if [[ -f "${SCRIPT_DIR}/config.env" ]]; then
    # shellcheck disable=SC1091
    source "${SCRIPT_DIR}/config.env"
fi

WORKLOAD_FILE="${WORKLOAD_FILE:-${SCRIPT_DIR}/reflinks_tokenmeta_read_heavy.yaml}"

# Set defaults for any unset variables
TARGET="${TARGET:-astra}"

# Astra DB connection
ASTRA_SCB_PATH="${ASTRA_SCB_PATH:-}"
ASTRA_TOKEN="${ASTRA_TOKEN:-}"

# Open-source Cassandra connection
CASSANDRA_HOSTS="${CASSANDRA_HOSTS:-}"
CASSANDRA_PORT="${CASSANDRA_PORT:-9042}"
CASSANDRA_LOCALDC="${CASSANDRA_LOCALDC:-}"
CASSANDRA_USERNAME="${CASSANDRA_USERNAME:-}"
CASSANDRA_PASSWORD="${CASSANDRA_PASSWORD:-}"

# ASTRA_KEYSPACE / ASTRA_TABLE are accepted for older config.env files
KEYSPACE="${KEYSPACE:-${ASTRA_KEYSPACE:-pix}}"
TABLE="${TABLE:-${ASTRA_TABLE:-reflinks_tokenmeta}}"

# Astra only supports SAI; Cassandra 4.x only supports legacy indexes
if [[ "${TARGET}" == "astra" ]]; then
    INDEX_TYPE="${INDEX_TYPE:-sai}"
else
    INDEX_TYPE="${INDEX_TYPE:-legacy}"
fi

KEYCOUNT="${KEYCOUNT:-1000000}"
RAMPUP_CYCLES="${RAMPUP_CYCLES:-100000}"
RAMPUP_THREADS="${RAMPUP_THREADS:-auto}"
MAIN_CYCLES="${MAIN_CYCLES:-200000}"
MAIN_THREADS="${MAIN_THREADS:-auto}"
MAIN_RATE="${MAIN_RATE:-auto}"
READ_RATIO="${READ_RATIO:-5}"
WRITE_RATIO="${WRITE_RATIO:-5}"
WRITE_CL="${WRITE_CL:-LOCAL_QUORUM}"
READ_CL="${READ_CL:-LOCAL_QUORUM}"

# Metrics export defaults
METRICS_DIR="${METRICS_DIR:-${SCRIPT_DIR}/metrics}"
REPORT_CSV="${REPORT_CSV:-true}"
LOG_HISTOSTATS="${LOG_HISTOSTATS:-true}"
LOG_PROGRESS_CSV="${LOG_PROGRESS_CSV:-true}"
HISTOSTATS_INTERVAL="${HISTOSTATS_INTERVAL:-5s}"
# Per-op timers (e.g. successfor_select_read / successfor_insert_main) to split read vs write latency
INSTRUMENT_OPS="${INSTRUMENT_OPS:-true}"

# Keep each target's results separate so runs can be compared side by side
METRICS_DIR="${METRICS_DIR}/${TARGET}"

# Populates the CONN_ARGS array with the nb5 driver connection parameters for TARGET
set_conn_args() {
    if [[ "${TARGET}" == "astra" ]]; then
        CONN_ARGS=(
            secureconnectbundle="${ASTRA_SCB_PATH}"
            username="token"
            password="${ASTRA_TOKEN}"
        )
    else
        CONN_ARGS=(
            host="${CASSANDRA_HOSTS}"
            port="${CASSANDRA_PORT}"
            localdc="${CASSANDRA_LOCALDC}"
        )
        if [[ -n "${CASSANDRA_USERNAME}" ]]; then
            CONN_ARGS+=(username="${CASSANDRA_USERNAME}" password="${CASSANDRA_PASSWORD}")
        fi
    fi
}

# Human-readable connection endpoint for banners
target_endpoint() {
    if [[ "${TARGET}" == "astra" ]]; then
        echo "Astra DB (SCB: ${ASTRA_SCB_PATH})"
    else
        echo "Cassandra (${CASSANDRA_HOSTS}:${CASSANDRA_PORT}, localdc=${CASSANDRA_LOCALDC})"
    fi
}

get_metric_flags() {
    local phase_name="${1:-benchmark}"
    local flags=()

    mkdir -p "${METRICS_DIR}"

    if [[ "${REPORT_CSV}" == "true" ]]; then
        flags+=("--report-csv-to" "${METRICS_DIR}")
    fi

    # Format is <file>:<metric regex>:<interval>; '.*' matches all latency & timer histograms
    if [[ "${LOG_HISTOSTATS}" == "true" ]]; then
        flags+=("--log-histostats" "${METRICS_DIR}/${phase_name}_histostats.csv:.*:${HISTOSTATS_INTERVAL}")
    fi

    flags+=("--progress" "console:10s")

    echo "${flags[@]}"
}

find_nb() {
    if [[ -n "${NB_EXEC:-}" && -f "${NB_EXEC}" ]]; then
        echo "${NB_EXEC}"
        return 0
    fi

    # Check local workspace nb5.jar
    local workspace_jar="${SCRIPT_DIR}/../nosqlbench/nb5.jar"
    if [[ -f "${workspace_jar}" ]]; then
        echo "${workspace_jar}"
        return 0
    fi

    # Check if 'nb5' is in PATH
    if command -v nb5 &>/dev/null; then
        echo "nb5"
        return 0
    fi

    # Check if 'nb' is in PATH
    if command -v nb &>/dev/null; then
        echo "nb"
        return 0
    fi

    echo ""
}

validate_env() {
    local errors=0

    case "${TARGET}" in
        astra)
            if [[ -z "${ASTRA_SCB_PATH}" ]]; then
                echo "ERROR: ASTRA_SCB_PATH is not set. Please specify the path to your Secure Connect Bundle (.zip)." >&2
                errors=$((errors + 1))
            elif [[ ! -f "${ASTRA_SCB_PATH}" ]]; then
                echo "ERROR: Secure Connect Bundle file not found at: ${ASTRA_SCB_PATH}" >&2
                errors=$((errors + 1))
            fi

            if [[ -z "${ASTRA_TOKEN}" ]]; then
                echo "ERROR: ASTRA_TOKEN is not set. Please provide your Astra DB token (e.g. AstraCS:...)." >&2
                errors=$((errors + 1))
            fi

            if [[ "${INDEX_TYPE}" != "sai" ]]; then
                echo "ERROR: Astra DB only supports INDEX_TYPE=sai (got '${INDEX_TYPE}')." >&2
                errors=$((errors + 1))
            fi
            ;;
        cassandra)
            if [[ -z "${CASSANDRA_HOSTS}" ]]; then
                echo "ERROR: CASSANDRA_HOSTS is not set. Please provide a comma-separated list of contact points." >&2
                errors=$((errors + 1))
            fi

            if [[ -z "${CASSANDRA_LOCALDC}" ]]; then
                echo "ERROR: CASSANDRA_LOCALDC is not set. Use the datacenter name shown by 'nodetool status'." >&2
                errors=$((errors + 1))
            fi

            if [[ -n "${CASSANDRA_USERNAME}" && -z "${CASSANDRA_PASSWORD}" ]]; then
                echo "ERROR: CASSANDRA_USERNAME is set but CASSANDRA_PASSWORD is empty." >&2
                errors=$((errors + 1))
            fi

            if [[ "${INDEX_TYPE}" != "sai" && "${INDEX_TYPE}" != "legacy" ]]; then
                echo "ERROR: INDEX_TYPE must be 'sai' or 'legacy' (got '${INDEX_TYPE}')." >&2
                errors=$((errors + 1))
            fi
            ;;
        *)
            echo "ERROR: TARGET must be 'astra' or 'cassandra' (got '${TARGET}')." >&2
            errors=$((errors + 1))
            ;;
    esac

    local nb_bin
    nb_bin="$(find_nb)"
    if [[ -z "${nb_bin}" ]]; then
        echo "ERROR: NoSQLBench (nb5 or nb5.jar) could not be found." >&2
        echo "Please install nb5 or set NB_EXEC in config.env." >&2
        errors=$((errors + 1))
    fi

    if [[ ${errors} -gt 0 ]]; then
        echo "" >&2
        echo "Tip: Fill in the required values for TARGET=${TARGET} in:" >&2
        echo "  ${SCRIPT_DIR}/config.env" >&2
        exit 1
    fi
}

# nb5.jar requires Java 25+ (class file version 69)
find_java() {
    if [[ -n "${JAVA_BIN:-}" ]]; then
        echo "${JAVA_BIN}"
        return 0
    fi

    # Homebrew openjdk@25 is keg-only, so it is not on PATH by default
    local brew_java
    for brew_java in /opt/homebrew/opt/openjdk@25/bin/java /usr/local/opt/openjdk@25/bin/java; do
        if [[ -x "${brew_java}" ]]; then
            echo "${brew_java}"
            return 0
        fi
    done

    echo "java"
}

run_nb() {
    local nb_bin
    nb_bin="$(find_nb)"

    local cmd=()
    if [[ "${nb_bin}" == *.jar ]]; then
        cmd=("$(find_java)" "-jar" "${nb_bin}")
    else
        cmd=("${nb_bin}")
    fi

    "${cmd[@]}" "$@"
}
