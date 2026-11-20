#!/bin/sh
# comide's errand (`comide run`) checked end to end. No model is called: the model is stood
# in for by replies written by hand (talk.almd, COMIDE_FAKE), and under nautra by
# ci/fake-model.py. The part under nautra is skipped where there is no nautra.
#
#   ci/check.sh
set -u

here=$(cd "$(dirname "$0")/.." && pwd)
cd "$here" || exit 1
fails=0
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
# The person's own settings and keys are not part of what is checked.
export XDG_CONFIG_HOME="$tmp/config"

say()  { printf '%s\n' "$*"; }
bad()  { say "FAIL: $*"; fails=$((fails + 1)); }
same() { # same WHAT EXPECTED ACTUAL
  if [ "$2" = "$3" ]; then say "ok: $1"; else bad "$1"; say "  expected: $2"; say "  actual:   $3"; fi
}
has()  { # has WHAT NEEDLE FILE
  if grep -q -- "$2" "$3" 2>/dev/null; then say "ok: $1"; else bad "$1"; say "  no '$2' in $3"; fi
}

almide=${ALMIDE:-almide}
say "== almide test"
"$almide" test > "$tmp/test.out" 2>&1 || { bad "almide test"; tail -20 "$tmp/test.out"; }
say "== almide build"
"$almide" build src/main.almd -o comide > "$tmp/build.out" 2>&1 || { bad "almide build"; tail -20 "$tmp/build.out"; say "$fails failed"; exit 1; }
[ -x ./comide ] || { bad "no ./comide after the build"; say "$fails failed"; exit 1; }

say "== a task worked end to end, against a stand-in for the model"
# Six replies written by hand (talk.almd, COMIDE_FAKE): a command that changes directory
# and exports a variable; one that reads both back; one that outlasts its wait; a wait for
# that job; then "done" twice, the second after comide has asked.
mkdir -p "$tmp/fake" "$tmp/root/sub" "$tmp/log"
python3 - "$tmp/fake" <<'EOF'
import json, sys
def call(**a):
    return {"calls": [{"id": "", "name": "shell", "arguments": json.dumps(dict(analysis="a", plan="p", **a))}], "reasoning": "thought"}
replies = [call(command="cd sub && export FOO=bar && echo one"),
           call(command="pwd; echo $FOO"),
           call(command="echo early; sleep 3; echo late", wait_s=1),
           call(job=3, wait_s=20),
           {"content": "All done."},
           {"content": "Yes, done."}]
for i, r in enumerate(replies, 1):
    json.dump(r, open(f"{sys.argv[1]}/reply-{i}.json", "w"))
EOF
COMIDE_FAKE="$tmp/fake" COMIDE_LOG_DIR="$tmp/log" ./comide run "do the thing" --ask tool --root "$tmp/root" > "$tmp/run.out" 2> "$tmp/run.err"
same "exit 0" "0" "$?"
same "the last answer is what it prints" "Yes, done." "$(cat "$tmp/run.out")"
python3 - "$tmp/fake" > "$tmp/sent.out" <<'EOF'
import json, sys
r = json.load(open(sys.argv[1] + "/request-6.json"))
tools = [m["content"] for m in r["messages"] if m["role"] == "tool"]
users = [m["content"] for m in r["messages"] if m["role"] == "user"]
acts = [m for m in r["messages"] if m["role"] == "assistant" and m.get("tool_calls")]
print("effort", repr(r["effort"]))
print("max_tokens", r["max_tokens"])
print("tools", [t["function"]["name"] for t in r["tools"]])
print("cwd kept", tools[1].splitlines()[0].endswith("/root/sub"))
print("variable kept", tools[1].splitlines()[1])
print("outlasted", tools[2].splitlines()[0], "|", "still running after 1 s, as job 3" in tools[2])
print("waited for", " ".join(tools[3].splitlines()))
print("reasoning back", all(m.get("reasoning_content") == "thought" for m in acts))
print("asked once", sum(1 for u in users if u.startswith("Are you sure")))
EOF
has "no reasoning effort is sent" "^effort ''$" "$tmp/sent.out"
has "the output limit is large" "^max_tokens 65536$" "$tmp/sent.out"
has "one tool" "^tools \['shell'\]$" "$tmp/sent.out"
has "the directory a command changed to is the next command's" "^cwd kept True$" "$tmp/sent.out"
has "and so is the variable it exported" "^variable kept bar$" "$tmp/sent.out"
has "a command that outlasts its wait gives what it has printed and keeps running" "^outlasted early | True$" "$tmp/sent.out"
has "and can be waited for, to the end" "^waited for early late \[exit code 0\]$" "$tmp/sent.out"
has "what the model reasoned goes back with each reply" "^reasoning back True$" "$tmp/sent.out"
has "it is asked once whether the task is complete" "^asked once 1$" "$tmp/sent.out"
same "the cost is written as the run goes" "\$0.060000" "$(cat "$tmp/log/cost.txt")"

say "== a reply cut off is not an answer, and a command left running is ended"
rm -rf "$tmp/fake" "$tmp/log"; mkdir -p "$tmp/fake" "$tmp/log"
python3 - "$tmp/fake" "$tmp/alive" <<'EOF'
import json, sys
d, alive = sys.argv[1], sys.argv[2]
replies = [{"content": "I was thinking and", "finish": "length"},
           {"calls": [{"id": "c1", "name": "shell", "arguments": json.dumps({"analysis": "a", "plan": "p", "command": f"while :; do date > {alive}; sleep 1; done", "wait_s": 1})}]},
           {"content": "Done."}, {"content": "Done."}]
for i, r in enumerate(replies, 1):
    json.dump(r, open(f"{d}/reply-{i}.json", "w"))
EOF
COMIDE_FAKE="$tmp/fake" ./comide run "loop" --ask tool --root "$tmp/root" > "$tmp/run2.out" 2> "$tmp/run2.err"
same "exit 0" "0" "$?"
has "the model is told its reply was cut off, and goes on" "reached the output limit" "$tmp/run2.err"
before=$(cat "$tmp/alive" 2>/dev/null); sleep 3; after=$(cat "$tmp/alive" 2>/dev/null)
same "nothing it started is still running after the run" "$before" "$after"

say "== the same, with the model asked in writing (the default)"
# Seven replies: two commands in one reply, the second reading back what the first left;
# one that outlasts its wait, and a wait for it; a reply that is not JSON; "complete",
# which is asked about; and "complete" again.
rm -rf "$tmp/fake" "$tmp/log"; mkdir -p "$tmp/fake" "$tmp/log"
python3 - "$tmp/fake" <<'EOF'
import json, sys
def say(commands, done=False, **more):
    return {"content": json.dumps({"analysis": "what I see", "plan": "what I will do", "commands": commands, "task_complete": done}), "reasoning": "thought", **more}
replies = [say([{"command": "cd sub && export FOO=bar && echo one", "wait_s": 5}, {"command": "pwd; echo $FOO"}]),
           say([{"command": "echo early; sleep 3; echo late", "wait_s": 1}]),
           say([{"job": 3, "wait_s": 20}]),
           {"content": "I think the next step is to look around."},
           say([], done=True),
           say([{"command": "echo last look"}], done=True)]
for i, r in enumerate(replies, 1):
    json.dump(r, open(f"{sys.argv[1]}/reply-{i}.json", "w"))
EOF
COMIDE_FAKE="$tmp/fake" COMIDE_LOG_DIR="$tmp/log" ./comide run "do the thing" --root "$tmp/root" > "$tmp/run3.out" 2> "$tmp/run3.err"
same "exit 0" "0" "$?"
python3 - "$tmp/fake" "$tmp/log" > "$tmp/sent3.out" <<'EOF'
import json, sys
r = json.load(open(sys.argv[1] + "/request-6.json"))
users = [m["content"] for m in r["messages"] if m["role"] == "user"]
print("tools", len(r["tools"]))
print("effort", repr(r["effort"]))
print("task first", users[0].startswith("Task Description:"))
print("both ran", "$ cd sub && export FOO=bar && echo one" in users[1] and "$ pwd; echo $FOO" in users[1])
print("state kept", "/root/sub\nbar\n[exit code 0]" in users[1])
print("outlasted", "still running after 1 s, as job 3" in users[2])
print("waited for", users[3].replace("\n", " "))
print("unread said back", users[4].startswith("Previous response had parsing errors") and "None of its commands were run" in users[4])
print("asked once", sum(1 for u in users if "Are you sure you want to mark the task as complete" in u))
print("reasoning back", all(m.get("reasoning_content") == "thought" for m in r["messages"] if m["role"] == "assistant" and m["content"].startswith("{")))
t = json.load(open(sys.argv[2] + "/trajectory.json"))
print("record", len(t["steps"]), t["steps"][0]["reasoning_chars"], t["steps"][0]["content_chars"] > 50)
print("transcript", len(json.load(open(sys.argv[2] + "/transcript.json"))) >= 12)
EOF
has "no tool is sent" "^tools 0$" "$tmp/sent3.out"
has "no reasoning effort is sent" "^effort ''$" "$tmp/sent3.out"
has "the task is the first thing said" "^task first True$" "$tmp/sent3.out"
has "the commands of one reply run in order and are shown with their output" "^both ran True$" "$tmp/sent3.out"
has "the terminal's state carries from one command to the next" "^state kept True$" "$tmp/sent3.out"
has "a command that outlasts its wait keeps running" "^outlasted True$" "$tmp/sent3.out"
has "and can be waited for" "^waited for (job 3) early late \[exit code 0\]$" "$tmp/sent3.out"
has "a reply that is not JSON runs nothing and is said back" "^unread said back True$" "$tmp/sent3.out"
has "complete is asked about once, and complete again ends it" "^asked once 1$" "$tmp/sent3.out"
has "what the model reasoned goes back with each reply" "^reasoning back True$" "$tmp/sent3.out"
has "every step records how much was reasoned and written" "^record 6 7 True$" "$tmp/sent3.out"
has "the conversation is on disk after every step" "^transcript True$" "$tmp/sent3.out"
has "the commands of the last reply are run before it ends" "last look" "$tmp/run3.err"

say "== the survey and the task shown again, when asked for"
rm -rf "$tmp/fake" "$tmp/log"; mkdir -p "$tmp/fake" "$tmp/log"
python3 - "$tmp/fake" <<'EOF'
import json, sys
def say(commands, done=False):
    return {"content": json.dumps({"analysis": "a", "plan": "p", "commands": commands, "task_complete": done})}
for i, r in enumerate([say([{"command": "echo hi"}]), say([], done=True), say([], done=True)], 1):
    json.dump(r, open(f"{sys.argv[1]}/reply-{i}.json", "w"))
EOF
COMIDE_SURVEY=1 COMIDE_RECALL=1 COMIDE_FAKE="$tmp/fake" ./comide run "write the unusual thing to /app/out.txt" --root "$tmp/root" > "$tmp/run4.out" 2> "$tmp/run4.err"
same "exit 0" "0" "$?"
python3 - "$tmp/fake" "$tmp/root" > "$tmp/sent4.out" <<'EOF'
import json, sys
first = json.load(open(sys.argv[1] + "/request-1.json"))["messages"][1]["content"]
last = [m["content"] for m in json.load(open(sys.argv[1] + "/request-3.json"))["messages"] if m["role"] == "user"][-1]
print("survey", "[Environment Snapshot" in first and ("working directory: " + sys.argv[2]) in first and "sub" in first)
print("no trailer", "[exit code" not in first)
print("task first", first.startswith("Task Description:\nwrite the unusual thing"))
print("recall", "original task again:\n\nwrite the unusual thing to /app/out.txt" in last and "task_complete" in last)
EOF
has "what the terminal is like is shown with the task, before the first reply" "^survey True$" "$tmp/sent4.out"
has "without the terminal's own last line" "^no trailer True$" "$tmp/sent4.out"
has "the task still comes first" "^task first True$" "$tmp/sent4.out"
has "asked whether it is done, the model is shown the task again" "^recall True$" "$tmp/sent4.out"
rm -rf "$tmp/fake"; mkdir -p "$tmp/fake"
python3 -c "
import json
json.dump({'content': json.dumps({'analysis':'a','plan':'p','commands':[],'task_complete':True})}, open('$tmp/fake/reply-1.json','w'))"
COMIDE_FAKE="$tmp/fake" ./comide run "plain" --root "$tmp/root" > /dev/null 2>&1
if grep -q "Environment Snapshot" "$tmp/fake/request-1.json"; then bad "neither is on unless asked for"; else say "ok: neither is on unless asked for"; fi

say "== what the model reasoned is not sent back, when asked not to"
rm -rf "$tmp/fake"; mkdir -p "$tmp/fake"
python3 - "$tmp/fake" <<'EOF'
import json, sys
def say(commands, done=False):
    return {"content": json.dumps({"analysis": "a", "plan": "p", "commands": commands, "task_complete": done}), "reasoning": "a long thought"}
for i, r in enumerate([say([{"command": "echo hi"}]), say([], done=True), say([], done=True)], 1):
    json.dump(r, open(f"{sys.argv[1]}/reply-{i}.json", "w"))
EOF
COMIDE_REASONING_BACK=0 COMIDE_FAKE="$tmp/fake" COMIDE_LOG_DIR="$tmp/log" ./comide run "plain" --root "$tmp/root" > /dev/null 2>&1
if grep -q "a long thought" "$tmp/fake/request-3.json"; then bad "the reasoning went back"; else say "ok: no earlier reasoning is in what is sent"; fi
same "how much it reasoned is still recorded" "14" "$(python3 -c "import json; print(json.load(open('$tmp/log/trajectory.json'))['steps'][0]['reasoning_chars'])")"

say "== said complete, the work is checked in a new conversation, when asked for"
rm -rf "$tmp/fake" "$tmp/log"; mkdir -p "$tmp/fake" "$tmp/log"
python3 - "$tmp/fake" <<'EOF'
import json, sys
def say(commands, done=False):
    return {"content": json.dumps({"analysis": "a", "plan": "p", "commands": commands, "task_complete": done})}
replies = [say([{"command": "echo first work"}]), say([], done=True), say([], done=True),
           say([{"command": "echo looked again"}]), say([], done=True), say([], done=True)]
for i, r in enumerate(replies, 1):
    json.dump(r, open(f"{sys.argv[1]}/reply-{i}.json", "w"))
EOF
COMIDE_CHECK=1 COMIDE_FAKE="$tmp/fake" COMIDE_LOG_DIR="$tmp/log" ./comide run "write the unusual thing to /app/out.txt" --root "$tmp/root" > /dev/null 2> "$tmp/run5.err"
same "exit 0" "0" "$?"
python3 - "$tmp/fake" "$tmp/log" > "$tmp/sent5.out" <<'EOF'
import json, sys
m = json.load(open(sys.argv[1] + "/request-4.json"))["messages"]
print("fresh", len(m) == 2 and "first work" not in json.dumps(m))
print("task", m[1]["content"].startswith("Task Description:\nwrite the unusual thing to /app/out.txt\n\n[Review]"))
last = json.load(open(sys.argv[1] + "/request-6.json"))["messages"]
print("asked again", "Are you sure" in last[-1]["content"])
print("steps", len(json.load(open(sys.argv[2] + "/trajectory.json"))["steps"]))
print("kept", "first work" in open(sys.argv[2] + "/transcript-work.json").read())
print("mark", open(sys.argv[2] + "/check.txt").read().strip())
EOF
has "the one who checks starts with the task alone" "^fresh True$" "$tmp/sent5.out"
has "and the note that the report is not evidence" "^task True$" "$tmp/sent5.out"
has "its complete is asked about once, as the first one's was" "^asked again True$" "$tmp/sent5.out"
has "every step of both is in the record" "^steps 6$" "$tmp/sent5.out"
has "the first conversation is kept" "^kept True$" "$tmp/sent5.out"
has "where the check began is written down" "^mark the check began after step 3$" "$tmp/sent5.out"
has "its commands are run" "looked again" "$tmp/run5.err"
[ ! -f "$tmp/fake/request-7.json" ] && say "ok: it is checked once, not again and again" || bad "a seventh call was made"

say "== the settings are heard before and after every command of an errand"
# A deny rule, an ask rule, a hook that stops one command and a hook that objects to what
# another printed. Three replies: the five commands, then "complete" twice.
rm -rf "$tmp/fake" "$tmp/gate"; mkdir -p "$tmp/fake" "$tmp/gate"
cat > "$tmp/settings.json" <<EOF
{ "permissions": { "deny": ["shell(rm -rf*)"], "ask": ["shell(git push*)"], "allow": ["shell(echo*)"] },
  "hooks": {
    "PreToolUse":  [ { "matcher": "shell", "hooks": [ { "type": "command", "command": "grep -q forbidden-word && { echo 'that word is not used here' >&2; exit 2; }; exit 0" } ] } ],
    "PostToolUse": [ { "matcher": "shell", "hooks": [ { "type": "command", "command": "grep -q leaked-thing && { echo 'that should not have been printed' >&2; exit 2; }; exit 0" } ] } ] } }
EOF
python3 - "$tmp/fake" <<'EOF'
import json, sys
def say(commands, done=False):
    return {"content": json.dumps({"analysis": "a", "plan": "p", "commands": commands, "task_complete": done})}
replies = [say([{"command": "echo plain > kept.txt; cat kept.txt"},
                {"command": "touch doomed.txt; cd . && rm -rf doomed.txt"},
                {"command": "git push origin main"},
                {"command": "echo forbidden-word > hooked.txt"},
                {"command": "echo leaked-th''ing"}]),
           say([], done=True), say([], done=True)]
for i, r in enumerate(replies, 1):
    json.dump(r, open(f"{sys.argv[1]}/reply-{i}.json", "w"))
EOF
COMIDE_SETTINGS="$tmp/settings.json" COMIDE_FAKE="$tmp/fake" ./comide run "gate" --root "$tmp/gate" > /dev/null 2> "$tmp/gate.err"
same "exit 0" "0" "$?"
python3 - "$tmp/fake" "$tmp/gate" > "$tmp/gate.out" <<'EOF'
import json, os, sys
said = [m["content"] for m in json.load(open(sys.argv[1] + "/request-2.json"))["messages"] if m["role"] == "user"][-1]
print("plain ran", "plain\n[exit code 0]" in said)
print("denied", "the settings deny this command (shell(rm -rf*))" in said, os.path.exists(sys.argv[2] + "/doomed.txt"))
print("asked", "nobody is here to ask" in said)
print("pre hook", "that word is not used here" in said, os.path.exists(sys.argv[2] + "/hooked.txt"))
print("post hook", "leaked-thing\n" in said and "that should not have been printed" in said)
EOF
has "a command no rule stops runs" "^plain ran True$" "$tmp/gate.out"
has "a denied command is not run, though it is the second half of a chain, and the model is told" "^denied True False$" "$tmp/gate.out"
has "a command the settings would ask about is not run: nobody is there" "^asked True$" "$tmp/gate.out"
has "a hook stops a command before it runs" "^pre hook True False$" "$tmp/gate.out"
has "a hook's objection goes under what the command printed" "^post hook True$" "$tmp/gate.out"
printf '{ not json' > "$tmp/broken.json"
COMIDE_SETTINGS="$tmp/broken.json" COMIDE_FAKE="$tmp/fake" ./comide run "gate" --root "$tmp/gate" > /dev/null 2> "$tmp/gate2.err"
same "settings that cannot be read stop the errand before it starts" "1" "$?"

say "== without a task, nothing is started"
./comide run > /dev/null 2>&1
same "exit 2" "2" "$?"


say "== under nautra: the same work with no key in reach, and a terminal that cannot leave"
NAUTRA=${NAUTRA:-$(command -v nautra || true)}
if [ -z "$NAUTRA" ] || [ ! -x "$NAUTRA" ]; then
  say "skipped: no nautra on PATH or in NAUTRA"
else
  export NAUTRA
  sh nautra/build.sh > "$tmp/nbuild.out" 2>&1 || { bad "nautra/build.sh"; tail -20 "$tmp/nbuild.out"; }
  # Not under /tmp: every sandboxed command may write there, so a workspace there cannot
  # show that its parent is closed.
  mkdir -p "$HOME/.cache/comide"
  probe=$(mktemp -d "$HOME/.cache/comide/ci-XXXXXX")
  sh ci/nautra-probe.sh "$probe" "${PROBE_PORT:-18790}" closed > "$tmp/probe.out" 2>&1
  has "the run ends well" "^run=0$" "$tmp/probe.out"
  has "the model was called with the real key, put there by nautra" "^authorization=Bearer the-real-key-777$" "$tmp/probe.out"
  has "comide holds no key: not in the terminal's variables" "^held=\[\]$" "$tmp/probe.out"
  has "nor anywhere in them" "^envkey=1$" "$tmp/probe.out"
  has "nor in the composition file, the record or the state" "^real-key-on-disk=False$" "$tmp/probe.out"
  has "the directory the keys are kept in cannot be read" "^keyfile=1$" "$tmp/probe.out"
  has "and nothing of it came back to the model" "^file-key-seen=False$" "$tmp/probe.out"
  has "the workspace's parent cannot be written" "^outside-written=False$" "$tmp/probe.out"
  has "nor the home directory" "^home-written=False$" "$tmp/probe.out"
  has "nor ~/.ssh read" "^ssh=1$" "$tmp/probe.out"
  has "a host not named cannot be reached" "^net=6$" "$tmp/probe.out"
  has "the model's own address cannot be reached from the terminal" "^model=7$" "$tmp/probe.out"
  has "the workspace can be written and read" "^inside=0$" "$tmp/probe.out"
  has "the directory and the variables last from call to call" "^kept=0$" "$tmp/probe.out"
  has "a command that outlasts its wait is waited for again" "^waited=True$" "$tmp/probe.out"
  has "nothing is left running when the run ends" "^left-running=False$" "$tmp/probe.out"
  rm -rf "$probe"
fi

say ""
if [ "$fails" -eq 0 ]; then say "all checks passed"; else say "$fails failed"; exit 1; fi
