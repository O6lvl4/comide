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
printf 'def unusual_name():\n    return 41 + 1\n' > "$P/root/hewn.py"
echo "SECRET_IN_FILE=file-key-999" > "$P/keys/.env"

python3 - "$P/fake" "$P" "$port" <<'EOF'
import json, sys
fake, P, port = sys.argv[1:4]
def say(commands, done=False, tail=""):
    return {"content": json.dumps({"analysis": "a", "plan": "p", "commands": commands, "task_complete": done}) + tail}
# The tools that are components (src/tool*.almd), written as orders beside the terminal's:
# a file written from a text after the object and read back by the host's path, then each
# tool asked for what it was not given.
note = "\n<<<BODY note\nline one\n\"quoted\" {braces}\n>>>BODY note\n"
tools = [
    {"tool": "write", "args": {"path": "tooled/note.txt", "content": "@body:note"}},
    {"tool": "read", "args": {"path": f"{P}/root/tooled/note.txt"}},
    {"tool": "write", "args": {"path": "/work/../escaped-by-tool.txt", "content": "x"}},
    {"tool": "read", "args": {"path": "/etc/hosts"}},
    {"tool": "read", "args": {"path": f"{P}/keys/.env"}},
    {"tool": "reference", "args": {"language": "almide"}},
    {"tool": "no_such_tool", "args": {}},
    # hew's tools, there when hew is here as a component (nautra/run.sh): what they answer
    # is looked for below only then.
    {"tool": "outline", "args": {"path": "hewn.py"}},
    {"tool": "search", "args": {"pattern": "def unusual_name"}},
    {"tool": "read", "args": {"path": "hewn.py", "symbol": "unusual_name"}},
    # golemide's edit, there when it is here as a component: a passage quoted with the
    # wrong indentation still lands.
    {"tool": "edit", "args": {"path": "hewn.py", "old": "def unusual_name():\n  return 41 + 1", "new": "def unusual_name():\n    return 40 + 2"}},
    # and a file that does not parse is refused by the grammars linked into the component.
    {"tool": "write", "args": {"path": "broken.py", "content": "def f(a, b:\n    return (a + b\n"}},
]
probe = tools + [
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
for i, r in enumerate([say(probe, tail=note), say([], done=True), say([], done=True)], 1):
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
import json, os, re, sys
P = sys.argv[1]
sent = json.load(open(P + "/fake/request-2.json"))
said = sent["messages"][-1]["content"]
for line in said.split("\n"):
    if re.fullmatch(r"[a-z]+=\d+", line) or line.startswith("held="):
        print(line)
print("waited=" + str("(job 14)\nslept\n[exit code 0]" in said))
system = json.load(open(P + "/fake/request-1.json"))["messages"][0]["content"]
print("tools-told=" + str("- read: " in system and "- write: " in system and "- reference: " in system and "- shell: " not in system))
print("tool-wrote=" + str("wrote tooled/note.txt: 2 lines" in said or '"ok":true,"path":"tooled/note.txt"' in said))
if "- edit: " in system:
    print("golemide-gate=" + str("refused by the syntax gate" in said and not os.path.exists(P + "/root/broken.py") and "gramide (linked)" in said))
    print("golemide-edit=" + str("return 40 + 2" in open(P + "/root/hewn.py").read() and "matched ignoring" in said))
first_read = said.split("(tool read")[1].split("(tool ")[0]
print("tool-read=" + str("line one" in first_read and '"quoted" {braces}' in first_read))
print("tool-hosts=" + str("/etc/hosts could not be read" in said or "no such file: /etc/hosts" in said))
print("tool-reference=" + str("import fs " in said and "effect fn main() -> Unit" in said))
if "- outline: " in system:
    print("hew-outline=" + str("unusual_name" in said.split("(tool outline")[1].split("(tool search")[0]))
    print("hew-search=" + str("hewn.py" in said.split("(tool search")[1].split("(tool read")[0] and "1 matches" in said))
    print("hew-read=" + str("return 41 + 1" in said.split('(tool read {"path":"hewn.py"')[1][:400]))
print("tool-unknown=" + str("no_such_tool" in said and ("refused" in said or "could not" in said)))
print("authorization=" + str(sent["authorization"]))
import subprocess
print("left-running=" + str(subprocess.run(["pgrep", "-f", "sleep 321"], capture_output=True).returncode == 0))
print("file-key-seen=" + str("file-key-999" in said))
import os, glob
everything = "".join(open(f, errors="replace").read() for f in glob.glob(P + "/runs/*/**", recursive=True) if os.path.isfile(f))
print("real-key-on-disk=" + str("the-real-key-777" in everything))
print("outside-written=" + str(os.path.exists(P + "/outside.txt")))
print("tool-file=" + str(open(P + "/root/tooled/note.txt").read() == 'line one\n"quoted" {braces}\n' if os.path.exists(P + "/root/tooled/note.txt") else "missing"))
print("tool-escaped=" + str(os.path.exists(P + "/escaped-by-tool.txt")))
print("home-written=" + str(os.path.exists(os.path.expanduser("~/comide-probe-escape.txt"))))
EOF
