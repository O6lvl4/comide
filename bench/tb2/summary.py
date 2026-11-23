#!/usr/bin/env python3
"""Runs of one instrument, side by side, and the band between them.

    bench/tb2/summary.py RUN_DIR [RUN_DIR...]

Each RUN_DIR holds a results.tsv (group, task, PASS|FAIL, attempts, cost, wall) and a
conditions file. Prints one line per run, then the mean, the lowest and the highest, and
the band (highest minus lowest) in tasks and in points. Two setups differ only when the
gap between them is wider than that band.

Runs measured under different conditions are refused rather than averaged: a mean over
two different things is a number about neither.
"""
import sys
from pathlib import Path

# What must match for runs to be the same measurement. The date and the rig's commit
# change between runs of one baseline and do not change what is measured.
SAME = ("instrument", "edit", "edit_strong", "talk", "languages", "tasks", "attempts",
        "limit_per_language", "instructions", "effort", "confirm_done", "ask", "settings", "binary", "confine", "strong_after", "golemide", "comide", "polyglot-benchmark", "terminal-bench-2")


def conditions(run: Path) -> dict:
    out = {}
    for line in (run / "conditions").read_text().splitlines():
        key, sep, val = line.partition(": ")
        if sep:
            out[key] = val
    return out


def rows(run: Path) -> list:
    return [l.split("\t") for l in (run / "results.tsv").read_text().splitlines() if l.strip()]


def measured(cond: dict) -> dict:
    return {k: cond[k] for k in SAME if k in cond}


def main(argv: list) -> int:
    if len(argv) < 2:
        print(__doc__, file=sys.stderr)
        return 2
    runs = [Path(a) for a in argv[1:]]
    first = measured(conditions(runs[0]))
    for run in runs[1:]:
        other = measured(conditions(run))
        if other != first:
            diff = sorted(k for k in set(first) | set(other) if first.get(k) != other.get(k))
            print(f"{run}: not the same measurement as {runs[0]} (differs in: {', '.join(diff)})", file=sys.stderr)
            return 1

    for k, v in first.items():
        print(f"{k}: {v}")
    print()
    print(f"{'RUN':<28}{'SOLVED':>10}{'RATE':>8}{'COST':>10}")
    solved, costs, totals = [], [], set()
    for run in runs:
        r = rows(run)
        p = sum(1 for x in r if x[2] == "PASS")
        c = sum(float(x[4] or 0) for x in r)
        solved.append(p)
        costs.append(c)
        totals.add(len(r))
        print(f"{run.name:<28}{f'{p}/{len(r)}':>10}{p / len(r) * 100:>7.1f}%{c:>10.4f}")
    if len(totals) != 1:
        print(f"the runs do not have the same number of tasks: {sorted(totals)}", file=sys.stderr)
        return 1
    n = totals.pop()
    lo, hi, mean = min(solved), max(solved), sum(solved) / len(solved)
    print()
    print(f"runs: {len(runs)}   tasks: {n}")
    print(f"mean: {mean:.1f}/{n} ({mean / n * 100:.1f}%)   lowest: {lo} ({lo / n * 100:.1f}%)   highest: {hi} ({hi / n * 100:.1f}%)")
    print(f"band: {hi - lo} tasks ({(hi - lo) / n * 100:.1f} points)")
    print(f"cost: mean ${sum(costs) / len(costs):.4f} per run, ${sum(costs):.4f} in all")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
