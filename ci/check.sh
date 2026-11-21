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
           say([], done=True), say([], done=True, analysis="Wrote made.txt; it says hi."),
           say([{"command": "echo more >> made.txt"}, {"command": "echo never > never.txt"}, {"command": "echo after > after.txt"}]),
           say([], done=True), say([], done=True, analysis="Added a line.")]
for i, r in enumerate(replies, 1):
    json.dump(r, open(f"{sys.argv[1]}/reply-{i}.json", "w"))
EOF
conv() { HOME="$tmp/home" LOCAL_BASE_URL=http://127.0.0.1:9/v1 LOCAL_API_KEY=none COMIDE_FAKE="$tmp/fake" ./comide "$@" --loop written --model local:stand-in --root "$tmp/conv"; }
conv -p "make the file" --yes > "$tmp/conv1.out" 2> "$tmp/conv1.err"
same "exit 0" "0" "$?"
has "the last analysis is the answer" "Wrote made.txt; it says hi." "$tmp/conv1.out"
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
def say(commands, done=False, tail=""):
    return {"content": json.dumps({"analysis": "a", "plan": "p", "commands": commands, "task_complete": done}) + tail}
body = "\n<<<BODY make\ncat > made.py <<'PY'\nd = {\"k\": [1, 2]}\nprint(\"}\" + str(d[\"k\"][1]))\nPY\npython3 made.py > made.out\n>>>BODY make\n"
replies = [say([{"command": "@body:make", "wait_s": 10}], tail=body),
           say([{"command": "@body:missing"}]),
           say([], done=True), say([], done=True)]
for i, r in enumerate(replies, 1):
    json.dump(r, open(f"{sys.argv[1]}/reply-{i}.json", "w"))
EOF
HOME="$tmp/home" LOCAL_BASE_URL=http://127.0.0.1:9/v1 LOCAL_API_KEY=none COMIDE_SEARXNG_URL=http://127.0.0.1:9 COMIDE_FAKE="$tmp/fake" \
  ./comide -p "make it" --yes --model local:stand-in --root "$tmp/bd" > "$tmp/bd.out" 2> "$tmp/bd.err"
same "exit 0" "0" "$?"
same "the text ran as it was written" "}2" "$(cat "$tmp/bd/made.out" 2>/dev/null)"
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
replies = [say([{"command": "echo one; sleep 2; echo two", "wait_s": 10}]),
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

# What the model was told in that conversation: the machine is the person's, and, where
# almide is installed, the language's syntax as a program. The program is taken out of the
# prompt and given to the compiler, so the text a model learns from cannot rot unseen.
python3 - "$tmp/fake" "$tmp/primer.almd" > "$tmp/told.out" <<'EOF'
import json, sys
system = json.load(open(sys.argv[1] + "/request-1.json"))["messages"][0]["content"]
print("own machine", "This is the user's own machine" in system)
a = system.find("import fs ")
b = system.find('assert_eq(label(15), "FizzBuzz")\n}')
print("primer", a >= 0 and b > a)
if a >= 0 and b > a:
    open(sys.argv[2], "w").write(system[a:b] + 'assert_eq(label(15), "FizzBuzz")\n}\n')
EOF
has "with a person there, the model is told the machine is theirs" "^own machine True$" "$tmp/told.out"
if command -v "$almide" > /dev/null 2>&1; then
  has "with almide installed, the model is given the language's syntax as a program" "^primer True$" "$tmp/told.out"
  ( cd "$tmp" && : > notes.txt && "$almide" check primer.almd > "$tmp/primer.check" 2>&1 && "$almide" test primer.almd > "$tmp/primer.test" 2>&1 )
  same "and that program passes almide check and its own test" "0" "$?"
fi

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
  rm -rf "$probe"
fi

say ""
if [ "$fails" -eq 0 ]; then say "all checks passed"; else say "$fails failed"; exit 1; fi
