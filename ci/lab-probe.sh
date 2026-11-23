#!/bin/sh
# What the terminal can and cannot reach inside the lab (nautra/lab.sh), tried from inside it.
#
#   ci/lab-probe.sh DIR PORT
#
# A stand-in model tells the terminal to try each thing; what the terminal answered is
# printed, one line a try, as NAME=EXIT. While it runs, something listens on PORT on this
# machine too: the lab's terminal is granted that port, and must still not reach it here.
set -eu
here=$(cd "$(dirname "$0")/.." && pwd)
P=$1; port=$2
mkdir -p "$P/fake" "$P/targets" "$P/work" "$P/mac"
echo "lab-hello" > "$P/targets/hello.txt"
echo "from-the-mac" > "$P/mac/hello.txt"
echo "seed" > "$P/work/seed.txt"

python3 - "$P/fake" "$port" <<'EOF'
import json, sys
fake, port = sys.argv[1:3]
def say(commands, done=False):
    return {"content": json.dumps({"analysis": "a", "plan": "p", "commands": commands, "task_complete": done})}
get = "curl -sS -m 5 -o /dev/null"
probe = [
    {"command": f"curl -sS -m 5 $TARGET/hello.txt | grep -q lab-hello; echo target=$?"},
    {"command": f"{get} http://127.0.0.1:18900/v1/chat/completions -d '{{}}'; echo model=$?"},
    {"command": f"{get} https://example.com; echo outside=$?"},
    {"command": f"{get} http://example.com:{port}/; echo sameport=$?"},
    {"command": f"{get} http://host.docker.internal:{port}/hello.txt; echo mac=$?"},
    {"command": "echo \"held=[$LOCAL_API_KEY]\"; cat /proc/*/environ 2>/dev/null | grep -ac the-real-key; echo procenv=$?"},
    {"command": "cat /lab/run/comide.toml > /dev/null; echo composition=$?"},
    {"command": "echo x > /lab/outside.txt; echo sibling=$?"},
    {"command": "echo x > ~/escape.txt; echo home=$?"},
    {"command": "python3 -c 'print(6*7)' && echo 'int main(){return 0;}' > t.c && cc t.c -o t && ./t && git init -q g; echo tools=$?"},
    {"command": "cat seed.txt > copy.txt; echo inside=$?"},
    # Left running when the model says it is done: comide must end it.
    {"command": "sleep 321", "wait_s": 1},
]
for i, r in enumerate([say(probe), say([], done=True), say([], done=True)], 1):
    json.dump(r, open(f"{fake}/reply-{i}.json", "w"))
EOF

python3 -m http.server "$port" --directory "$P/mac" > /dev/null 2>&1 &
mac=$!
trap 'kill $mac 2>/dev/null || true' EXIT
sleep 1

code=0
LOCAL_API_KEY=the-real-key-777 STAND_IN="$P/fake" PORT=$port TIMEOUT=5m \
  sh "$here/nautra/lab.sh" "$P" "probe" > "$P/out.txt" 2>&1 || code=$?
echo "run=$code"
python3 - "$P" <<'EOF'
import glob, json, os, re, sys
P = sys.argv[1]
run = sorted(glob.glob(P + "/runs/*"))[-1]
sent = json.load(open(run + "/fake/request-2.json"))
said = sent["messages"][-1]["content"]
for line in said.split("\n"):
    if re.fullmatch(r"[a-z]+=\d+", line) or line.startswith("held="):
        print(line)
print("authorization=" + str(sent["authorization"]))
print("left-running=" + str("sleep 321" in open(run + "/processes-at-end.txt").read()))
print("target-saw=" + str("hello.txt" in open(run + "/target.jsonl").read()))
print("work-out=" + str(os.path.exists(run + "/work/copy.txt")))
everything = "".join(open(f, errors="replace").read() for f in glob.glob(run + "/**", recursive=True)
                     if os.path.isfile(f) and "/fake/" not in f)
print("real-key-on-disk=" + str("the-real-key-777" in everything))
print(open(run + "/left.txt").read().strip().replace("\n", " "))
EOF
