#!/usr/bin/env python3
"""The held-out tasks, chosen without looking at them.

    bench/tb2/select.py TB2_DIR [N]        (N defaults to 10)

Every task directory under TB2_DIR that is not named in bench/tb2/tasks-seen.txt, ordered by
sha256(SALT + name), smallest first; the first N are printed. Nothing of a task
is read but its name: a set picked after reading tasks, or after seeing results, measures
the picking.

bench/tb2/tasks-unbuildable.txt names tasks whose container cannot be built on this machine.
They are skipped and the next in the order takes the place; the file says why for each.
"""
import hashlib
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
# The salt the sets were first picked with, under an older name of this work. Changing it
# would pick other tasks: it stays.
SALT = "famulus7-0.1:"


def names(path: Path) -> set:
    if not path.exists():
        return set()
    return {l.split()[0] for l in path.read_text().splitlines() if l.strip() and not l.startswith("#")}


def order(tasks: list) -> list:
    return sorted(tasks, key=lambda t: hashlib.sha256((SALT + t).encode()).hexdigest())


def main(argv: list) -> int:
    if len(argv) < 2:
        print(__doc__, file=sys.stderr)
        return 2
    n = int(argv[2]) if len(argv) > 2 else 10
    tb2 = Path(argv[1])
    every = sorted(p.name for p in tb2.iterdir() if (p / "task.toml").is_file())
    out = names(HERE / "tasks-seen.txt") | names(HERE / "tasks-unbuildable.txt")
    for t in order([t for t in every if t not in out])[:n]:
        print(t)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
