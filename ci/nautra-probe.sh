#!/bin/sh
# What the terminal of comide under nautra can and cannot reach, tried from inside it.
#
#   ci/nautra-probe.sh DIR PORT READS
#
# DIR must not be under /tmp: every sandboxed command may write there (nautra's rule), so a
# workspace there cannot show that its parent is closed. A stand-in model (ci/fake-model.py)
# tells the terminal to try each thing; what the terminal answered is printed, one line a
# try, as NAME=EXIT.
set -eu
here=$(cd "$(dirname "$0")/.." && pwd)
P=$1; port=$2; reads=$3
mkdir -p "$P/fake" "$P/root" "$P/runs" "$P/keys"
echo "SECRET_IN_FILE=file-key-999" > "$P/keys/.env"

python3 - "$P/fake" "$P" "$port" <<'EOF'
import json, sys
fake, P, port = sys.argv[1:4]
def say(commands, done=False):
    return {"content": json.dumps({"analysis": "a", "plan": "p", "commands": commands, "task_complete": done})}
probe = [
    {"command": f"cat {P}/keys/.env; echo keyfile=$?"},
    {"command": "echo \"held=[$LOCAL_API_KEY]\"; env | grep -c real-key; echo envkey=$?"},
    {"command": "echo x > ../outside.txt; echo sibling=$?"},
    {"command": "echo x > ~/comide-probe-escape.txt; echo home=$?"},
    {"command": "curl -sS -m 5 -o /dev/null https://example.com; echo net=$?"},
    {"command": f"curl -sS -m 5 -o /dev/null http://127.0.0.1:{port}/v1/chat/completions -d '{{}}'; echo model=$?"},
    {"command": "grep -c real-key ../runs/*/comide.toml; echo composition=$?"},
    {"command": "ls ~/.ssh > /dev/null; echo ssh=$?"},
    {"command": "python3 -c 'print(6*7)'; git --version > /dev/null; echo tools=$?"},
    {"command": "echo ok > in.txt && cat in.txt; echo inside=$?"},
    # One terminal across calls: the directory and the variable are still there, and a
    # command that outlasts its wait can be waited for again. (Jobs are numbered from 1,
    # and comide's own first look is job 1: these are jobs 12 to 14.)
    {"command": "mkdir -p sub && cd sub && export WHO=tide"},
    {"command": "[ \"$(basename \"$PWD\")-$WHO\" = sub-tide ]; echo kept=$?"},
    {"command": "sleep 2; echo slept", "wait_s": 1},
    {"job": 14, "wait_s": 10},
    # Left running when the model says it is done: comide must end it.
    {"command": "sleep 321", "wait_s": 1},
]
for i, r in enumerate([say(probe), say([], done=True), say([], done=True)], 1):
    json.dump(r, open(f"{fake}/reply-{i}.json", "w"))
EOF

python3 "$here/ci/fake-model.py" "$port" "$P/fake" &
model=$!
trap 'kill $model 2>/dev/null || true' EXIT
sleep 1
code=0
LOCAL_API_KEY=the-real-key-777 READS=$reads DENY_READ="$P/keys" RUNS="$P/runs" MODEL=local:stand-in \
  PROVIDER_ENV="LOCAL_BASE_URL=http://127.0.0.1:$port/v1" PROVIDER_SECRET="LOCAL_API_KEY@127.0.0.1:$port" \
  PROVIDER_NET="127.0.0.1:$port" sh "$here/nautra/run.sh" "probe" --root "$P/root" > "$P/out.txt" 2>&1 || code=$?
echo "run=$code"
python3 - "$P" <<'EOF'
import json, re, sys
P = sys.argv[1]
sent = json.load(open(P + "/fake/request-2.json"))
said = sent["messages"][-1]["content"]
for line in said.split("\n"):
    if re.fullmatch(r"[a-z]+=\d+", line) or line.startswith("held="):
        print(line)
print("waited=" + str("(job 14)\nslept\n[exit code 0]" in said))
print("authorization=" + str(sent["authorization"]))
import subprocess
print("left-running=" + str(subprocess.run(["pgrep", "-f", "sleep 321"], capture_output=True).returncode == 0))
print("file-key-seen=" + str("file-key-999" in said))
import os, glob
everything = "".join(open(f, errors="replace").read() for f in glob.glob(P + "/runs/*/**", recursive=True) if os.path.isfile(f))
print("real-key-on-disk=" + str("the-real-key-777" in everything))
print("outside-written=" + str(os.path.exists(P + "/outside.txt")))
print("home-written=" + str(os.path.exists(os.path.expanduser("~/comide-probe-escape.txt"))))
EOF
