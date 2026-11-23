#!/bin/sh
# However a run in the lab ends, nothing of it is left: tried with a run that outlasts its
# time, and with one that is stopped from outside while a command is running.
#
#   ci/lab-ends.sh DIR
#
# Prints NAME=VALUE lines: how each run ended and what it left.
set -eu
here=$(cd "$(dirname "$0")/.." && pwd)
P=$1
mkdir -p "$P/fake"
python3 - "$P/fake" <<'EOF'
import json, sys
long = {"content": json.dumps({"analysis": "a", "plan": "p", "task_complete": False,
                               "commands": [{"command": "sleep 600", "wait_s": 20}]})}
for i in range(1, 4):
    json.dump(long, open(f"{sys.argv[1]}/reply-{i}.json", "w"))
EOF
left() { tr '\n' ' ' < "$(ls -d "$1"/runs/* | tail -1)/left.txt" | sed 's/ $//'; }

code=0
LOCAL_API_KEY=k STAND_IN="$P/fake" TIMEOUT=15s sh "$here/nautra/lab.sh" "$P/timeout" "wait" > "$P/timeout.txt" 2>&1 || code=$?
echo "timeout-run=$code"
echo "timeout-left=$(left "$P/timeout")"

LOCAL_API_KEY=k STAND_IN="$P/fake" TIMEOUT=10m sh "$here/nautra/lab.sh" "$P/stopped" "wait" > "$P/stopped.txt" 2>&1 &
lab=$!
# Until the agent's box is up and its command is running.
n=0
while [ $n -lt 60 ] && ! grep -q "comide in the lab" "$P/stopped.txt" 2>/dev/null; do sleep 1; n=$((n + 1)); done
sleep 5
kill -TERM $lab
code=0
wait $lab || code=$?
echo "stopped-run=$code"
echo "stopped-left=$(left "$P/stopped")"
echo "any-left=$(docker ps -aq --filter label=comide.lab | wc -l | tr -d ' ')+$(docker network ls -q --filter label=comide.lab | wc -l | tr -d ' ')"
