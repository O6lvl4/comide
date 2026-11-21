#!/bin/sh
# comide's errand (`comide errand`) checked end to end. No model is called: the model is stood
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
good() { say "ok: $*"; }
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
COMIDE_FAKE="$tmp/fake" COMIDE_LOG_DIR="$tmp/log" ./comide errand "do the thing" --ask tool --root "$tmp/root" > "$tmp/run.out" 2> "$tmp/run.err"
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
COMIDE_FAKE="$tmp/fake" ./comide errand "loop" --ask tool --root "$tmp/root" > "$tmp/run2.out" 2> "$tmp/run2.err"
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
COMIDE_FAKE="$tmp/fake" COMIDE_LOG_DIR="$tmp/log" ./comide errand "do the thing" --root "$tmp/root" > "$tmp/run3.out" 2> "$tmp/run3.err"
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
COMIDE_SURVEY=1 COMIDE_RECALL=1 COMIDE_FAKE="$tmp/fake" ./comide errand "write the unusual thing to /app/out.txt" --root "$tmp/root" > "$tmp/run4.out" 2> "$tmp/run4.err"
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
COMIDE_FAKE="$tmp/fake" ./comide errand "plain" --root "$tmp/root" > /dev/null 2>&1
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
COMIDE_REASONING_BACK=0 COMIDE_FAKE="$tmp/fake" COMIDE_LOG_DIR="$tmp/log" ./comide errand "plain" --root "$tmp/root" > /dev/null 2>&1
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
COMIDE_CHECK=1 COMIDE_FAKE="$tmp/fake" COMIDE_LOG_DIR="$tmp/log" ./comide errand "write the unusual thing to /app/out.txt" --root "$tmp/root" > /dev/null 2> "$tmp/run5.err"
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
COMIDE_SETTINGS="$tmp/settings.json" COMIDE_FAKE="$tmp/fake" ./comide errand "gate" --root "$tmp/gate" > /dev/null 2> "$tmp/gate.err"
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
COMIDE_SETTINGS="$tmp/broken.json" COMIDE_FAKE="$tmp/fake" ./comide errand "gate" --root "$tmp/gate" > /dev/null 2> "$tmp/gate2.err"
same "settings that cannot be read stop the errand before it starts" "1" "$?"

say "== the conversation, with the model asked in writing (--loop written)"
# One request with --yes, then the session taken up again by a person who is asked about
# a command and says yes, and about another and says what to do instead.
rm -rf "$tmp/fake" "$tmp/conv"; mkdir -p "$tmp/fake" "$tmp/conv" "$tmp/home"
python3 - "$tmp/fake" <<'EOF'
import json, sys
def say(commands, done=False, analysis="a"):
    return {"content": json.dumps({"analysis": analysis, "plan": "p", "commands": commands, "task_complete": done}), "reasoning": "thought"}
replies = [say([{"command": "echo hi > made.txt && cat made.txt"}]),
           say([], done=True, analysis="Wrote made.txt; it says hi."), say([], done=True, analysis="Yes."),
           say([{"command": "echo more >> made.txt"}, {"command": "echo never > never.txt"}, {"command": "echo after > after.txt"}]),
           say([], done=True, analysis="Added a line."), say([], done=True, analysis="Yes.")]
for i, r in enumerate(replies, 1):
    json.dump(r, open(f"{sys.argv[1]}/reply-{i}.json", "w"))
EOF
conv() { HOME="$tmp/home" LOCAL_BASE_URL=http://127.0.0.1:9/v1 LOCAL_API_KEY=none COMIDE_FAKE="$tmp/fake" ./comide "$@" --loop written --model local:stand-in --root "$tmp/conv"; }
conv -p "make the file" --yes > "$tmp/conv1.out" 2> "$tmp/conv1.err"
same "exit 0" "0" "$?"
has "what the model said when it finished is the answer" "Wrote made.txt; it says hi." "$tmp/conv1.out"
same "the command ran" "hi" "$(cat "$tmp/conv/made.txt")"
printf 'add a line\n1\nuse printf instead\n' | conv --continue > "$tmp/conv2.out" 2> "$tmp/conv2.err"
same "exit 0" "0" "$?"
same "a command the person said yes to ran" "hi more" "$(tr '\n' ' ' < "$tmp/conv/made.txt" | sed 's/ $//')"
if [ -e "$tmp/conv/never.txt" ] || [ -e "$tmp/conv/after.txt" ]; then bad "a declined command, and the one after it, are not run"; else say "ok: a declined command, and the one after it, are not run"; fi
python3 - "$tmp/fake" > "$tmp/conv.out" <<'EOF'
import json, sys
r4 = json.load(open(sys.argv[1] + "/request-4.json"))["messages"]
r5 = json.load(open(sys.argv[1] + "/request-5.json"))["messages"]
print("system", "Format your response as JSON" in r4[0]["content"], len(json.load(open(sys.argv[1] + "/request-4.json"))["tools"]))
print("kept", [m["role"] for m in r4[1:3]] == ["user", "assistant"] and r4[1]["content"].startswith("Task Description:\nmake the file"))
print("said plainly", r4[-1]["content"] == "add a line")
print("declined", "the user declined this command and said: use printf instead" in r5[-1]["content"])
print("the rest", "an earlier command of this reply was not run" in r5[-1]["content"])
EOF
has "the model is told the shape of its reply, and is sent no tool" "^system True 0$" "$tmp/conv.out"
has "the session taken up again has what was said before" "^kept True$" "$tmp/conv.out"
has "what the person says next is said as they said it" "^said plainly True$" "$tmp/conv.out"
has "the model reads what the person said in place of the command" "^declined True$" "$tmp/conv.out"
has "and that the commands after it were not run" "^the rest True$" "$tmp/conv.out"
printf 'again\n' | conv -p "no one here" > /dev/null 2>&1
if [ -e "$tmp/conv/never.txt" ]; then bad "with nobody to ask and no --yes, no command runs"; else say "ok: with nobody to ask and no --yes, no command runs"; fi

say "== the conversation's tools, written as commands"
# A tool beside a terminal command in one reply; a tool that is not one; then, in plan
# mode, a terminal command and a tool that changes things, both held. A question is
# answered at once, without being asked whether it is done.
rm -rf "$tmp/fake" "$tmp/tl" "$tmp/home"; mkdir -p "$tmp/fake" "$tmp/tl" "$tmp/home"
python3 - "$tmp/fake" <<'EOF'
import json, sys
def say(commands, done=False, analysis="a"):
    return {"content": json.dumps({"analysis": analysis, "plan": "p", "commands": commands, "task_complete": done})}
replies = [say([{"tool": "remember", "args": {"note": "the staging db is read-only"}},
                {"command": "echo ran > ran.txt"},
                {"tool": "no_such_tool", "args": {}}]),
           say([], done=True), say([], done=True, analysis="Kept the note."),
           say([{"command": "echo plan > planned.txt"}, {"tool": "remember", "args": {"note": "not in plan mode"}}]),
           say([], done=True, analysis="Here is the plan."), say([], done=True, analysis="Here is the plan."),
           say([], done=True, analysis="It is 42.")]
for i, r in enumerate(replies, 1):
    json.dump(r, open(f"{sys.argv[1]}/reply-{i}.json", "w"))
EOF
tl() { HOME="$tmp/home" LOCAL_BASE_URL=http://127.0.0.1:9/v1 LOCAL_API_KEY=none COMIDE_FAKE="$tmp/fake" ./comide "$@" --model local:stand-in --root "$tmp/tl"; }
tl -p "keep a note" --yes > "$tmp/tl1.out" 2> "$tmp/tl1.err"
same "exit 0, with the written loop as the default" "0" "$?"
same "the terminal command beside the tool ran" "ran" "$(cat "$tmp/tl/ran.txt" 2>/dev/null)"
if grep -rq "the staging db is read-only" "$tmp/home/.comide/memory" 2>/dev/null; then say "ok: the tool ran: the note is kept"; else bad "the tool ran: the note is kept"; fi
tl -p "plan it" --yes --plan --continue > "$tmp/tl2.out" 2> "$tmp/tl2.err"
if [ -e "$tmp/tl/planned.txt" ]; then bad "in plan mode the terminal is held"; else say "ok: in plan mode the terminal is held"; fi
if grep -rq "not in plan mode" "$tmp/home/.comide/memory" 2>/dev/null; then bad "and so is a tool that changes things"; else say "ok: and so is a tool that changes things"; fi
tl -p "what is six times seven?" --continue > "$tmp/tl3.out" 2> "$tmp/tl3.err"
same "a question is answered at once" "It is 42." "$(cat "$tmp/tl3.out")"
python3 - "$tmp/fake" > "$tmp/tl.out" <<'EOF'
import json, os, sys
f = sys.argv[1]
r1 = json.load(open(f + "/request-1.json")); r2 = json.load(open(f + "/request-2.json"))["messages"]; r5 = json.load(open(f + "/request-5.json"))["messages"]
system = r1["messages"][0]["content"]
print("told", "- edit: " in system and "- solve: " in system and '{"tool": "NAME", "args": {...}}' in system and len(r1["tools"]) == 0)
print("results", "Kept in " in r2[-1]["content"] and "$ echo ran > ran.txt" in r2[-1]["content"])
print("unknown", "no_such_tool" in r2[-1]["content"])
print("held", r5[-1]["content"].count("plan mode") >= 2)
print("plan note", "Plan mode" in r5[-2 - 1]["content"] or any("[Plan mode" in m["content"] for m in r5 if m["role"] == "user"))
print("no eighth call", not os.path.exists(f + "/request-8.json"))
EOF
has "the model is told of the tools in writing, and is sent none" "^told True$" "$tmp/tl.out"
has "a tool's result and a command's are shown together, in order" "^results True$" "$tmp/tl.out"
has "a tool that does not exist is said back" "^unknown True$" "$tmp/tl.out"
has "what was held in plan mode is said to the model" "^held True$" "$tmp/tl.out"
has "a request in plan mode says so" "^plan note True$" "$tmp/tl.out"
has "an answer with no work behind it is not asked about" "^no eighth call True$" "$tmp/tl.out"

say "== a long text, written after the object"
# A script with quotes, braces and newlines in it, written as it is after the JSON and
# named in a command; and no search engine answering, so the search is not offered.
rm -rf "$tmp/fake" "$tmp/bd"; mkdir -p "$tmp/fake" "$tmp/bd"
python3 - "$tmp/fake" <<'EOF'
import json, sys
def say(commands, done=False, tail="", analysis="a"):
    return {"content": json.dumps({"analysis": analysis, "plan": "p", "commands": commands, "task_complete": done}) + tail}
body = "\n<<<BODY make\ncat > made.py <<'PY'\nd = {\"k\": [1, 2]}\nprint(\"}\" + str(d[\"k\"][1]))\nPY\npython3 made.py > made.out\n>>>BODY make\n"
replies = [say([{"command": "@body:make", "wait_s": 10}], tail=body),
           say([{"command": "@body:missing"}]),
           say([], done=True, analysis="@body:answer", tail="\n<<<BODY answer\nMade it. It prints:\n\n    }2\n>>>BODY answer\n"),
           say([], done=True, analysis="Yes, the task is complete.")]
for i, r in enumerate(replies, 1):
    json.dump(r, open(f"{sys.argv[1]}/reply-{i}.json", "w"))
EOF
HOME="$tmp/home" LOCAL_BASE_URL=http://127.0.0.1:9/v1 LOCAL_API_KEY=none COMIDE_SEARXNG_URL=http://127.0.0.1:9 COMIDE_FAKE="$tmp/fake" \
  ./comide -p "make it" --yes --model local:stand-in --root "$tmp/bd" > "$tmp/bd.out" 2> "$tmp/bd.err"
same "exit 0" "0" "$?"
same "the text ran as it was written" "}2" "$(cat "$tmp/bd/made.out" 2>/dev/null)"
# Asked whether it is sure, the model answers that question; what it said first, with its
# line breaks, is the answer the person gets.
same "the answer is what the model said when it finished, not its yes to being asked" "Made it. It prints:

    }2" "$(cat "$tmp/bd.out")"
python3 - "$tmp/fake" > "$tmp/bd.sent" <<'EOF'
import json, sys
f = sys.argv[1]
system = json.load(open(f + "/request-1.json"))["messages"][0]["content"]
r3 = json.load(open(f + "/request-3.json"))["messages"]
print("told", "<<<BODY NAME" in system)
print("no search", "- web_search: " not in system and "- web_fetch: " in system)
print("missing", "names a text" in r3[-1]["content"])
EOF
has "the model is told how to write a long text" "^told True$" "$tmp/bd.sent"
has "with no search engine answering, the search is not offered" "^no search True$" "$tmp/bd.sent"
has "a text named and not written is said back, and nothing runs" "^missing True$" "$tmp/bd.sent"

say "== on a terminal: the input box takes the keys, and what runs is shown running"
# In a pseudo-terminal (ci/pty-drive.py): two wide characters typed, one erased, sent;
# the model's reply runs a command that takes two seconds. From the epoch 15 stdlib to
# 0.7.1 the terminal was never taken over and none of this was checked: no box, and a
# line reader that could not erase a wide character.
rm -rf "$tmp/fake" "$tmp/pt"; mkdir -p "$tmp/fake" "$tmp/pt"
python3 - "$tmp/fake" <<'EOF'
import json, sys
def say(commands, done=False, analysis="a"):
    return {"content": json.dumps({"analysis": analysis, "plan": "p", "commands": commands, "task_complete": done})}
replies = [say([{"tool": "reference", "args": {"language": "almide"}},
                {"tool": "reference", "args": {"language": "almide", "module": "int"}},
                {"command": "echo one; sleep 2; echo two", "wait_s": 10}]),
           say([], done=True, analysis="All done."), say([], done=True, analysis="All done.")]
for i, r in enumerate(replies, 1):
    json.dump(r, open(f"{sys.argv[1]}/reply-{i}.json", "w"))
EOF
( cd "$tmp/pt" && HOME="$tmp/home" LOCAL_BASE_URL=http://127.0.0.1:9/v1 LOCAL_API_KEY=none COMIDE_SEARXNG_URL=http://127.0.0.1:9 COMIDE_FAKE="$tmp/fake" \
    python3 "$here/ci/pty-drive.py" 12 'あい@2,\x7f@3,\r@4,\x03@10,\x03@10.4' -- "$here/comide" --yes --model local:stand-in > "$tmp/pt.raw" 2>&1 )
sed 's/'"$(printf '\033')"'\[[0-9;?]*[A-Za-z]/ /g' "$tmp/pt.raw" | tr '\r' '\n' > "$tmp/pt.txt"
has "the input box is drawn" "│ *❯" "$tmp/pt.txt"
has "two wide characters typed are drawn" "❯ *あい" "$tmp/pt.txt"
python3 - "$tmp/fake" "$tmp/pt.txt" > "$tmp/pt.out" <<'EOF'
import json, re, sys
sent = [m["content"] for m in json.load(open(sys.argv[1] + "/request-1.json"))["messages"] if m["role"] == "user"]
print("sent", sent[-1] == "Task Description:\nあ")
screen = open(sys.argv[2], encoding="utf-8", errors="replace").read()
rows = [l for l in screen.split("\n") if "❯" in l and "│" in l]
after = [i for i, l in enumerate(rows) if re.search(r"❯ *あい", l)]
print("erased", bool(after) and any(re.search(r"❯ *あ {3,}", l) for l in rows[after[-1] + 1:]))
print("running", bool(re.search(r"Running… +\d+s", screen)))
print("printed", "one" in screen and "two" in screen and "All done." in screen)
EOF
has "one of them erased is gone from the screen" "^erased True$" "$tmp/pt.out"
has "and from what is sent" "^sent True$" "$tmp/pt.out"
has "a command that is running is shown running, with the seconds" "^running True$" "$tmp/pt.out"
has "what it printed and the answer are shown" "^printed True$" "$tmp/pt.out"

# Shift+Enter and Option+Enter. A terminal sends both as a plain Return unless it is asked
# to tell modified keys apart, so the box asks while it is read (and takes the asking back),
# and the keys arrive as `ESC [ 13 ; 2 u` and `ESC [ 13 ; 3 u`: each a new line in the text.
# Ctrl+C arrives in the same form then, and still leaves.
rm -rf "$tmp/fake2" "$tmp/pt2"; mkdir -p "$tmp/fake2" "$tmp/pt2"
python3 - "$tmp/fake2" <<'EOF'
import json, sys
for i in (1, 2):
    json.dump({"content": json.dumps({"analysis": "Read.", "plan": "p", "commands": [], "task_complete": True})}, open(f"{sys.argv[1]}/reply-{i}.json", "w"))
EOF
( cd "$tmp/pt2" && HOME="$tmp/home" LOCAL_BASE_URL=http://127.0.0.1:9/v1 LOCAL_API_KEY=none COMIDE_SEARXNG_URL=http://127.0.0.1:9 COMIDE_FAKE="$tmp/fake2" \
    python3 "$here/ci/pty-drive.py" 12 'a@2,\x1b[13;2u@2.5,b@3,\x1b[13;3u@3.5,c@4,\r@4.5,\x1b[99;5u@9,\x1b[99;5u@9.4' -- "$here/comide" --yes --model local:stand-in > "$tmp/pt2.raw" 2>&1 )
python3 - "$tmp/fake2" "$tmp/pt2.raw" > "$tmp/pt2.out" <<'EOF'
import json, sys
sent = [m["content"] for m in json.load(open(sys.argv[1] + "/request-1.json"))["messages"] if m["role"] == "user"]
raw = open(sys.argv[2], "rb").read()
print("lines", sent[-1] == "Task Description:\na\nb\nc")
print("asked", b"\x1b[>1u" in raw, "taken back", raw.count(b"\x1b[<u") >= raw.count(b"\x1b[>1u") > 0)
EOF
has "Shift+Enter and Option+Enter are new lines in what is sent" "^lines True$" "$tmp/pt2.out"
has "the terminal is asked to tell modified keys apart, and the asking is taken back" "^asked True taken back True$" "$tmp/pt2.out"

# Said while comide works. A command is running: a line is typed and Enter pressed, and
# the model reads it with that command's results, before its next reply. A second line is
# typed and not entered while the next command runs: when the request ends it is in the
# input box, not lost.
rm -rf "$tmp/fake3" "$tmp/pt3"; mkdir -p "$tmp/fake3" "$tmp/pt3"
python3 - "$tmp/fake3" <<'EOF'
import json, sys
def say(commands, done=False, analysis="a"):
    return {"content": json.dumps({"analysis": analysis, "plan": "p", "commands": commands, "task_complete": done})}
r = [say([{"command": "echo one; sleep 4; echo two", "wait_s": 10}]), say([{"command": "sleep 3; echo three", "wait_s": 10}]), say([], True, "All done."), say([], True, "All done.")]
for i, x in enumerate(r, 1):
    json.dump(x, open(f"{sys.argv[1]}/reply-{i}.json", "w"))
EOF
( cd "$tmp/pt3" && HOME="$tmp/home" LOCAL_BASE_URL=http://127.0.0.1:9/v1 LOCAL_API_KEY=none COMIDE_SEARXNG_URL=http://127.0.0.1:9 COMIDE_FAKE="$tmp/fake3" \
    python3 "$here/ci/pty-drive.py" 16 'go@2,\r@2.5,use tabs@4,\r@5,too late@9.5,\x03@14,\x03@14.4' -- "$here/comide" --yes --model local:stand-in > "$tmp/pt3.raw" 2>&1 )
python3 - "$tmp/fake3" "$tmp/pt3.raw" > "$tmp/pt3.out" <<'EOF'
import json, re, sys
last = lambda n: json.load(open(f"{sys.argv[1]}/request-{n}.json"))["messages"][-1]["content"]
screen = re.sub(r"\x1b\[[0-9;?<>]*[A-Za-z]", " ", open(sys.argv[2], errors="replace").read()).replace("\r", "\n")
print("told", "While you were working, the user said this" in last(2) and last(2).endswith("use tabs") and "[exit code 0]" in last(2))
print("once", "use tabs" not in last(3))
print("shown", "❯ use tabs" in screen and "told comide: use tabs" in screen)
print("kept", any("too late" in l and "│" in l for l in screen.split("\n")[-40:]))
EOF
has "what is typed and entered while a command runs is told to the model with its results" "^told True$" "$tmp/pt3.out"
has "and told once" "^once True$" "$tmp/pt3.out"
has "it is shown while it is typed, and said to have been told" "^shown True$" "$tmp/pt3.out"
has "what was typed and not entered is in the input box when the request ends" "^kept True$" "$tmp/pt3.out"

# Esc with something typed: the request stops there (the command, and what the reply had
# left to run), and what was typed is the next request at once. Esc with nothing typed
# stops the command only, as it always did, and sends nothing.
rm -rf "$tmp/fake4" "$tmp/pt4"; mkdir -p "$tmp/fake4" "$tmp/pt4"
python3 - "$tmp/fake4" <<'EOF'
import json, sys
def say(commands, done=False, analysis="a"):
    return {"content": json.dumps({"analysis": analysis, "plan": "p", "commands": commands, "task_complete": done})}
r = [say([{"command": "echo one; sleep 30; echo never", "wait_s": 40}, {"command": "echo second-order"}]),
     say([{"command": "sleep 20; echo again", "wait_s": 30}]), say([], True, "Done."), say([], True, "Done.")]
for i, x in enumerate(r, 1):
    json.dump(x, open(f"{sys.argv[1]}/reply-{i}.json", "w"))
EOF
( cd "$tmp/pt4" && HOME="$tmp/home" LOCAL_BASE_URL=http://127.0.0.1:9/v1 LOCAL_API_KEY=none COMIDE_SEARXNG_URL=http://127.0.0.1:9 COMIDE_FAKE="$tmp/fake4" \
    python3 "$here/ci/pty-drive.py" 16 'go@2,\r@2.5,other way@4,\x1b@5.5,\x1b@8.5,\x03@13,\x03@13.4' -- "$here/comide" --yes --model local:stand-in > "$tmp/pt4.raw" 2>&1 )
python3 - "$tmp/fake4" "$tmp/pt4.raw" > "$tmp/pt4.out" <<'EOF'
import json, re, sys
users = lambda n: [m["content"] for m in json.load(open(f"{sys.argv[1]}/request-{n}.json"))["messages"] if m["role"] == "user"]
screen = re.sub(r"\x1b\[[0-9;?<>]*[A-Za-z]", " ", open(sys.argv[2], errors="replace").read()).replace("\r", "\n")
print("sent", users(2)[-1] == "other way" and "stopped the request here" in users(2)[-2] and "second-order\n[not run" in users(2)[-2])
print("said", "stopped, and sent: other way" in screen and "never" not in screen)
print("plain", "[The user stopped this command.]" in users(3)[-1] and screen.count("stopped, and sent") == 1)
EOF
has "Esc with something typed stops the request and sends it as the next one at once" "^sent True$" "$tmp/pt4.out"
has "and says so; the command it stopped did not go on" "^said True$" "$tmp/pt4.out"
has "Esc with nothing typed stops the command only, and sends nothing" "^plain True$" "$tmp/pt4.out"

# A question put to the person is not answered by what they were typing. The request, and
# then "1" and Enter, arrive together, before the question "Run this command?" is up: on
# 0.9.3 the "1" answered it and the command ran unasked.
rm -rf "$tmp/fake5" "$tmp/pt5"; mkdir -p "$tmp/fake5" "$tmp/pt5"
python3 - "$tmp/fake5" <<'EOF'
import json, sys
def say(commands, done=False, analysis="a"):
    return {"content": json.dumps({"analysis": analysis, "plan": "p", "commands": commands, "task_complete": done})}
for i, x in enumerate([say([{"command": "touch ran.txt"}]), say([], True, "Done."), say([], True, "Done.")], 1):
    json.dump(x, open(f"{sys.argv[1]}/reply-{i}.json", "w"))
EOF
( cd "$tmp/pt5" && HOME="$tmp/home" LOCAL_BASE_URL=http://127.0.0.1:9/v1 LOCAL_API_KEY=none COMIDE_SEARXNG_URL=http://127.0.0.1:9 COMIDE_FAKE="$tmp/fake5" \
    python3 "$here/ci/pty-drive.py" 12 'go\r1\r@2,\x1b@6,\x03@10,\x03@10.4' -- "$here/comide" --model local:stand-in > "$tmp/pt5.raw" 2>&1 )
[ ! -e "$tmp/pt5/ran.txt" ] && grep -q "Run this command?" "$tmp/pt5.raw" && good "keys typed ahead of a question do not answer it: the command is not run" || bad "a command ran on keys typed before its question was up"

# ↑ takes back a line handed over while comide works, before it is told; and Esc twice on
# an empty input box is /rewind, with its menus, which puts the request in the box again.
rm -rf "$tmp/fake6" "$tmp/pt6"; mkdir -p "$tmp/fake6" "$tmp/pt6"
python3 - "$tmp/fake6" <<'EOF'
import json, sys
def say(commands, done=False, analysis="a"):
    return {"content": json.dumps({"analysis": analysis, "plan": "p", "commands": commands, "task_complete": done})}
for i, x in enumerate([say([{"command": "echo one; sleep 5; echo two", "wait_s": 10}]), say([], True, "Done."), say([], True, "Done.")], 1):
    json.dump(x, open(f"{sys.argv[1]}/reply-{i}.json", "w"))
EOF
( cd "$tmp/pt6" && HOME="$tmp/home" LOCAL_BASE_URL=http://127.0.0.1:9/v1 LOCAL_API_KEY=none COMIDE_SEARXNG_URL=http://127.0.0.1:9 COMIDE_FAKE="$tmp/fake6" \
    python3 "$here/ci/pty-drive.py" 20 'go@2,\r@2.5,wrong@3.5,\r@4,\x1b[A@4.8,\x15@5.4,right@5.8,\r@6.4,\x1b@11,\x1b@12,\r@13.5,\r@15,\x03@18,\x03@18.4' -- "$here/comide" --yes --model local:stand-in > "$tmp/pt6.raw" 2>&1 )
python3 - "$tmp/fake6" "$tmp/pt6.raw" > "$tmp/pt6.out" <<'EOF'
import json, re, sys
last = json.load(open(f"{sys.argv[1]}/request-2.json"))["messages"][-1]["content"]
screen = re.sub(r"\x1b\[[0-9;?<>]*[A-Za-z]", " ", open(sys.argv[2], errors="replace").read()).replace("\r", "\n")
print("taken", last.endswith("right") and "wrong" not in last)
print("rewound", "esc again to go back" in screen and "Go back to before which request?" in screen and "the conversation is back to before: go" in screen)
print("again", any(re.search(r"❯ *go", l) and "│" in l for l in screen.split("\n")[-30:]))
EOF
has "a line handed over is taken back with ↑ and another told in its place" "^taken True$" "$tmp/pt6.out"
has "Esc twice on an empty box is /rewind, chosen from its menus" "^rewound True$" "$tmp/pt6.out"
has "and the request gone back over is in the input box again" "^again True$" "$tmp/pt6.out"

# What the model was told in that conversation: the machine is the person's, and, where
# almide is installed, that the reference tool tells about the language. The tool's answer
# is the syntax as one program; the program is taken out of the answer and given to the
# compiler, so the text a model learns from cannot rot unseen.
python3 - "$tmp/fake" "$tmp/primer.almd" > "$tmp/told.out" <<'EOF'
import json, sys
system = json.load(open(sys.argv[1] + "/request-1.json"))["messages"][0]["content"]
seen = json.load(open(sys.argv[1] + "/request-2.json"))["messages"][-1]["content"]
print("own machine", "This is the user's own machine" in system)
print("one line", "call the reference tool" in system and "- reference: " in system and "import fs " not in system)
print("module", "fn int.to_string(x: Int) -> String" in seen and "int.__" not in seen)
a = seen.find("import fs ")
b = seen.find('assert_eq(label(15), "FizzBuzz")\n}')
print("primer", a >= 0 and b > a)
if a >= 0 and b > a:
    open(sys.argv[2], "w").write(seen[a:b] + 'assert_eq(label(15), "FizzBuzz")\n}\n')
EOF
has "with a person there, the model is told the machine is theirs" "^own machine True$" "$tmp/told.out"
if command -v "$almide" > /dev/null 2>&1; then
  has "with almide installed, the model is told of the reference tool in one line, not the syntax" "^one line True$" "$tmp/told.out"
  has "the tool gives the language's syntax as a program" "^primer True$" "$tmp/told.out"
  has "and one module's functions, without the module's own workings" "^module True$" "$tmp/told.out"
  ( cd "$tmp" && : > notes.txt && "$almide" check primer.almd > "$tmp/primer.check" 2>&1 && "$almide" test primer.almd > "$tmp/primer.test" 2>&1 )
  same "and that program passes almide check and its own test" "0" "$?"
fi

say "== the conversation's commands: going back, going on, writing it out"
# Two requests, each changing the project; then back to before the second (files only),
# back to before the first (both), an export, and the commands that only say something.
# The project has a repository of its own, which must be left as it was.
rm -rf "$tmp/cfake" "$tmp/cproj" "$tmp/chome"; mkdir -p "$tmp/cfake" "$tmp/cproj/ignored" "$tmp/chome"
( cd "$tmp/cproj" && git init -q && echo one > a.txt && echo keep > keep.txt && echo 'ignored/' > .gitignore && echo x > ignored/i.txt )
python3 - "$tmp/cfake" <<'EOF'
import json, sys
def say(commands, done=False, analysis="a"):
    return {"content": json.dumps({"analysis": analysis, "plan": "p", "commands": commands, "task_complete": done})}
# The first request changes a file with a tool, makes one and removes one in the terminal
# by name, and makes one without naming it in a way that can be read (the name is put
# together by the program). The second changes the first file again.
r = [say([{"tool": "write", "args": {"path": "a.txt", "content": "two\n"}}, {"command": "echo new > b.txt; rm keep.txt"},
          {"command": "python3 -c \"open('gen' + chr(46) + 'txt', 'w').write('g')\""}]), say([], True, "First done."), say([], True, "First done."),
     say([{"tool": "write", "args": {"path": "a.txt", "content": "three\n"}}]), say([], True, "Second done."), say([], True, "Second done.")]
for i, x in enumerate(r, 1):
    json.dump(x, open(f"{sys.argv[1]}/reply-{i}.json", "w"))
EOF
talk() { ( cd "$tmp/cproj" && HOME="$tmp/chome" XDG_CONFIG_HOME="$tmp/chome/.config" LOCAL_BASE_URL=http://127.0.0.1:9/v1 LOCAL_API_KEY=none COMIDE_SEARXNG_URL=http://127.0.0.1:9 COMIDE_FAKE="$tmp/cfake" \
  "$here/comide" --yes --model local:stand-in 2>&1 | sed 's/'"$(printf '\033')"'\[[0-9;]*m//g' ); }
printf '%s\n' 'change the files' 'change again' '/rewind' '/rewind 1 files' '/export' '/export out.md' '/context' '/status' '/permissions' '/mcp' '/hooks' '/skills' '/agents' '/doctor' '/login' '/usage' '/nope' '/exit' | talk > "$tmp/c1.txt"
has "/rewind lists the requests of the run, the last first" "1\. change again" "$tmp/c1.txt"
has "the files go back to before a request" "M a.txt" "$tmp/c1.txt"
[ "$(cat "$tmp/cproj/a.txt")" = two ] && [ -f "$tmp/cproj/b.txt" ] && [ ! -e "$tmp/cproj/keep.txt" ] && good "back before the second request: its change is undone, the first request's stay" || bad "the files after /rewind 1 files: a.txt=$(cat "$tmp/cproj/a.txt")"
has "/export writes the conversation where comide keeps its own" "written to .*/\.comide/exports/[0-9]*\.md" "$tmp/c1.txt"
exported=$(ls "$tmp"/chome/.comide/exports/*.md 2>/dev/null | head -1)
grep -q '^## You' "$exported" && grep -q 'change the files' "$exported" && grep -q 'Second done\.' "$exported" && ! grep -q 'You are comide' "$exported" \
  && good "the export has what was asked and answered, and not the system prompt" || bad "the export's contents"
[ -f "$tmp/cproj/out.md" ] && good "/export FILE writes there" || bad "/export out.md wrote no file"
has "/context says how big the conversation is" "messages, about .*k characters" "$tmp/c1.txt"
has "/status says where things are kept" "settings: .*settings\.json" "$tmp/c1.txt"
has "/permissions says what runs without asking" "run without asking: " "$tmp/c1.txt"
has "/mcp, /hooks and /skills say what is set up" "no MCP servers are set" "$tmp/c1.txt"
has "/doctor says which programs are there" "^ *ok  *golemide$" "$tmp/c1.txt"
has "a command from habit that comide has no use for is answered with what to do" "/login is not a command here" "$tmp/c1.txt"
has "another name for a command works" "this session: .* model calls" "$tmp/c1.txt"
has "a command that is nothing is said to be" "no command /nope" "$tmp/c1.txt"

rm -f "$tmp/cproj/out.md" "$tmp"/cfake/request-*
( cd "$tmp/cproj" && echo one > a.txt && echo keep > keep.txt && rm -f b.txt && echo x > ignored/i.txt )
rm -rf "$tmp/chome"; mkdir -p "$tmp/chome"
printf '%s\n' 'change the files' 'change again' '/rewind 2' '/exit' | talk > "$tmp/c2.txt"
has "back before the first request, the conversation goes back too" "the conversation is back to before: change the files" "$tmp/c2.txt"
[ "$(cat "$tmp/cproj/a.txt")" = one ] && [ "$(cat "$tmp/cproj/keep.txt" 2>/dev/null)" = keep ] && [ ! -e "$tmp/cproj/b.txt" ] \
  && good "what a tool changed is as it was, what a command removed by name is back, what it made by name is gone" || bad "the files after /rewind 2: $(ls "$tmp/cproj")"
[ -f "$tmp/cproj/gen.txt" ] && grep -q "changed since and not kept" "$tmp/c2.txt" && grep -q "^ *gen\.txt$" "$tmp/c2.txt" \
  && good "what a command made without naming it is left, and said to be" || bad "the unnamed file: $(ls "$tmp/cproj"); $(grep -c 'not kept' "$tmp/c2.txt") notes"
[ -z "$(cd "$tmp/cproj" && git log --oneline 2>/dev/null)" ] && [ -z "$(cd "$tmp/cproj" && git diff --cached --name-only)" ] && [ -z "$(find "$tmp/chome/.comide" -name HEAD)" ] \
  && good "no repository is touched or made: the project's has no commit and nothing staged, and comide keeps none" || bad "a repository was touched or made"
[ -z "$(ls "$tmp"/chome/.comide/sessions/*/ 2>/dev/null)" ] && good "a conversation gone back to its start is not kept for --continue" || bad "the undone conversation is still kept"

# A conversation taken up again can still go back: the copies and the marks are kept under
# its name, not the run's.
rm -f "$tmp"/cfake/request-* "$tmp/cproj/gen.txt"
( cd "$tmp/cproj" && echo one > a.txt && echo keep > keep.txt && rm -f b.txt )
rm -rf "$tmp/chome"; mkdir -p "$tmp/chome"
printf '%s\n' 'change the files' '/exit' | talk > /dev/null
rm -f "$tmp"/cfake/request-*
printf '%s\n' '/rewind 1' '/exit' | ( cd "$tmp/cproj" && HOME="$tmp/chome" XDG_CONFIG_HOME="$tmp/chome/.config" LOCAL_BASE_URL=http://127.0.0.1:9/v1 LOCAL_API_KEY=none COMIDE_SEARXNG_URL=http://127.0.0.1:9 COMIDE_FAKE="$tmp/cfake" \
  "$here/comide" --continue --yes --model local:stand-in > "$tmp/c4.txt" 2>&1 )
[ "$(cat "$tmp/cproj/a.txt")" = one ] && [ "$(cat "$tmp/cproj/keep.txt" 2>/dev/null)" = keep ] && [ ! -e "$tmp/cproj/b.txt" ] \
  && good "taken up again in a new run, the conversation's last request can still be gone back over" || bad "/rewind after --continue: a.txt=$(cat "$tmp/cproj/a.txt"); $(ls "$tmp/cproj")"
rm -f "$tmp/cproj/gen.txt"

rm -f "$tmp"/cfake/request-*
printf '%s\n' 'change the files' '/exit' | talk > /dev/null
kept=$(ls "$tmp"/chome/.comide/sessions/*/ | sed 's/\.json$//' | head -1)
rm -f "$tmp"/cfake/request-*
printf '%s\n' '/resume' "/resume $kept" '/exit' | talk > "$tmp/c3.txt"
has "/resume lists the project's earlier conversations" "$kept .*change the files" "$tmp/c3.txt"
has "/resume ID goes on with one" "going on with the conversation of .*change the files" "$tmp/c3.txt"

say "== without a task, nothing is started"
./comide errand > /dev/null 2>&1
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
  # Its other tools are components, each with only what it needs (src/tool*.almd).
  has "the agent is told of the tools its composition gives, asked of nautra" "^tools-told=True$" "$tmp/probe.out"
  has "a file is written by a tool from a text after the object" "^tool-wrote=True$" "$tmp/probe.out"
  has "and is on the host as it was written" "^tool-file=True$" "$tmp/probe.out"
  has "and read back by the path the host knows it by" "^tool-read=True$" "$tmp/probe.out"
  has "the tool that writes cannot write beside the project" "^tool-escaped=False$" "$tmp/probe.out"
  has "the tool that reads cannot read the system's files" "^tool-hosts=True$" "$tmp/probe.out"
  has "the reference tool, given nothing, says what it holds" "^tool-reference=True$" "$tmp/probe.out"
  has "a tool the composition does not give is said back" "^tool-unknown=True$" "$tmp/probe.out"
  # hew as a component (hew's ci/build-wasm.sh), when it is here: four more tools.
  if grep -q '^hew-' "$tmp/probe.out"; then
    has "hew outlines a file from inside its sandbox" "^hew-outline=True$" "$tmp/probe.out"
    has "and searches the project" "^hew-search=True$" "$tmp/probe.out"
    has "and reads one function by name" "^hew-read=True$" "$tmp/probe.out"
  else
    say "skipped: no hew component (HEW_WASM, or ../hew/build/hew.wasm)"
  fi
  # golemide's edit as a component (golemide's ci/build-wasm.sh), when it is here.
  if grep -q '^golemide-edit=' "$tmp/probe.out"; then
    has "golemide edits a file from inside its sandbox, the passage quoted loosely" "^golemide-edit=True$" "$tmp/probe.out"
    has "and refuses a file that does not parse, with no checker program to run" "^golemide-gate=True$" "$tmp/probe.out"
  else
    say "skipped: no golemide edit component (GOLEMIDE_EDIT_WASM, or ../golemide/build/golemide-edit.wasm)"
  fi

  say "== --confined: the conversation here, its terminal behind nautra's door"
  # The native comide, with every terminal order sent to the terminal nautra publishes.
  # The walls are tried from inside by a stand-in model; then comide is asked for a
  # confined terminal where there is no nautra, and must not start.
  rm -rf "$tmp/fake"; mkdir -p "$tmp/fake" "$probe/cw/proj" "$probe/cw/outside"
  echo seed > "$probe/cw/proj/seed.txt"
  python3 - "$tmp/fake" "$probe/cw" <<'EOF'
import json, sys
fake, P = sys.argv[1:3]
def say(commands, done=False, analysis="a"):
    return {"content": json.dumps({"analysis": analysis, "plan": "p", "commands": commands, "task_complete": done})}
tries = [
    {"command": "cat seed.txt > /dev/null && echo made > made.txt; echo inside=$?"},
    {"command": f"echo x > {P}/outside/escape.txt 2> /dev/null; echo outside=$?"},
    {"command": "ls ~ > /dev/null 2>&1; echo home=$?"},
    {"command": "cat ~/.ssh/* > /dev/null 2>&1; echo ssh=$?"},
    {"command": "curl -sS -m 4 -o /dev/null https://example.com 2> /dev/null; echo net=$?", "wait_s": 10},
    {"command": "mkdir -p sub && cd sub && export V=kept"},
    {"command": "echo kept=$(basename $(pwd))-$V"},
]
replies = [say(tries), say([], done=True, analysis="Done."), say([], done=True, analysis="Done.")]
for i, r in enumerate(replies, 1):
    json.dump(r, open(f"{fake}/reply-{i}.json", "w"))
EOF
  LOCAL_BASE_URL=http://127.0.0.1:9/v1 LOCAL_API_KEY=none COMIDE_SEARXNG_URL=http://127.0.0.1:9 COMIDE_SHELL="$here/build/comide-shell" COMIDE_FAKE="$tmp/fake" ./comide -p "try the walls" --yes --confined --model local:stand-in --root "$probe/cw/proj" > "$tmp/cw.out" 2> "$tmp/cw.err"
  same "exit 0" "0" "$?"
  python3 - "$tmp/fake" > "$tmp/cw.sent" <<'EOF'
import json, re, sys
r1 = json.load(open(sys.argv[1] + "/request-1.json"))["messages"]
seen = json.load(open(sys.argv[1] + "/request-2.json"))["messages"][-1]["content"]
print("told", "Your terminal is confined" in r1[0]["content"])
for name in ("inside", "outside", "home", "ssh", "net", "kept"):
    m = re.search("^" + name + r"=(\S+)", seen, re.M)
    print(name + "=" + (m.group(1) if m else "?"))
print("moved", "[the terminal is now in " in seen)
EOF
  has "the person is told the terminal is confined" "terminal confined by nautra" "$tmp/cw.err"
  has "and so is the model" "^told True$" "$tmp/cw.sent"
  has "the project can be read and written" "^inside=0$" "$tmp/cw.sent"
  same "and the file is there" "made" "$(cat "$probe/cw/proj/made.txt" 2>/dev/null)"
  has "beside the project nothing can be written" "^outside=1$" "$tmp/cw.sent"
  if [ -e "$probe/cw/outside/escape.txt" ]; then bad "and nothing was"; else say "ok: and nothing was"; fi
  has "the home directory cannot be listed" "^home=1$" "$tmp/cw.sent"
  has "nor ~/.ssh read" "^ssh=1$" "$tmp/cw.sent"
  has "no host can be reached" "^net=6$" "$tmp/cw.sent"
  has "the directory and the variables last from command to command" "^kept=sub-kept$" "$tmp/cw.sent"
  has "and the model is told where the terminal now is" "^moved True$" "$tmp/cw.sent"
  if pgrep -f "confined-.*\.toml" > /dev/null 2>&1; then bad "nautra's door is closed when the conversation ends"; else say "ok: nautra's door is closed when the conversation ends"; fi
  rm -f "$probe/cw/proj/made.txt"
  NAUTRA=/nonexistent/nautra LOCAL_BASE_URL=http://127.0.0.1:9/v1 LOCAL_API_KEY=none COMIDE_SEARXNG_URL=http://127.0.0.1:9 COMIDE_SHELL="$here/build/comide-shell" COMIDE_FAKE="$tmp/fake" ./comide -p "try the walls" --yes --confined --model local:stand-in --root "$probe/cw/proj" > "$tmp/cw2.out" 2> "$tmp/cw2.err"
  if [ "$?" -ne 0 ] && [ ! -e "$probe/cw/proj/made.txt" ]; then say "ok: without nautra a confined conversation does not start, and nothing runs unconfined"; else bad "without nautra a confined conversation does not start, and nothing runs unconfined"; fi
  rm -rf "$probe"
fi

say ""
if [ "$fails" -eq 0 ]; then say "all checks passed"; else say "$fails failed"; exit 1; fi
