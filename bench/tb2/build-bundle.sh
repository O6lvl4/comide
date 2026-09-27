#!/usr/bin/env bash
# Builds the Linux bundle Terminal-Bench runs comide from (bench/tb2/Dockerfile) and
# unpacks it to $OUT/bundle: bin/{comide,golemide,gramide,hew,ctxgate,porta}.
#
#   bench/tb2/build-bundle.sh
#   OUT=/tmp/tb2 PLATFORM=linux/amd64 bench/tb2/build-bundle.sh
#
# Each tool is built from its repository's committed HEAD (git archive), not the working
# tree, so what ran is a commit that can be named. The commits go in $OUT/bundle/SOURCES.
#
#   OUT             where the bundle lands     (default: $TMPDIR/comide-tb2)
#   PLATFORM        the Docker platform         (default: the host's)
#   COMPANIONS_DIR  the local clones            (default: ~/workspace/github.com/O6lvl4)
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUT="${OUT:-${TMPDIR:-/tmp}/comide-tb2}"
COMPANIONS_DIR="${COMPANIONS_DIR:-$HOME/workspace/github.com/O6lvl4}"
PLATFORM="${PLATFORM:-}"
IMAGE=comide-tb2-bundle

ctx="$OUT/context"
rm -rf "$ctx" && mkdir -p "$ctx/src"
cp "$HERE/Dockerfile" "$ctx/"
: > "$ctx/SOURCES"
for repo in gramide-cli hew ctxgate golemide comide; do
  dir="$COMPANIONS_DIR/$repo"
  [ -d "$dir/.git" ] || { echo "not a clone: $dir" >&2; exit 2; }
  mkdir -p "$ctx/src/$repo"
  git -C "$dir" archive HEAD | tar -x -C "$ctx/src/$repo"
  echo "$repo $(git -C "$dir" rev-parse --short HEAD)" >> "$ctx/SOURCES"
done
cat "$ctx/SOURCES"

docker build ${PLATFORM:+--platform "$PLATFORM"} -t "$IMAGE" "$ctx"

rm -rf "$OUT/bundle"
id="$(docker create ${PLATFORM:+--platform "$PLATFORM"} "$IMAGE")"
docker cp "$id:/bundle" "$OUT/bundle"
docker rm "$id" > /dev/null
cp "$ctx/SOURCES" "$OUT/bundle/SOURCES"
echo "== bundle at $OUT/bundle (needs $(cat "$OUT/bundle/glibc-needed"))"
ls -la "$OUT/bundle/bin"
