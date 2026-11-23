#!/usr/bin/env python3
"""One run out of a run and the reruns of trials that never started.

    bench/tb2/merge.py OUT_DIR TASKS_FILE RUN_DIR [RERUN_DIR...]

A trial that ended before the agent did anything (no step recorded and nothing spent: the
container did not start, the agent's own setup timed out) says nothing about the agent.
Such a task is run again alone, and its row is taken from the latest RUN_DIR in which it
did start. A trial that started is never replaced: a rerun is not a second chance.

Writes OUT_DIR/results.tsv with the rows of TASKS_FILE's tasks, and OUT_DIR/conditions:
the first run's, with a note for every row that came from a rerun.
"""
import sys
from pathlib import Path


def rows(run: Path) -> dict:
    return {x[1]: x for x in (l.split("\t") for l in (run / "results.tsv").read_text().splitlines() if l.strip())}


def started(row: list) -> bool:
    return bool(row[7]) or float(row[4] or 0) > 0


def main(argv: list) -> int:
    if len(argv) < 4:
        print(__doc__, file=sys.stderr)
        return 2
    out, runs = Path(argv[1]), [Path(a) for a in argv[3:]]
    tasks = [l.strip() for l in Path(argv[2]).read_text().splitlines() if l.strip() and not l.startswith("#")]
    chosen, notes = {}, []
    for run in runs:
        for task, row in rows(run).items():
            if task not in chosen or (not started(chosen[task][1]) and started(row)):
                if task in chosen:
                    notes.append(f"note: {task} did not start in {chosen[task][0].name} ({chosen[task][1][6]}); its row is from {run.name}, run alone")
                elif run is not runs[0]:
                    notes.append(f"note: {task} is from {run.name}, run alone")
                chosen[task] = (run, row)
    missing = [t for t in tasks if t not in chosen]
    if missing:
        print(f"no row for: {' '.join(missing)}", file=sys.stderr)
        return 1
    out.mkdir(parents=True, exist_ok=True)
    (out / "results.tsv").write_text("".join("\t".join(chosen[t][1]) + "\n" for t in sorted(tasks)))
    cond = [l for l in (runs[0] / "conditions").read_text().splitlines() if not l.startswith("tasks: ")]
    cond.insert(3, "tasks: " + " ".join(tasks))
    (out / "conditions").write_text("\n".join(cond + notes) + "\n")
    rs = [chosen[t][1] for t in tasks]
    print(f"{sum(1 for r in rs if r[2] == 'PASS')}/{len(rs)} passed, ${sum(float(r[4] or 0) for r in rs):.4f}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
