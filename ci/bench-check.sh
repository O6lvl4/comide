#!/bin/sh
# The measuring rig (bench/tb2/measure.sh and the scripts beside it), checked end to end.
# No model is called and no container is started: Harbor is stood in for by
# ci/fake-harbor.sh.
#
#   ci/bench-check.sh
set -u

here=$(cd "$(dirname "$0")/.." && pwd)
cd "$here" || exit 1
rig=bench/tb2
fails=0
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

say()  { printf '%s\n' "$*"; }
bad()  { say "FAIL: $*"; fails=$((fails + 1)); }
same() { # same WHAT EXPECTED ACTUAL
  if [ "$2" = "$3" ]; then say "ok: $1"; else bad "$1"; say "  expected: $2"; say "  actual:   $3"; fi
}
has()  { # has WHAT NEEDLE FILE
  if grep -q -- "$2" "$3" 2>/dev/null; then say "ok: $1"; else bad "$1"; say "  no '$2' in $3"; fi
}

# A credentials file with nothing real in it.
mkdir -p "$tmp/tb2"
printf 'CLOUDFLARE_ACCOUNT_ID=acct\nCLOUDFLARE_API_TOKEN=tok\n' > "$tmp/keys.env"
printf 'alpha\nbeta\n# a comment\n\ngamma\n' > "$tmp/tasks.txt"
run() { # run NAME MODE LIMIT [TASK...]
  name=$1; mode=$2; limit=$3; shift 3
  KEYS="$tmp/keys.env" TB2="$tmp/tb2" HARBOR="$here/ci/fake-harbor.sh" FAKE_MODE=$mode LIMIT=$limit POLL=1 GRACE=5 \
    BENCH_WORK="$tmp/$name" sh $rig/measure.sh terminus-2 "$tmp/tasks.txt" "$@" > "$tmp/$name.out" 2> "$tmp/$name.err"
}

say "== the cost of a run is read from the tokens its trials recorded"
mkdir -p "$tmp/c/job/t__x/agent"
echo '{}' > "$tmp/c/job/t__x/config.json"
echo '{"steps": [{"metrics": {"prompt_tokens": 1000000, "cached_tokens": 500000, "completion_tokens": 100000}}, {"source": "user"}]}' > "$tmp/c/job/t__x/agent/trajectory.json"
same "fresh input, cached input and output each at their own price" "1.2700" "$(python3 $rig/cost.py "$tmp/c")"
mkdir -p "$tmp/c/job/u__x/agent"
echo '{}' > "$tmp/c/job/u__x/config.json"
echo '$0.5000' > "$tmp/c/job/u__x/agent/cost.txt"
same "an agent that wrote its own cost is taken at its word" "1.7700" "$(python3 $rig/cost.py "$tmp/c")"
python3 $rig/cost.py "$tmp/c" no-such-model > /dev/null 2>&1
same "a model with no price is refused, not counted as free" "2" "$?"

say "== a run that finishes"
run done-1 finish 100; code=$?
same "exit 0" "0" "$code"
same "one row per task in the file, comments and blank lines left out" "3" "$(grep -c . "$tmp/done-1/results.tsv")"
same "the first passed and the others failed, as the stand-in decided" "PASS FAIL FAIL" "$(cut -f3 "$tmp/done-1/results.tsv" | tr '\n' ' ' | sed 's/ $//')"
same "each row has the cost, the steps and the output tokens" "1.4000 1 0" "$(awk -F'\t' 'NR == 1 { print $5, $8, $9 }' "$tmp/done-1/results.tsv")"
has "the conditions name the limit" "limit_usd: 100" "$tmp/done-1/conditions"
has "the conditions name the tasks file" "tasks_file: tasks.txt" "$tmp/done-1/conditions"
if grep -q '^stopped:' "$tmp/done-1/conditions"; then bad "a run that finished is not marked stopped"; else say "ok: a run that finished is not marked stopped"; fi

say "== only the tasks named"
run named finish 100 beta; code=$?
same "one row" "beta" "$(cut -f2 "$tmp/named/results.tsv")"

say "== a run that reaches its limit is stopped"
run capped forever 5; code=$?
same "exit 3" "3" "$code"
has "the conditions say it was stopped, and is not the whole set" "^stopped: the cost limit of \$5 was reached" "$tmp/capped/conditions"
same "every trial cut off is a row marked stopped" "stopped stopped stopped" "$(cut -f7 "$tmp/capped/results.tsv" | tr '\n' ' ' | sed 's/ $//')"
same "and none of them passed" "FAIL FAIL FAIL" "$(cut -f3 "$tmp/capped/results.tsv" | tr '\n' ' ' | sed 's/ $//')"
if [ -f "$tmp/capped/"*/interrupted ]; then say "ok: Harbor was interrupted, so it can take its containers down"; else bad "Harbor was not interrupted"; fi
spent=$(awk -F'\t' '{ c += $5 } END { print c }' "$tmp/capped/results.tsv")
if awk -v s="$spent" 'BEGIN { exit !(s >= 5 && s < 20) }'; then say "ok: it stopped soon after the limit (\$$spent against \$5)"; else bad "it ran on to \$$spent against a limit of \$5"; fi

say "== no limit, no run; no credentials file, no run"
KEYS="$tmp/keys.env" TB2="$tmp/tb2" HARBOR="$here/ci/fake-harbor.sh" BENCH_WORK="$tmp/nolimit" sh $rig/measure.sh terminus-2 "$tmp/tasks.txt" > /dev/null 2> "$tmp/nolimit.err"
same "exit 2" "2" "$?"
has "it says what is missing" "LIMIT is not set" "$tmp/nolimit.err"
if [ -e "$tmp/nolimit" ]; then bad "nothing is started without a limit"; else say "ok: nothing is started without a limit"; fi
env -u KEYS TB2="$tmp/tb2" HARBOR="$here/ci/fake-harbor.sh" LIMIT=1 BENCH_WORK="$tmp/nokeys" sh $rig/measure.sh terminus-2 "$tmp/tasks.txt" > /dev/null 2> "$tmp/nokeys.err"
same "exit 2" "2" "$?"
has "it says what is missing" "KEYS must name a file" "$tmp/nokeys.err"
if [ -e "$tmp/nokeys" ]; then bad "nothing is started without credentials"; else say "ok: nothing is started without credentials"; fi

say "== summary.py"
run done-2 finish 100 > /dev/null
python3 $rig/summary.py "$tmp/done-1" "$tmp/done-2" > "$tmp/summary.out" 2>&1
has "two runs of one setup: the mean and the band" "mean: 1.0/3" "$tmp/summary.out"
has "the band" "band: 0 tasks" "$tmp/summary.out"
python3 $rig/summary.py "$tmp/done-1" "$tmp/named" > /dev/null 2>&1
same "runs over different tasks are refused, not averaged" "1" "$?"

say "== merge.py"
mkdir -p "$tmp/m1" "$tmp/m2"
printf 'limit_usd: 1\n' > "$tmp/m1/conditions"
printf 'tb2\talpha\tFAIL\t1\t0.0000\t\tRuntimeError\t\t\ntb2\tbeta\tFAIL\t1\t0.5000\t900\tAgentTimeoutError\t9\t100\n' > "$tmp/m1/results.tsv"
printf 'tb2\talpha\tPASS\t1\t0.2000\t60\t\t4\t50\ntb2\tbeta\tPASS\t1\t0.1000\t60\t\t3\t40\n' > "$tmp/m2/results.tsv"
printf 'alpha\nbeta\n' > "$tmp/two.txt"
python3 $rig/merge.py "$tmp/m" "$tmp/two.txt" "$tmp/m1" "$tmp/m2" > /dev/null
same "a trial that never started is taken from its rerun" "PASS" "$(awk -F'\t' '$2 == "alpha" { print $3 }' "$tmp/m/results.tsv")"
same "a trial that started is never replaced: a rerun is not a second chance" "FAIL" "$(awk -F'\t' '$2 == "beta" { print $3 }' "$tmp/m/results.tsv")"
has "the conditions say which row came from a rerun" "note: alpha did not start" "$tmp/m/conditions"
printf 'alpha\nbeta\ngamma\n' > "$tmp/three.txt"
python3 $rig/merge.py "$tmp/mm" "$tmp/three.txt" "$tmp/m1" "$tmp/m2" > /dev/null 2>&1
same "a task with no row at all is an error, not a shorter run" "1" "$?"

say "== select.py"
for t in a b c d e f; do mkdir -p "$tmp/sel/$t"; : > "$tmp/sel/$t/task.toml"; done
mkdir -p "$tmp/sel/not-a-task"
first=$(python3 $rig/select.py "$tmp/sel" 3 | tr '\n' ' ')
same "the same names give the same choice" "$first" "$(python3 $rig/select.py "$tmp/sel" 3 | tr '\n' ' ')"
same "it chooses as many as asked" "3" "$(python3 $rig/select.py "$tmp/sel" 3 | grep -c .)"
if python3 $rig/select.py "$tmp/sel" 9 | grep -q not-a-task; then bad "a directory with no task.toml is not a task"; else say "ok: a directory with no task.toml is not a task"; fi

say "== the two sets of tasks"
same "ten tasks to think with" "10" "$(grep -v '^#' $rig/tasks-dev.txt | grep -c .)"
same "ten tasks held out" "10" "$(grep -v '^#' $rig/tasks-held-out.txt | grep -c .)"
both=$(grep -v '^#' $rig/tasks-held-out.txt | grep . | while read -r t; do grep -qx "$t" $rig/tasks-seen.txt && echo "$t"; done | tr '\n' ' ')
same "no held-out task is one that was seen" "" "$both"
both=$(grep -v '^#' $rig/tasks-held-out.txt | grep . | while read -r t; do grep -qx "$t" $rig/tasks-dev.txt && echo "$t"; done | tr '\n' ' ')
same "nor one of the tasks to think with" "" "$both"

say ""
if [ "$fails" -eq 0 ]; then say "all bench checks passed"; else say "$fails failed"; exit 1; fi
