#!/usr/bin/env bash
# comide on Terminal-Bench 2.0, through Harbor, on this machine's Docker.
#
#   bench/tb2/run.sh                                  every task
#   TASKS="cancel-async-tasks fix-git" bench/tb2/run.sh
#   CONFINE=none N=4 bench/tb2/run.sh
#
# The task images are built from each task's Dockerfile (--force-build), not pulled: the
# published ones are amd64 only, and built here they are native to the host, which is
# what the bundle (bench/tb2/build-bundle.sh) was built for. That is the one way this
# differs from the leaderboard's runs.
#
#   MODEL     comide's model, as Harbor's provider/model  (default: cf/glm-5.3-flash)
#   CONFINE   app (porta) or none                         (default: app)
#   TASKS     task names; empty = all
#   N         tasks in parallel                           (default: 2)
#   MAX_STEPS comide's --max-steps                        (default: 200; the task's own
#             agent timeout, 15 minutes on most, is what really ends a run. comide's
#             default of 40 cut off 5 of the first 11 tasks mid-work)
#   BUNDLE    the Linux bundle                            (default: $TMPDIR/comide-tb2/bundle)
#   TB2       the terminal-bench-2 checkout               (default: ~/workspace/github.com/harbor-framework/terminal-bench-2)
#   HARBOR    the harbor executable                       (default: the checkout's .venv)
#   JOBS_DIR  where Harbor writes the results             (default: $TMPDIR/comide-tb2/jobs)
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GH="$HOME/workspace/github.com/harbor-framework"
MODEL="${MODEL:-cf/glm-5.3-flash}"
CONFINE="${CONFINE:-app}"
N="${N:-2}"
BUNDLE="${BUNDLE:-${TMPDIR:-/tmp}/comide-tb2/bundle}"
TB2="${TB2:-$GH/terminal-bench-2}"
HARBOR="${HARBOR:-$GH/harbor/.venv/bin/harbor}"
JOBS_DIR="${JOBS_DIR:-${TMPDIR:-/tmp}/comide-tb2/jobs}"

[ -x "$BUNDLE/bin/comide" ] || { echo "no bundle at $BUNDLE: run bench/tb2/build-bundle.sh" >&2; exit 2; }
[ -d "$TB2" ] || { echo "no terminal-bench-2 at $TB2" >&2; exit 2; }

# The credentials, from the same .env golemide and comide read, into this process only:
# Harbor passes them to the agent, and the agent to comide by name.
envfile="${XDG_CONFIG_HOME:-$HOME/.config}/golemide/.env"
if [ -f "$envfile" ]; then set -a; . "$envfile"; set +a; fi

include=()
for t in ${TASKS:-}; do include+=(-i "$t"); done

export COMIDE_TB2_BUNDLE="$BUNDLE" COMIDE_TB2_CONFINE="$CONFINE"
export COMIDE_TB2_MAX_STEPS="${MAX_STEPS:-200}"
export PYTHONPATH="$HERE${PYTHONPATH:+:$PYTHONPATH}"

echo "== comide $(awk '$1=="comide"{print $2}' "$BUNDLE/SOURCES") · $MODEL · confine=$CONFINE · max-steps=$COMIDE_TB2_MAX_STEPS · ${TASKS:-all tasks} · n=$N"
exec "$HARBOR" run -p "$TB2" "${include[@]}" \
  --agent-import-path comide_agent:Comide -m "$MODEL" \
  --force-build -n "$N" -o "$JOBS_DIR" \
  --job-name "comide-$CONFINE-$(date +%Y%m%d-%H%M%S)"
