#!/bin/sh
# Whether each task's container can be built and started on this machine, found out
# without calling a model: Harbor's `nop` agent does nothing, so a trial is the build, the
# start and the task's own tests (which fail, nothing having been done).
#
#   bench/tb2/buildable.sh TASK...
#
# Prints one line per task: `built`, or the exception Harbor ended the trial with. A task
# that does not build goes into bench/tb2/tasks-unbuildable.txt with that line as the reason,
# and bench/tb2/select.py then puts the next in its order in its place.
set -eu

[ $# -ge 1 ] || { echo "usage: bench/tb2/buildable.sh TASK..." >&2; exit 2; }
GH=$HOME/workspace/github.com/harbor-framework
TB2=${TB2:-$GH/terminal-bench-2}
HARBOR=${HARBOR:-$GH/harbor/.venv/bin/harbor}
work=${BENCH_WORK:-${RUNS:-$HOME/.cache/comide/bench/runs}/buildable-$(date +%Y%m%d-%H%M%S)}
mkdir -p "$work"

include=""
for t in "$@"; do include="$include -i $t"; done
"$HARBOR" run -p "$TB2" $include -a nop --force-build -n "${N:-2}" -o "$work" --job-name buildable > "$work/harbor.out" 2>&1 || true

python3 - "$work" "$@" <<'EOF'
import json, sys
from pathlib import Path
run, asked = Path(sys.argv[1]), sys.argv[2:]
seen = {}
for p in run.rglob("result.json"):
    try:
        r = json.loads(p.read_text())
    except (OSError, ValueError):
        continue
    if isinstance(r, dict) and "task_name" in r and "trial_name" in r:
        exc = (r.get("exception_info") or {}).get("exception_type")
        seen[r["task_name"].split("/")[-1]] = exc or "built"
for t in asked:
    print(t, seen.get(t, "no trial: see harbor.out"))
EOF
