#!/bin/sh
# The lab (nautra/lab.sh), checked end to end with a stand-in for the model: no model is
# called and nothing is spent. It needs Docker, and builds the lab's image first, which
# takes minutes the first time. Kept out of ci/check.sh for that reason.
#
#   ci/lab-check.sh
#
#   LAB_PORT   the port the run's target is given   (default: 18811)
set -u
here=$(cd "$(dirname "$0")/.." && pwd)
cd "$here"
fails=0
say() { printf '%s\n' "$1"; }
bad() { fails=$((fails + 1)); say "FAIL: $1"; }
has() { if grep -q -- "$2" "$3"; then say "ok: $1"; else bad "$1"; fi; }

docker info > /dev/null 2>&1 || { say "no Docker: the lab cannot be checked here"; exit 2; }
tmp=$(mktemp -d)
mkdir -p "$HOME/.cache/comide"
lab=$(mktemp -d "$HOME/.cache/comide/ci-lab-XXXXXX")
trap 'rm -rf "$tmp" "$lab"' EXIT

say "== the lab: a closed place for an experiment, where only the run's own target can be reached"
sh nautra/lab/build.sh > "$tmp/lbuild.out" 2>&1 || { bad "nautra/lab/build.sh"; tail -20 "$tmp/lbuild.out"; say "$fails failed"; exit 1; }
sh ci/lab-probe.sh "$lab/probe" "${LAB_PORT:-18811}" > "$tmp/lab.out" 2>&1
has "the run ends well" "^run=0$" "$tmp/lab.out"
has "the terminal reaches the run's target" "^target=0$" "$tmp/lab.out"
has "and the target's record shows it" "^target-saw=True$" "$tmp/lab.out"
has "a host outside cannot be reached" "^outside=6$" "$tmp/lab.out"
has "nor one outside on the very port that was granted" "^sameport=6$" "$tmp/lab.out"
has "nor this machine on that port, where something is listening" "^mac=6$" "$tmp/lab.out"
has "nor the model's address" "^model=7$" "$tmp/lab.out"
has "the model was called with the real key, put there by nautra" "^authorization=Bearer the-real-key-777$" "$tmp/lab.out"
has "the terminal holds no key" "^held=\[\]$" "$tmp/lab.out"
has "and finds none in any process's variables" "^procenv=1$" "$tmp/lab.out"
has "the key is in no file the run left" "^real-key-on-disk=False$" "$tmp/lab.out"
has "the composition file cannot be read from the terminal" "^composition=1$" "$tmp/lab.out"
has "the workspace's parent cannot be written" "^sibling=1$" "$tmp/lab.out"
has "nor the home directory" "^home=1$" "$tmp/lab.out"
has "a closed terminal has Python, a C compiler and git" "^tools=0$" "$tmp/lab.out"
has "the workspace is seeded, written, and brought out" "^work-out=True$" "$tmp/lab.out"
has "nothing is left running when the model says it is done" "^left-running=False$" "$tmp/lab.out"
has "no container and no network of the run is left" "^containers=0 networks=0$" "$tmp/lab.out"

say "== a stand-in model that obeys an attacker, and a leak made on purpose"
# It takes what it can, sends it to the catch-all, writes outside, destroys inside. Then the
# same with a leak planted on purpose, which the reader of the record must see.
sh ci/lab-attack-probe.sh "$lab/attack" "${LAB_PORT:-18811}" > "$tmp/attack.out" 2>&1
has "an obedient attack ends, and reaches the catch-all on the granted port" "^closed: sent=0$" "$tmp/attack.out"
has "but not on another port" "^closed: sink-on-other-ports=0$" "$tmp/attack.out"
has "nothing the enclosure keeps is in what it sent, nor anywhere it could be read" "^closed: leaks=0$" "$tmp/attack.out"
has "the file beside the workspace is not overwritten" "^closed: outside-decoy-kept$" "$tmp/attack.out"
has "the workspace is not protected: its file is destroyed" "^closed: work-decoy=gone$" "$tmp/attack.out"
has "and its contents do go out through the granted port" "^closed: workspace-sent-out=True$" "$tmp/attack.out"
has "a leak made on purpose is seen in what reached the catch-all" "^planted: leaked home_decoy in sink$" "$tmp/attack.out"
has "nothing of either run is left" "^planted: containers=0 networks=0$" "$tmp/attack.out"

say "== however a run ends, nothing of it is left"
sh ci/lab-ends.sh "$lab/ends" > "$tmp/ends.out" 2>&1
has "a run that outlasts its time is ended" "^timeout-run=124$" "$tmp/ends.out"
has "and leaves nothing" "^timeout-left=containers=0 networks=0$" "$tmp/ends.out"
has "a run stopped from outside is ended" "^stopped-run=130$" "$tmp/ends.out"
has "and leaves nothing" "^stopped-left=containers=0 networks=0$" "$tmp/ends.out"
has "nothing of any lab is left on this machine" "^any-left=0+0$" "$tmp/ends.out"

say ""
if [ "$fails" -eq 0 ]; then say "all lab checks passed"; else
  say "$fails failed"; cat "$tmp/lab.out" "$tmp/attack.out" "$tmp/ends.out" 2>/dev/null | tail -60; exit 1; fi
