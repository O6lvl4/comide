#!/usr/bin/env python3
"""Harbor's job directory, as the results.tsv bench/tb2/summary.py reads.

    bench/tb2/results.py RUN_DIR [MODEL]

Harbor writes one result.json per trial, somewhere under the job directory. Each becomes
one row of RUN_DIR/results.tsv:

    tb2 <TAB> task <TAB> PASS|FAIL <TAB> 1 <TAB> cost <TAB> wall seconds <TAB> note <TAB> steps <TAB> output tokens

A task passes when its own tests gave a reward of 1. A trial that ended in an exception
with no reward (a container that would not build, a timeout before the tests ran) is a
FAIL, and the note says which exception: a task the agent never got to try still counts
against the setup, because the run was asked to do it.

The cost is the agent's own when it wrote one, and otherwise worked out from the recorded
tokens (bench/tb2/cost.py). Steps and output tokens are how much the agent did and wrote: two
agents on one model that differ fivefold there are not doing the same work.

A trial directory with no result.json is a trial that was stopped (the cost limit, a
kill). It gets a row too, FAIL with the note `stopped`, so a stopped run cannot be read
as a short one.
"""
import json
import sys
from datetime import datetime
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import cost  # noqa: E402


def seconds(timing) -> str:
    try:
        a = datetime.fromisoformat(timing["started_at"])
        b = datetime.fromisoformat(timing["finished_at"])
        return str(int((b - a).total_seconds()))
    except (TypeError, KeyError, ValueError):
        return ""


def work(trial: Path) -> tuple:
    steps, out = 0, 0
    for p in sorted((trial / "agent").glob("trajectory*.json")):
        try:
            for s in json.loads(p.read_text()).get("steps") or []:
                m = s.get("metrics") or {}
                if m:
                    steps += 1
                    out += m.get("completion_tokens") or 0
        except (OSError, ValueError):
            pass
    return (str(steps) if steps else "", str(out) if steps else "")


def task_of(trial: Path) -> str:
    try:
        cfg = json.loads((trial / "config.json").read_text())
        return str((cfg.get("task") or {}).get("path") or trial.name).rstrip("/").split("/")[-1]
    except (OSError, ValueError):
        return trial.name.split("__")[0]


def row(trial: Path, price: tuple) -> list:
    spent = cost.of_trial(trial, price)
    steps, out = work(trial)
    try:
        r = json.loads((trial / "result.json").read_text())
    except (OSError, ValueError):
        return ["tb2", task_of(trial), "FAIL", "1", f"{spent:.4f}", "", "stopped", steps, out]
    rewards = (r.get("verifier_result") or {}).get("rewards") or {}
    passed = bool(rewards) and all(float(v) >= 1.0 for v in rewards.values())
    exc = (r.get("exception_info") or {}).get("exception_type") or ""
    note = exc if exc else ("" if rewards else "no reward")
    return ["tb2", r["task_name"].split("/")[-1], "PASS" if passed else "FAIL", "1",
            f"{spent:.4f}", seconds(r.get("agent_execution")), note, steps, out]


def main(argv: list) -> int:
    if len(argv) < 2:
        print(__doc__, file=sys.stderr)
        return 2
    run = Path(argv[1])
    model = argv[2] if len(argv) > 2 else "@cf/zai-org/glm-5.3"
    if model not in cost.PRICES:
        print(f"no price for {model}: add it to bench/tb2/cost.py with where it was read", file=sys.stderr)
        return 2
    rows = sorted((row(t, cost.PRICES[model]) for t in cost.trial_dirs(run)), key=lambda x: x[1])
    if not rows:
        print(f"{run}: no trials", file=sys.stderr)
        return 1
    (run / "results.tsv").write_text("".join("\t".join(x) + "\n" for x in rows))
    for x in rows:
        print(f"{x[2]:<5} {x[1]:<36} ${x[4]:<8} {x[5] or '?':>5}s {x[7] or '?':>4} steps {x[8] or '?':>7} out  {x[6]}")
    passed = sum(1 for x in rows if x[2] == "PASS")
    print(f"\n{passed}/{len(rows)} passed, ${sum(float(x[4] or 0) for x in rows):.4f}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
