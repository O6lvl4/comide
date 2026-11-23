#!/bin/sh
# Terminal-Bench 2 through Harbor, by one of several agents on the same model, inside a
# limit of dollars, so that what differs between two runs is the harness.
#
#   LIMIT=dollars bench/tb2/measure.sh AGENT TASKS_FILE [TASK...]   (TASK...: only these, of the file's)
#
#   AGENT   terminus-2    Harbor's own agent, as it ships: its own prompt, its own
#                         settings. The baseline. It calls the model from this machine
#                         and types into the task's terminal, so no key goes into a task.
#           comide        comide as a person would run it unattended: `comide -p TASK --yes`,
#                         the conversation's loop with every tool, from the bundle
#                         bench/tb2/build-bundle.sh made (BUNDLE), unconfined in the task's
#                         container. Its cost is what it wrote itself.
#           errand        `comide errand TASK`: the binary alone (bench/tb2/linux/build.sh),
#                         one terminal as its tool, put into the task's container and run
#                         there. The model's key goes in with it, unconfined, so the
#                         credentials file must hold nothing but a key made for measuring.
#           meta-harness  the agent published with the Meta-Harness paper (below).
#
#   LIMIT   dollars this run may cost; reaching it stops the run        (required)
#   KEYS    a file of NAME=VALUE lines holding CLOUDFLARE_ACCOUNT_ID and
#           CLOUDFLARE_API_TOKEN                                         (required)
#   MODEL   the Workers AI model id        (default: @cf/zai-org/glm-5.3)
#   N       tasks in parallel              (default: 2)
#   BIN     errand only: the Linux binary  (default: $TMPDIR/comide-linux/comide)
#   BUNDLE  comide only: the bundle        (default: $TMPDIR/comide-tb2/bundle)
#   MAX_STEPS  comide and errand: --max-steps   (default: 200 for comide, comide's own for errand)
#   RUNS    where runs are written, each in a directory of its own
#           (default: ~/.cache/comide/bench/runs; BENCH_WORK names one run's directory outright)
#   TB2, HARBOR  the terminal-bench-2 checkout and the harbor to run
#           (default: ~/workspace/github.com/harbor-framework/terminal-bench-2 and
#           .../harbor/.venv/bin/harbor)
#
# bench/tb2/run.sh is the other runner: every task, no limit, comide confined or not. This
# one is for comparing: a baseline, fixed sets of tasks (tasks-dev.txt, tasks-held-out.txt),
# rows and conditions written down (results.py, summary.py), several runs in one budget
# (series.sh).
#
# The limit is not optional. One task that runs to its timeout can cost more than the other
# nine together, and a run nobody is watching goes past what was meant to be spent. Here the
# cost is read from what the trials record as they go, every POLL seconds (cost.py), and at
# LIMIT the run is stopped; what was finished stays, and the trials cut off are rows marked
# `stopped` (results.py). A run stopped this way is not a measurement of the whole set, and
# its conditions file says so.
set -eu

here=$(cd "$(dirname "$0")/../.." && pwd)
rig=$here/bench/tb2
[ $# -ge 2 ] || { echo "usage: LIMIT=dollars bench/tb2/measure.sh terminus-2|comide|errand|meta-harness TASKS_FILE [TASK...]" >&2; exit 2; }
agent=$1; tasks_file=$2; shift 2
case $agent in terminus-2|comide|errand|meta-harness) ;; *) echo "no agent named $agent: terminus-2, comide, errand or meta-harness" >&2; exit 2 ;; esac
# meta-harness: the agent published with the Meta-Harness paper (stanford-iris-lab/
# meta-harness-tbench2-artifact), a subclass of terminus-2 that beat it with the same
# model on the official board. Run as published, like terminus-2: from this machine, no
# key in the task. Its source was read before it was run here (2026-11-20, 57fefdb): it
# reaches the network only through LiteLLM, with the address Harbor gives it.
META=${META:-$HOME/workspace/github.com/stanford-iris-lab/meta-harness-tbench2-artifact}
if [ "$agent" = meta-harness ]; then
  [ -f "$META/agent.py" ] || { echo "no Meta-Harness checkout at $META" >&2; exit 2; }
  # It records no cached tokens (cost.py): its cost is worked out as if this share of
  # every prompt was read from cache, and is an estimate.
  export ASSUMED_CACHED=${ASSUMED_CACHED:-0.9}
fi
[ -f "$tasks_file" ] || { echo "no tasks file at $tasks_file" >&2; exit 2; }
if [ $# -eq 0 ]; then set -- $(grep -v '^#' "$tasks_file" | grep -v '^$'); fi
[ -n "${LIMIT:-}" ] || { echo "LIMIT is not set: say how many dollars this run may cost" >&2; exit 2; }

MODEL=${MODEL:-@cf/zai-org/glm-5.3}
empty=$(mktemp -d)
python3 "$rig/cost.py" "$empty" "$MODEL" > /dev/null || { rmdir "$empty"; exit 2; }
rmdir "$empty"

[ -n "${KEYS:-}" ] && [ -f "$KEYS" ] || { echo "KEYS must name a file holding the model's credentials: a measurement runs on a key of its own" >&2; exit 2; }
set -a; . "$KEYS"; set +a

GH=$HOME/workspace/github.com/harbor-framework
TB2=${TB2:-$GH/terminal-bench-2}
HARBOR=${HARBOR:-$GH/harbor/.venv/bin/harbor}
stamp=$(date +%Y%m%d-%H%M%S)
work=${BENCH_WORK:-${RUNS:-$HOME/.cache/comide/bench/runs}/$agent-$stamp}

BIN=${BIN:-${TMPDIR:-/tmp}/comide-linux/comide}
if [ "$agent" = errand ]; then
  [ -f "$BIN" ] || { echo "no Linux build of comide at $BIN: run bench/tb2/linux/build.sh" >&2; exit 2; }
fi
BUNDLE=${BUNDLE:-${TMPDIR:-/tmp}/comide-tb2/bundle}
if [ "$agent" = comide ]; then
  [ -f "$BUNDLE/bin/comide" ] || { echo "no bundle of comide at $BUNDLE: run bench/tb2/build-bundle.sh" >&2; exit 2; }
fi
mkdir -p "$work"

commit_of() { git -C "$1" rev-parse --short HEAD 2>/dev/null || echo unknown; }
{
  if [ "$agent" = errand ]; then
    echo "instrument: tb2 (Terminal-Bench 2), through comide errand in each task's container"
  elif [ "$agent" = comide ]; then
    echo "instrument: tb2 (Terminal-Bench 2), through comide -p --yes in each task's container"
  elif [ "$agent" = meta-harness ]; then
    echo "instrument: tb2 (Terminal-Bench 2), through the published Meta-Harness agent"
    echo "cost: an estimate, taking $ASSUMED_CACHED of every prompt as read from cache (the agent records none)"
    echo "meta-harness: $(commit_of "$META")"
  else
    echo "instrument: tb2 (Terminal-Bench 2), through Harbor's terminus-2"
  fi
  echo "date: $(date +%Y-%m-%dT%H:%M:%S%z)"
  echo "talk: cf:$MODEL"
  echo "tasks_file: $(basename "$tasks_file")"
  echo "tasks: $*"
  echo "attempts: 1"
  echo "jobs: ${N:-2}"
  echo "limit_usd: $LIMIT"
  echo "rig: $(commit_of "$here")"
  if [ "$agent" = errand ]; then
    echo "binary: $(cat "$(dirname "$BIN")/SOURCE" 2>/dev/null || echo unknown)"
    echo "settings: max_tokens=${COMIDE_MAX_TOKENS:-default} max_steps=${MAX_STEPS:-default} reasoning_back=${COMIDE_REASONING_BACK:-1} check=${COMIDE_CHECK:-0}"
  elif [ "$agent" = comide ]; then
    echo "bundle:"; sed 's/^/  /' "$BUNDLE/SOURCES"
    echo "max_steps: ${MAX_STEPS:-200}"
  fi
  echo "harbor: $(commit_of "$GH/harbor")"
  echo "terminal-bench-2: $(commit_of "$TB2")"
  echo "host: $(uname -sm)"
} > "$work/conditions"
cat "$work/conditions"

include=""
for t in "$@"; do include="$include -i $t"; done

# Harbor is started through unignored.py, so that the interrupt at the limit reaches it and
# it takes its containers down. Not through a shell function: in the background that is a
# subshell, and the pid held would be the subshell's.
export PYTHONPATH="$rig${PYTHONPATH:+:$PYTHONPATH}"
# shellcheck disable=SC2086
if [ "$agent" = comide ]; then
  export COMIDE_TB2_BUNDLE="$BUNDLE" COMIDE_TB2_CONFINE=none COMIDE_TB2_MAX_STEPS="${MAX_STEPS:-200}"
  python3 "$rig/unignored.py" "$HARBOR" run -p "$TB2" $include --agent-import-path comide_agent:Comide -m "cf/$MODEL" \
    --force-build -n "${N:-2}" -o "$work" --job-name "comide-$stamp" > "$work/harbor.out" 2>&1 &
elif [ "$agent" = errand ]; then
  export COMIDE_ERRAND_BIN="$BIN" COMIDE_ERRAND_MODEL="cf:$MODEL" COMIDE_ERRAND_MAX_STEPS="${MAX_STEPS:-}"
  python3 "$rig/unignored.py" "$HARBOR" run -p "$TB2" $include --agent-import-path errand_agent:Errand -m "cf/$MODEL" \
    --force-build -n "${N:-2}" -o "$work" --job-name "errand-$stamp" > "$work/harbor.out" 2>&1 &
elif [ "$agent" = meta-harness ]; then
  export OPENAI_API_KEY="$CLOUDFLARE_API_TOKEN"
  export PYTHONPATH="$META:$PYTHONPATH"
  # It runs on the Harbor it was written for (0.1.45, with litellm below 1.82.7 as its
  # pyproject pins), in an environment of its own beside it: on the Harbor of today its
  # terminus-2 base has moved (AttributeError: _enable_summarize). That Harbor names a task
  # with -t.
  include=""
  for t in "$@"; do include="$include -t $t"; done
  python3 "$rig/unignored.py" "${META_HARBOR:-$META/.venv/bin/harbor}" run -p "$TB2" $include --agent-import-path agent:AgentHarness -m "openai/$MODEL" \
    --ak "api_base=https://api.cloudflare.com/client/v4/accounts/$CLOUDFLARE_ACCOUNT_ID/ai/v1" \
    --force-build -n "${N:-2}" -o "$work" --job-name "metaharness-$stamp" > "$work/harbor.out" 2>&1 &
else
  # Workers AI speaks the OpenAI chat-completions shape; LiteLLM reaches it as openai/MODEL.
  export OPENAI_API_KEY="$CLOUDFLARE_API_TOKEN"
  python3 "$rig/unignored.py" "$HARBOR" run -p "$TB2" $include -a terminus-2 -m "openai/$MODEL" \
    --ak "api_base=https://api.cloudflare.com/client/v4/accounts/$CLOUDFLARE_ACCOUNT_ID/ai/v1" \
    --force-build -n "${N:-2}" -o "$work" --job-name "terminus2-$stamp" > "$work/harbor.out" 2>&1 &
fi
harbor=$!

stopped=""
while kill -0 "$harbor" 2>/dev/null; do
  sleep "${POLL:-30}"
  spent=$(python3 "$rig/cost.py" "$work" "$MODEL")
  if awk -v s="$spent" -v l="$LIMIT" 'BEGIN { exit !(s >= l) }'; then
    stopped=$spent
    echo "the run has cost \$$spent, at or past the limit of \$$LIMIT: stopping it" >&2
    # Interrupt first, so Harbor takes its containers down; then insist.
    kill -INT "$harbor" 2>/dev/null || true
    i=0
    while kill -0 "$harbor" 2>/dev/null && [ $i -lt "${GRACE:-90}" ]; do sleep 1; i=$((i + 1)); done
    kill -TERM "$harbor" 2>/dev/null || true
    break
  fi
done
status=0
wait "$harbor" 2>/dev/null || status=$?

if [ -n "$stopped" ]; then
  echo "stopped: the cost limit of \$$LIMIT was reached at \$$stopped; this is not the whole set" >> "$work/conditions"
fi
python3 "$rig/results.py" "$work" "$MODEL" || true
[ -z "$stopped" ] || exit 3
exit $status
