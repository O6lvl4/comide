"""Runs a program in a pseudo-terminal, types what it is told at the times it is told,
and prints what the screen was sent. Ends the program after a time limit, whatever it does.

  ptydrive.py SECONDS 'KEYS@T,KEYS@T,...' -- program args...

KEYS is a Python string literal body (\\x7f, \\r); T is seconds from the start.
"""
import os, pty, re, select, signal, sys, time

limit = float(sys.argv[1])
steps = []
for part in sys.argv[2].split(","):
    keys, at = part.rsplit("@", 1)
    steps.append((float(at), keys.encode("utf-8").decode("unicode_escape").encode("latin-1").decode("utf-8", "replace")
                  if "\\" in keys else keys))
argv = sys.argv[sys.argv.index("--") + 1:]

pid, fd = pty.fork()
if pid == 0:
    os.execvp(argv[0], argv)
t0 = time.time()
out = b""
steps.sort()
while time.time() - t0 < limit:
    while steps and time.time() - t0 >= steps[0][0]:
        os.write(fd, steps.pop(0)[1].encode("utf-8"))
    r, _, _ = select.select([fd], [], [], 0.05)
    if r:
        try:
            data = os.read(fd, 65536)
        except OSError:
            break
        if not data:
            break
        out += data
try:
    os.kill(pid, signal.SIGKILL)
except ProcessLookupError:
    pass
sys.stdout.write(out.decode("utf-8", "replace"))
