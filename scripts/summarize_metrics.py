#!/usr/bin/env python3
"""
Summarize NoSQLBench (nb5) --log-histostats files: throughput and latency per operation.

Each <phase>_histostats.csv covers a single session (nb5 overwrites it every run) and holds one
row per metric per interval:
    Tag=<metric>,Interval_Start,Interval_Length,count,min,p25,p50,p75,p90,p95,p98,p99,p999,p9999,max

Metrics used:
    successfor_<op>      latency of successful executions of op <op> (needs instrument-all=true)
    errorsfor_<op>       failed executions of op <op>
    result_success       latency of all successful ops
    cycles_responsetime  latency including rate-limiter queueing (only when a rate is set)

Usage:
    summarize_metrics.py [--timeline] PATH [PATH ...]
PATH may be a *_histostats.csv file or a directory containing them.
"""

import argparse
import os
import re
import sys
from datetime import datetime

PERCENTILES = ["p50", "p90", "p99", "p999"]
COLUMNS = ["count", "min", "p25", "p50", "p75", "p90", "p95", "p98", "p99", "p999", "p9999", "max"]
NS_PER_MS = 1_000_000


class Interval:
    def __init__(self, start, length, values):
        self.start = start
        self.length = length
        self.v = values

    @property
    def end(self):
        return self.start + self.length


def parse_file(path):
    """Returns (session, start_time_epoch, {tag: [Interval, ...]})."""
    session, start_epoch, unit = None, None, "NANOSECONDS"
    series = {}
    with open(path) as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            if line.startswith("#"):
                m = re.match(r"#logging stats for session (\S+)", line)
                if m:
                    session = m.group(1)
                m = re.match(r"#\[StartTime: ([\d.]+)", line)
                if m:
                    start_epoch = float(m.group(1))
                m = re.match(r"#\[TimeUnit: (\w+)", line)
                if m:
                    unit = m.group(1)
                continue
            parts = line.split(",")
            if not parts[0].startswith("Tag=") or len(parts) < 3 + len(COLUMNS):
                continue
            tag = parts[0][len("Tag="):]
            values = dict(zip(COLUMNS, (float(x) for x in parts[3:3 + len(COLUMNS)])))
            series.setdefault(tag, []).append(Interval(float(parts[1]), float(parts[2]), values))
    if unit != "NANOSECONDS":
        print(f"WARNING: {path}: unexpected time unit {unit}; latencies assume nanoseconds", file=sys.stderr)
    return session, start_epoch, series


def trim(intervals):
    """Drops empty intervals at the start and end (before the first op / after the last op)."""
    nonzero = [n for n, i in enumerate(intervals) if i.v["count"] > 0]
    return intervals[nonzero[0]:nonzero[-1] + 1] if nonzero else []


def steady(intervals):
    """Drops the first and last non-empty interval (warm-up / partial tail) when there are enough."""
    intervals = trim(intervals)
    return intervals[1:-1] if len(intervals) >= 4 else intervals


def summarize(intervals):
    """Aggregates per-interval rows. Percentiles are count-weighted averages of the interval
    percentiles (an approximation: exact merging needs the raw HDR histograms)."""
    total = sum(i.v["count"] for i in intervals)
    if not intervals:
        return None
    duration = max(i.end for i in intervals) - min(i.start for i in intervals)
    s = {
        "count": total,
        "duration": duration,
        "rate": total / duration if duration > 0 else 0.0,
        "peak_rate": max((i.v["count"] / i.length for i in intervals if i.length > 0), default=0.0),
        "max": max(i.v["max"] for i in intervals) / NS_PER_MS,
        "worst_p99": max(i.v["p99"] for i in intervals if i.v["count"] > 0) / NS_PER_MS if total else 0.0,
    }
    st = steady(intervals)
    st_dur = sum(i.length for i in st)
    s["steady_rate"] = sum(i.v["count"] for i in st) / st_dur if st_dur > 0 else s["rate"]
    for p in PERCENTILES:
        s[p] = (sum(i.v[p] * i.v["count"] for i in intervals) / total / NS_PER_MS) if total else 0.0
    return s


def fmt_ms(x):
    return f"{x:,.1f}" if x >= 100 else f"{x:,.2f}"


def print_phase(path, timeline):
    session, start_epoch, series = parse_file(path)
    phase = os.path.basename(path).replace("_histostats.csv", "")
    started = datetime.fromtimestamp(start_epoch).strftime("%Y-%m-%d %H:%M:%S") if start_epoch else "?"

    print("=" * 100)
    print(f"Phase: {phase}    Session: {session or '?'}    Started: {started}")
    print(f"File:  {path}")

    if not series:
        print("\n  (no data rows; the run may have failed or ended before the first interval)\n")
        return

    ops = sorted(t[len("successfor_"):] for t in series if t.startswith("successfor_"))
    rows = [(op, series[f"successfor_{op}"], series.get(f"errorsfor_{op}", [])) for op in ops]
    if "result_success" in series:
        rows.append(("ALL", series["result_success"],
                     [i for op in ops for i in series.get(f"errorsfor_{op}", [])]))

    ref = series.get("result_success") or next(iter(series.values()))
    s_all = summarize(ref)
    print(f"Duration: {s_all['duration']:,.1f}s in {len(ref)} intervals "
          f"(steady state excludes first/last interval when there are 4+)")
    if not ops:
        print("Note: no per-op timers found; run with INSTRUMENT_OPS=true to split reads and writes.")
    print("-" * 100)

    header = (f"{'Operation':<16}{'Ops':>12}{'Mix':>7}{'Ops/s':>10}{'Steady':>10}{'Peak':>10}"
              f"{'p50':>9}{'p90':>9}{'p99':>9}{'p99.9':>9}{'Max':>10}{'Errors':>9}")
    print(header)
    print(f"{'':<16}{'':>12}{'':>7}{'(avg)':>10}{'ops/s':>10}{'ops/s':>10}"
          f"{'ms':>9}{'ms':>9}{'ms':>9}{'ms':>9}{'ms':>10}{'':>9}")
    total_ok = s_all["count"] if s_all else 0
    for name, intervals, errs in rows:
        s = summarize(intervals)
        if not s:
            continue
        errors = int(sum(i.v["count"] for i in errs))
        mix = f"{100 * s['count'] / total_ok:.0f}%" if total_ok and name != "ALL" else ""
        print(f"{name:<16}{int(s['count']):>12,}{mix:>7}{s['rate']:>10,.0f}{s['steady_rate']:>10,.0f}"
              f"{s['peak_rate']:>10,.0f}{fmt_ms(s['p50']):>9}{fmt_ms(s['p90']):>9}{fmt_ms(s['p99']):>9}"
              f"{fmt_ms(s['p999']):>9}{fmt_ms(s['max']):>10}{errors:>9,}")

    response = summarize(series.get("cycles_responsetime", []))
    if response and response["count"] > 0:
        r = response
        print(f"{'response time*':<16}{'':>12}{'':>7}{'':>10}{'':>10}{'':>10}"
              f"{fmt_ms(r['p50']):>9}{fmt_ms(r['p90']):>9}{fmt_ms(r['p99']):>9}{fmt_ms(r['p999']):>9}"
              f"{fmt_ms(r['max']):>10}")
    print("-" * 100)
    print("Percentiles are count-weighted averages of per-interval percentiles (approximate); "
          "Max is exact.")
    if response and response["count"] > 0:
        print("* response time includes time queued behind the rate limiter; if it is much higher than "
              "service\n  latency, the client could not keep up with MAIN_RATE (add threads or lower the rate).")

    if timeline:
        print_timeline(series, ops)
    print()


def print_timeline(series, ops):
    ref = series.get("result_success")
    if not ref:
        return
    by_start = lambda tag: {round(i.start): i for i in series.get(tag, [])}
    per_op = {op: by_start(f"successfor_{op}") for op in ops}
    print()
    head = f"{'t(s)':>7}{'ops/s':>10}{'p50 ms':>9}{'p99 ms':>9}"
    for op in ops:
        head += f"{op + ' p99':>{max(14, len(op) + 6)}}"
    print(head)
    for i in trim(ref):
        rate = i.v["count"] / i.length if i.length else 0
        line = (f"{i.end:>7.0f}{rate:>10,.0f}{fmt_ms(i.v['p50'] / NS_PER_MS):>9}"
                f"{fmt_ms(i.v['p99'] / NS_PER_MS):>9}")
        for op in ops:
            oi = per_op[op].get(round(i.start))
            cell = fmt_ms(oi.v["p99"] / NS_PER_MS) if oi and oi.v["count"] else "-"
            line += f"{cell:>{max(14, len(op) + 6)}}"
        print(line)


def find_files(paths):
    files = []
    for p in paths:
        if os.path.isdir(p):
            found = sorted(os.path.join(p, f) for f in os.listdir(p) if f.endswith("_histostats.csv"))
            # rampup before main
            found.sort(key=lambda f: (0 if os.path.basename(f).startswith("rampup") else 1, f))
            if not found:
                print(f"No *_histostats.csv files in {p}", file=sys.stderr)
            files.extend(found)
        elif os.path.isfile(p):
            files.append(p)
        else:
            print(f"Not found: {p}", file=sys.stderr)
    return files


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("paths", nargs="+", help="histostats file(s) or metrics directories")
    ap.add_argument("--timeline", action="store_true", help="also print throughput/latency per interval")
    args = ap.parse_args()

    files = find_files(args.paths)
    if not files:
        return 1
    for f in files:
        print_phase(f, args.timeline)
    return 0


if __name__ == "__main__":
    sys.exit(main())
