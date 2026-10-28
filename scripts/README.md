# Astra DB / Cassandra Workloads for NoSQLBench (nb5)

This directory contains NoSQLBench workloads and automation scripts for benchmarking either DataStax Astra DB or open-source Apache Cassandra with the same operations, so results can be compared side by side. The target is selected with `TARGET=astra|cassandra` (see [Choosing a Target](#choosing-a-target-astra-db-vs-open-source-cassandra)).

---

## Directory Contents

| File | Purpose |
|------|---------|
| [`astradb_1kb_balanced.yaml`](astradb_1kb_balanced.yaml) | Balanced 50% read / 50% write NoSQLBench workload definition |
| [`reflinks_tokenmeta_read_heavy.yaml`](reflinks_tokenmeta_read_heavy.yaml) | Read-heavy (90% read / 10% write) workload for `reflinks_tokenmeta` table |
| [`reflinks_tokenmeta.sql`](reflinks_tokenmeta.sql) | CQL schema definition for `reflinks_tokenmeta` table and indexes |
| `config.env` | Target selection, connection settings (Astra or Cassandra) and runtime parameters |
| [`common.sh`](common.sh) | Shared shell routines for parameter validation and NoSQLBench execution |
| [`run_schema.sh`](run_schema.sh) | Creates the table and indexes in the existing keyspace (`schema` scenario) |
| [`run_rampup.sh`](run_rampup.sh) | Pre-populates the database with initial ~1KB records |
| [`run_main.sh`](run_main.sh) | Executes the main mixed read/write benchmark (`READ_RATIO` / `WRITE_RATIO`) |
| [`run_all.sh`](run_all.sh) | End-to-end automation: Schema -> Rampup -> Main Benchmark |
| [`cleanup.sh`](cleanup.sh) | Drops the test table |
| [`view_results.sh`](view_results.sh) | Summarizes throughput and latency per operation (reads vs writes) from the histostats metrics |
| [`summarize_metrics.py`](summarize_metrics.py) | Parser used by `view_results.sh`; can also be run directly on `*_histostats.csv` files |

---

## Workload Design & Data Model

### Table Schema (Astra DB Compatible)
```sql
CREATE TABLE IF NOT EXISTS TEMPLATE(keyspace,default_keyspace).TEMPLATE(table,astradb_1kb_bench) (
    id uuid,
    created_at timestamp,
    status text,
    seq_num int,
    data text,
    PRIMARY KEY (id)
);
```

### Row Sizing (~1KB)
- **`id` (UUID)**: 16 bytes (Deterministic via `Mod(TEMPLATE(keycount,1000000)); ToHashedUUID() -> java.util.UUID`)
- **`created_at` (Timestamp)**: 8 bytes (`StartingEpochMillis('2024-01-01 00:00:00'); ToJavaInstant() -> java.time.Instant`)
- **`status` (Text)**: ~8 bytes (`WeightedStrings('ACTIVE:70;INACTIVE:20;PENDING:10;')`)
- **`seq_num` (Int)**: 4 bytes (`HashRange(0, 1000000); ToInt() -> int`)
- **`data` (Text)**: 950 bytes ASCII (`AlphaNumericString(TEMPLATE(payload_size,950))`)
- **Cassandra / CQL overhead & cell metadata**: ~40 bytes
- **Total row footprint**: **~1,024 bytes (~1 KB)**

### Balanced 50% Read / 50% Write Traffic
The `main` block defines two operations matching `tags==block:"main.*"`:
- `main_read`: `ratio: TEMPLATE(read_ratio,5)` (`SELECT ... WHERE id = {id}`)
- `main_write`: `ratio: TEMPLATE(write_ratio,5)` (`INSERT INTO ... VALUES (...)`)

Because `{id}` is derived deterministically using `Mod(TEMPLATE(keycount,1000000))`, point reads query the exact partition key range written during the rampup phase and updated during write cycles.

---

## Quick Start

### 1. Prerequisites
- **Java Runtime**: Java 25+ for the bundled `nb5.jar` (Homebrew `openjdk@25` is picked up automatically, or set `JAVA_BIN`)
- **NoSQLBench**: `nb5` in PATH or `nosqlbench/nb5.jar`
- **Astra DB Database**:
  - Secure Connect Bundle (`.zip`) downloaded from your Astra DB dashboard.
  - Astra DB Application Token (format `AstraCS:...`).
  - Target Keyspace created in your Astra DB database.
- **Or an open-source Cassandra cluster**: contact points, local datacenter name, credentials if auth is enabled, and the target keyspace already created.

### 2. Configure Credentials
Edit `astradb-1kb-workload/config.env`:
```bash
TARGET="${TARGET:-astra}"          # astra | cassandra

# Astra DB (TARGET=astra)
ASTRA_SCB_PATH="/path/to/secure-connect-bundle.zip"
ASTRA_TOKEN="AstraCS:..."

# Open-source Cassandra (TARGET=cassandra)
CASSANDRA_HOSTS="10.0.0.1,10.0.0.2,10.0.0.3"
CASSANDRA_PORT=9042
CASSANDRA_LOCALDC="datacenter1"     # must match `nodetool status`
CASSANDRA_USERNAME=""               # empty if auth is disabled
CASSANDRA_PASSWORD=""

# Schema (both targets; the keyspace must already exist)
KEYSPACE="pix"
TABLE="reflinks_tokenmeta"
INDEX_TYPE=""                       # sai | legacy (empty = sai on Astra, legacy on Cassandra)

# Workload Tuning (TEMPLATE parameters)
KEYCOUNT=1000000
RAMPUP_CYCLES=100000
RAMPUP_THREADS="auto"
MAIN_CYCLES=200000
MAIN_THREADS="auto"
MAIN_RATE="auto"      # or target ops/sec, e.g. 10000
READ_RATIO=5
WRITE_RATIO=5
WRITE_CL="LOCAL_QUORUM"
READ_CL="LOCAL_QUORUM"

# Metrics Export (written to METRICS_DIR/<TARGET>, e.g. metrics/astra)
METRICS_DIR="metrics"
REPORT_CSV=true
LOG_HISTOSTATS=true
HISTOSTATS_INTERVAL="10s"
```

### 3. Execution Options

#### Option A: Full Automated Run (Recommended)
Runs schema creation, rampup (writes initial dataset), and the main 50/50 balanced workload:
```bash
./astradb-1kb-workload/run_all.sh
```

#### Option B: Step-by-Step Execution

1. **Create Table**:
   ```bash
   ./astradb-1kb-workload/run_schema.sh
   ```

2. **Rampup (Pre-populate ~1KB rows)**:
   ```bash
   ./astradb-1kb-workload/run_rampup.sh
   ```

3. **Run 50/50 Balanced Benchmark**:
   ```bash
   ./astradb-1kb-workload/run_main.sh
   ```

4. **View Metrics Summary**:
   ```bash
   ./astradb-1kb-workload/view_results.sh              # current TARGET
   ./astradb-1kb-workload/view_results.sh --timeline   # plus ops/s and p99 per interval
   ./astradb-1kb-workload/view_results.sh --all        # astra and cassandra, one after the other
   ```
   For each phase it shows, per operation (`select_read`, `insert_main`) and in total: ops, read/write mix,
   average / steady-state / peak ops/s, p50 / p90 / p99 / p99.9 / max latency in ms, and errors.
   Per-operation numbers need `INSTRUMENT_OPS=true` (the default). Each run overwrites
   `<phase>_histostats.csv`, so copy the folder if you want to keep a run's results.

5. **Cleanup (Drop table when finished)**:
   ```bash
   ./astradb-1kb-workload/cleanup.sh
   # Or skip confirmation:
   ./astradb-1kb-workload/cleanup.sh --force
   ```

---

## Choosing a Target: Astra DB vs Open-Source Cassandra

Set `TARGET` in `config.env`, or override it for a single run:
```bash
TARGET=astra     ./astradb-1kb-workload/run_all.sh
TARGET=cassandra ./astradb-1kb-workload/run_all.sh
```

The keyspace must already exist on both targets; the scripts only create, load and drop the table. Schema, rampup, main, verify, truncate and cleanup run the same statements on both targets. Only the connection and index type differ:

| | Astra DB | Open-source Cassandra |
|---|---|---|
| Connection | `secureconnectbundle`, `username=token`, `password=$ASTRA_TOKEN` | `host`, `port`, `localdc`, plus `username`/`password` when set |
| Indexes (`reflinks_tokenmeta`) | SAI only (`INDEX_TYPE=sai`) | `legacy` (4.x) or `sai` (5.0+) |

For a fair comparison:
- Create the Cassandra keyspace with RF 3 (`NetworkTopologyStrategy`) to match Astra, and keep `LOCAL_QUORUM` on both.
- Astra serverless applies rate limits; compare both targets at the same fixed `MAIN_RATE` that Astra can sustain.
- Results are kept apart in `metrics/astra` and `metrics/cassandra`; compare them with `./view_results.sh --all`.

---

## Direct NoSQLBench CLI Example

When using scenario invocation, template variables (e.g., `keyspace`, `table`, `keycount`, `payload_size`, `main-cycles`) are passed as CLI parameters, alongside metric export flags (`--report-csv-to` and `--log-histostats`):

```bash
java -jar nosqlbench/nb5.jar \
  --report-csv-to metrics \
  --log-histostats ".*:metrics/main_histostats.csv:5s" \
  --progress console:1s \
  astradb-1kb-workload/astradb_1kb_balanced.yaml main \
  secureconnectbundle=/path/to/secure-connect-bundle.zip \
  username=token \
  password=AstraCS:... \
  keyspace=default_keyspace \
  table=astradb_1kb_bench \
  keycount=1000000 \
  payload_size=950 \
  main-cycles=200000 \
  main-threads=auto \
  main-rate=10000 \
  read_ratio=5 \
  write_ratio=5 \
  read_cl=LOCAL_QUORUM \
  write_cl=LOCAL_QUORUM
```

---

## Read-Heavy Workload for `pix.reflinks_tokenmeta` (90% Read / 10% Write)

This is the default `WORKLOAD_FILE`. Set `READ_RATIO=9` and `WRITE_RATIO=1` in `config.env` for a 90/10 mix, then:

```bash
./astradb-1kb-workload/run_all.sh
```

Or directly via `nb5` (Astra; for Cassandra replace the three connection parameters with `host=... port=9042 localdc=...`):

```bash
java -jar nosqlbench/nb5.jar \
  --report-csv-to metrics \
  --log-histostats ".*:metrics/reflinks_histostats.csv:5s" \
  --progress console:1s \
  astradb-1kb-workload/reflinks_tokenmeta_read_heavy.yaml main \
  secureconnectbundle=/path/to/secure-connect-bundle.zip \
  username=token \
  password=AstraCS:... \
  keyspace=pix \
  table=reflinks_tokenmeta \
  keycount=1000000 \
  main-cycles=200000 \
  read_ratio=9 \
  write_ratio=1
```
