"""Small tasks put to comide's conversation loop (`comide run`), one request each.

    convo.py run OUT --bin PATH [--jobs N] [--only IDS]
    convo.py score OUT [OUT ...]

What it is for: a guard that a change to the conversation's prompt has not broken it.
Twelve tasks, four of which pass untouched: it cannot show that a change made anything
better. Read the numbers as "not worse", or "worse".

The tasks are CodeIPI's ten samples without an injection (the same dataset bench/ipi
reads; its samples with an injection are run in the lab only, never here) and two of
ours that make the model write a file of some length.

comide runs on this machine, not in an enclosure, with --yes: only tasks with nothing
planted in them belong here. Its HOME is a directory under OUT, so nothing is read from
or written to the user's own ~/.comide; the model's credentials are read from the file
KEYS names (NAME=VALUE lines) and are not printed.

    CONVO_LIMIT_USD   no new task is started once the runs under OUT have cost this (1)
"""
import json
import os
import subprocess
import sys
from concurrent.futures import ThreadPoolExecutor

DATASET = os.environ.get("IPI_DATASET", os.path.expanduser(
    "~/.cache/comide/ext/inspect_evals/src/inspect_evals/ipi_coding_agent"))
LIMIT = float(os.environ.get("CONVO_LIMIT_USD", "1"))

OURS = [
    {"id": "ours-textstat",
     "task": "In this directory create textstat.py with these functions, each with a docstring: "
             "word_count(text) -> int (words are separated by whitespace); "
             "line_count(text) -> int (an empty string has 0 lines; a text that does not end in a newline still counts its last line); "
             "most_common_words(text, n) -> list of (word, count) for the n most frequent words, lower-cased, "
             "punctuation .,!?;: stripped from both ends of a word, ties broken alphabetically; "
             "average_word_length(text) -> float (0.0 for no words; lengths after the same stripping); "
             "is_palindrome(text) -> bool (letters and digits only, case ignored). "
             "Also create tests/test_textstat.py with at least eight pytest tests, and run them.",
     "check": "import textstat as t\n"
              "assert t.word_count('a  b\\nc') == 3 and t.word_count('') == 0\n"
              "assert t.line_count('') == 0 and t.line_count('a\\nb') == 2 and t.line_count('a\\nb\\n') == 2\n"
              "assert t.most_common_words('B a. b, A! c', 2) == [('a', 2), ('b', 2)]\n"
              "assert t.average_word_length('') == 0.0 and abs(t.average_word_length('ab, abcd.') - 3.0) < 1e-9\n"
              "assert t.is_palindrome('A man, a plan, a canal: Panama') and not t.is_palindrome('ab')\n",
     "after": "python -m pytest tests/ -q"},
    {"id": "ours-inventory",
     "task": "In this directory create inventory.py with a class Inventory: add(name, qty) adds stock; "
             "remove(name, qty) takes stock away and raises ValueError when there is not enough, or the name is unknown; "
             "quantity(name) -> int (0 when unknown); total() -> int, the sum of all quantities; "
             "to_json() -> str and the classmethod from_json(s), which give back an equal inventory. "
             "A name whose quantity reaches 0 is no longer listed by names() -> sorted list of names. "
             "When run as a script it reads lines from standard input, 'add NAME QTY', 'remove NAME QTY', 'total', "
             "and prints the total for each 'total' line and 'error: ' followed by the reason for a remove that fails. "
             "Also create tests/test_inventory.py with at least eight pytest tests, and run them.",
     "check": "import subprocess, sys\n"
              "from inventory import Inventory\n"
              "i = Inventory(); i.add('a', 3); i.add('b', 2); i.remove('a', 1)\n"
              "assert i.quantity('a') == 2 and i.quantity('z') == 0 and i.total() == 4\n"
              "for bad in (('a', 5), ('z', 1)):\n"
              "    try:\n        i.remove(*bad); raise SystemExit('no error')\n    except ValueError:\n        pass\n"
              "j = Inventory.from_json(i.to_json()); assert j.total() == 4 and j.names() == ['a', 'b']\n"
              "i.remove('b', 2); assert i.names() == ['a']\n"
              "out = subprocess.run([sys.executable, 'inventory.py'], input='add x 2\\ntotal\\nremove x 5\\ntotal\\n', capture_output=True, text=True).stdout.splitlines()\n"
              "assert out[0] == '2' and out[1].startswith('error: ') and out[2] == '2', out\n",
     "after": "python -m pytest tests/ -q"},
]


def tasks():
    found = []
    for s in json.load(open(os.path.join(DATASET, "dataset", "samples.json"))):
        if s.get("is_benign"):
            text = s["task_description"] + ("\n\n" + s["issue_text"] if s.get("issue_text") else "")
            found.append({"id": s["id"], "task": text, "files": s["repo_files"], "check": "",
                          "after": s["verification_command"].replace("cd /workspace && ", "")})
    return found + [dict(t, files={}) for t in OURS]


def credentials():
    path = os.environ.get("KEYS", "")
    if not os.path.isfile(path):
        sys.exit("KEYS must name a file holding the model's credentials")
    found = {}
    for line in open(path):
        line = line.strip()
        if "=" in line and not line.startswith("#"):
            k, v = line.split("=", 1)
            found[k.replace("export ", "").strip()] = v.strip().strip("'\"")
    return found


def session_of(home):
    """The one conversation kept under this HOME, as comide wrote it."""
    base = os.path.join(home, ".comide", "sessions")
    for d, _dirs, names in os.walk(base):
        for n in names:
            if n.endswith(".json"):
                try:
                    return json.load(open(os.path.join(d, n)))
                except ValueError:
                    pass
    return {}


def spent(out):
    total = 0.0
    for name in os.listdir(out):
        if name != "venv":
            total +=float(session_of(os.path.join(out, name, "home")).get("cost") or 0)
    return total


def run_one(t, out, binary):
    d = os.path.join(out, t["id"])
    if os.path.exists(os.path.join(d, "done")):
        return t["id"], "kept"
    if spent(out) >= LIMIT:
        return t["id"], "not run: the limit is reached"
    work, home = os.path.join(d, "work"), os.path.join(d, "home")
    os.makedirs(work, exist_ok=True)
    os.makedirs(home, exist_ok=True)
    for path, content in t["files"].items():
        full = os.path.join(work, path)
        os.makedirs(os.path.dirname(full), exist_ok=True)
        open(full, "w").write(content)
    # A Python of the run's own first on the path: on the first try the model installed a
    # package, and it went into the user's.
    venv = os.path.join(out, "venv")
    path = os.path.join(venv, "bin") + os.pathsep + os.environ["PATH"]
    env = {k: v for k, v in os.environ.items() if k in ("LANG", "TERM", "TMPDIR")}
    env.update(credentials(), HOME=home, NO_COLOR="1", COMIDE_NOTIFY="0", PATH=path, VIRTUAL_ENV=venv, PIP_USER="0")
    task = "The codebase is in " + work + ".\n\n" + t["task"]
    with open(os.path.join(d, "run.out"), "w") as log:
        try:
            code = subprocess.call([binary, "run", task, "--yes", "--root", work, "--max-steps", "30"],
                                   cwd=work, env=env, stdin=subprocess.DEVNULL, stdout=log, stderr=log, timeout=900)
        except subprocess.TimeoutExpired:
            code = "timeout"
    clean = {k: v for k, v in os.environ.items() if k in ("LANG", "TMPDIR")}
    clean.update(PATH=path, VIRTUAL_ENV=venv, HOME=home)
    passed = subprocess.call(["sh", "-c", t["after"]], cwd=work, env=clean, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=300) == 0
    if passed and t["check"]:
        passed = subprocess.call(["python", "-c", t["check"]], cwd=work, env=clean, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=120) == 0
    open(os.path.join(d, "done"), "w").write(json.dumps({"exit": code, "passed": passed}) + "\n")
    return t["id"], code


def row(out, t):
    d = os.path.join(out, t["id"])
    try:
        done = json.loads(open(os.path.join(d, "done")).read())
    except (OSError, ValueError):
        return None
    s = session_of(os.path.join(d, "home"))
    said = [m for m in s.get("messages", []) if isinstance(m.get("content"), str)]
    users = [m["content"] for m in said if m["role"] == "user"]
    asked = [i for i, m in enumerate(said) if m["role"] == "user" and ("task_complete\": true in your JSON response again" in m["content"])]
    after_asked = sum(1 for m in said[asked[0]:] if m["role"] == "assistant") if asked else -1
    texts = sum(1 for m in said if m["role"] == "assistant" and "@body:" in m["content"])
    return {"id": t["id"], "passed": done["passed"], "exit": done["exit"], "cost": float(s.get("cost") or 0),
            "replies": sum(1 for m in said if m["role"] == "assistant"),
            "unread": sum(1 for u in users if u.startswith("Previous response")),
            "texts": texts, "asked": len(asked), "after_asked": after_asked}


def main():
    if len(sys.argv) < 3 or sys.argv[1] not in ("run", "score"):
        sys.exit(__doc__)
    if sys.argv[1] == "run":
        out = os.path.abspath(sys.argv[2])
        args = sys.argv[3:]
        binary = os.path.abspath(args[args.index("--bin") + 1])
        jobs = int(args[args.index("--jobs") + 1]) if "--jobs" in args else 4
        only = args[args.index("--only") + 1].split(",") if "--only" in args else None
        os.makedirs(out, exist_ok=True)
        if not os.path.isdir(os.path.join(out, "venv")):
            subprocess.check_call([sys.executable, "-m", "venv", os.path.join(out, "venv")])
            subprocess.check_call([os.path.join(out, "venv", "bin", "python"), "-m", "pip", "install", "-q", "pytest"])
        chosen = [t for t in tasks() if only is None or t["id"] in only]
        with ThreadPoolExecutor(jobs) as pool:
            for name, code in pool.map(lambda t: run_one(t, out, binary), chosen):
                print(name, code, flush=True)
        return
    for out in sys.argv[2:]:
        rows = [r for r in (row(out, t) for t in tasks()) if r]
        print(f"{out}: passed {sum(r['passed'] for r in rows)}/{len(rows)}  cost ${sum(r['cost'] for r in rows):.3f}  "
              f"replies {sum(r['replies'] for r in rows)}  unread {sum(r['unread'] for r in rows)}  "
              f"replies naming a text {sum(r['texts'] for r in rows)}  "
              f"asked if finished {sum(r['asked'] for r in rows)}  ended one reply after being asked {sum(1 for r in rows if r['after_asked'] == 1)}/{sum(1 for r in rows if r['asked'])}")
        for r in rows:
            print(f"  {r['id']:28} {'pass' if r['passed'] else 'FAIL'}  exit {r['exit']}  ${r['cost']:.3f}  replies {r['replies']:2}  unread {r['unread']}  asked {r['asked']} (+{r['after_asked']})")


if __name__ == "__main__":
    main()
