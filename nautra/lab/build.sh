#!/bin/sh
# Builds the lab's image (nautra/lab/Dockerfile) from the working tree.
#
#   nautra/lab/build.sh
#
#   IMAGE   the image's name   (default: comide-lab)
#   SRC     the agent's source: a directory with almide.toml, almide.lock and src/
#           (default: this repository)
#   AGENT   the file in SRC/src the agent is built from, without .almd   (default: enclosed)
set -eu
here=$(cd "$(dirname "$0")/../.." && pwd)
src=$(cd "${SRC:-$here}" && pwd)
# The context is a tar stream of just what the Dockerfile copies: nothing is left behind.
tar -c -C "$src" almide.toml almide.lock src -C "$here/nautra/lab" Dockerfile relay.py target.py sink.py \
  | docker build --build-arg "AGENT=${AGENT:-enclosed}" -t "${IMAGE:-comide-lab}" -
