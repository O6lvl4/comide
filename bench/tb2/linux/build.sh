#!/bin/sh
# Builds comide alone for Linux (bench/tb2/linux/Dockerfile) and puts it at $OUT/comide,
# with the commit it was built from in $OUT/SOURCE. For `comide errand` in a task's
# container (errand_agent.py); the bundle with golemide and the other tools is
# bench/tb2/build-bundle.sh.
#
#   bench/tb2/linux/build.sh
#
# It is built from the committed HEAD (git archive), not the working tree, so what a
# measurement ran is a commit that can be named.
#
#   OUT        where the binary lands      (default: $TMPDIR/comide-linux)
#   PLATFORM   the Docker platform         (default: the host's)
set -eu

here=$(cd "$(dirname "$0")/../../.." && pwd)
OUT=${OUT:-${TMPDIR:-/tmp}/comide-linux}
ctx="$OUT/context"
rm -rf "$ctx"
mkdir -p "$ctx/src"
cp "$here/bench/tb2/linux/Dockerfile" "$ctx/"
git -C "$here" archive HEAD almide.toml almide.lock src | tar -x -C "$ctx/src"

docker build ${PLATFORM:+--platform "$PLATFORM"} -t comide-linux "$ctx"
id=$(docker create ${PLATFORM:+--platform "$PLATFORM"} comide-linux)
docker cp "$id:/out/comide" "$OUT/comide"
docker cp "$id:/out/glibc-needed" "$OUT/glibc-needed"
docker rm "$id" > /dev/null
echo "comide $(git -C "$here" rev-parse --short HEAD)" > "$OUT/SOURCE"
echo "== $OUT/comide, from $(cat "$OUT/SOURCE"), needs $(cat "$OUT/glibc-needed")"
