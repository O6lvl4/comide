#!/usr/bin/env python3
"""Runs a program with SIGINT put back to its default.

    python3 bench/tb2/unignored.py PROGRAM [ARG...] &

A command a script puts in the background starts with SIGINT ignored, and a program cannot
be interrupted by a signal it was started ignoring (Python does not even install its
handler then). Harbor takes its containers down on an interrupt, so bench/tb2/measure.sh starts it
through this. The program takes this process's place, so the pid the script holds is the
program's own.
"""
import os
import signal
import sys

signal.signal(signal.SIGINT, signal.SIG_DFL)
os.execvp(sys.argv[1], sys.argv[1:])
