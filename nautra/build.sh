#!/bin/sh
# Builds the two halves of comide that run under nautra, into build/:
#
#   build/comide.wasm     the agent, a WebAssembly component (src/enclosed.almd)
#   build/comide-shell    its terminal, a native program (src/shelltool.almd)
set -eu
here=$(cd "$(dirname "$0")/.." && pwd)
cd "$here"
mkdir -p build
almide build src/enclosed.almd --target wasm -o build/comide.wasm
almide build src/shelltool.almd -o build/comide-shell
