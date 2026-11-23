#!/bin/sh
# Several runs of one agent over one set of tasks, inside one budget.
#
#   bench/tb2/series.sh AGENT TASKS_FILE RUNS BUDGET NAME
#
#   AGENT       terminus-2, comide, errand or meta-harness (bench/tb2/measure.sh)
#   TASKS_FILE  the tasks
#   RUNS        how many runs
#   BUDGET      dollars for all of them together
#   NAME        the runs are written to $RUNS/NAME-raw-N (and NAME-raw-Nb for a rerun), and
#               put together as $RUNS/NAME-N   (RUNS defaults to ~/.cache/comide/bench/runs)
#
# Each run's limit is what is left of the budget. A run is not started when less than
# MIN_LEFT dollars are left (default 3.5: about one run of these agents on ten tasks), and
# the series ends at the first run its limit stops. A task that never started in a run (no
# step recorded, nothing spent) is run again alone, once, and the two are merged
# (merge.py); a task that started is never run again.
#
# Environment for the agent (KEYS, MAX_STEPS, COMIDE_CHECK, ...) passes through to measure.sh.
set -eu

here=$(cd "$(dirname "$0")/../.." && pwd)
rig=$here/bench/tb2
[ $# -eq 5 ] || { echo "usage: bench/tb2/series.sh AGENT TASKS_FILE RUNS BUDGET NAME" >&2; exit 2; }
agent=$1; tasks_file=$2; runs=$3; budget=$4; name=$5
# The budget is counted the way measure.sh counts a run's limit. For meta-harness that is
# with a share of each prompt taken as cached (cost.py); without it here, a series added up
# to more than three times what its runs were stopped at.
if [ "$agent" = meta-harness ]; then export ASSUMED_CACHED=${ASSUMED_CACHED:-0.9}; fi
R=${RUNS:-$HOME/.cache/comide/bench/runs}
mkdir -p "$R"

spent() {
  total=0
  for d in "$R"/"$name"-raw-*; do
    [ -d "$d" ] || continue
    total=$(awk -v a="$total" -v b="$(python3 "$rig/cost.py" "$d")" 'BEGIN { print a + b }')
  done
  echo "$total"
}

i=1
while [ "$i" -le "$runs" ]; do
  left=$(awk -v b="$budget" -v s="$(spent)" 'BEGIN { print b - s }')
  if awk -v l="$left" -v m="${MIN_LEFT:-3.5}" 'BEGIN { exit !(l < m) }'; then
    echo "run $i not started: \$$left left of \$$budget"
    break
  fi
  code=0
  LIMIT=$left BENCH_WORK="$R/$name-raw-$i" sh "$rig/measure.sh" "$agent" "$tasks_file" > "$R/$name-raw-$i.out" 2>&1 || code=$?
  if [ "$code" -eq 3 ]; then
    echo "run $i stopped at the limit"
    break
  fi
  again=$(awk -F'\t' '$8 == "" && $5 + 0 == 0 { print $2 }' "$R/$name-raw-$i/results.tsv" | tr '\n' ' ')
  dirs="$R/$name-raw-$i"
  if [ -n "$again" ]; then
    left=$(awk -v b="$budget" -v s="$(spent)" 'BEGIN { print b - s }')
    # shellcheck disable=SC2086
    N=1 LIMIT=$left BENCH_WORK="$R/$name-raw-${i}b" sh "$rig/measure.sh" "$agent" "$tasks_file" $again > "$R/$name-raw-${i}b.out" 2>&1 || true
    dirs="$dirs $R/$name-raw-${i}b"
  fi
  echo "== run $i (run again alone: ${again:-none})"
  # shellcheck disable=SC2086
  python3 "$rig/merge.py" "$R/$name-$i" "$tasks_file" $dirs || true
  i=$((i + 1))
done
echo "spent in all: \$$(spent)"
