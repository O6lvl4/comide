#!/bin/sh
# A stand-in for `harbor run`, for ci/check.sh: it calls no model and starts no container.
# It makes the job directory Harbor would (-o DIR --job-name NAME), with one trial per
# task named by -i, and writes into each trial what terminus-2 writes.
#
#   FAKE_MODE=finish    every trial records one step and a result: the first task passes,
#                       the others fail; then it exits 0
#   FAKE_MODE=forever   every trial records another step each second and never finishes,
#                       until it is interrupted
#
# A step is 1,000,000 prompt tokens, none cached, and no output: $1.40 at glm-5.3's price.
set -eu
out=""; job="job"; tasks=""
while [ $# -gt 0 ]; do
  case $1 in
    -o) out=$2; shift 2 ;;
    --job-name) job=$2; shift 2 ;;
    -i) tasks="$tasks $2"; shift 2 ;;
    *) shift ;;
  esac
done
[ -n "$out" ] || { echo "fake harbor: no -o" >&2; exit 2; }

step='{"metrics": {"prompt_tokens": 1000000, "cached_tokens": 0, "completion_tokens": 0}}'
write() { # write TRIAL_DIR STEPS
  left=$2; steps=""
  while [ "$left" -gt 0 ]; do steps="$steps${steps:+, }$step"; left=$((left - 1)); done
  printf '{"steps": [%s]}\n' "$steps" > "$1/agent/trajectory.json"
}
for t in $tasks; do
  d="$out/$job/${t}__fake"
  mkdir -p "$d/agent"
  printf '{"task": {"path": "tb2/%s"}}\n' "$t" > "$d/config.json"
  write "$d" 1
done

if [ "${FAKE_MODE:-finish}" = finish ]; then
  first=1
  for t in $tasks; do
    d="$out/$job/${t}__fake"
    printf '{"task_name": "tb2/%s", "trial_name": "%s__fake", "verifier_result": {"rewards": {"reward": %s}}}\n' "$t" "$t" "$first" > "$d/result.json"
    first=0
  done
  exit 0
fi

trap 'echo interrupted > "$out/$job/interrupted"; exit 130' INT TERM
n=1
while :; do
  sleep 1
  n=$((n + 1))
  for t in $tasks; do write "$out/$job/${t}__fake" "$n"; done
done
