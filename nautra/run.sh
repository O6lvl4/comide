#!/bin/sh
# comide under nautra: the agent holds no key and its terminal cannot leave the workspace.
#
#   nautra/run.sh TASK [--root DIR]
#
#   --root DIR   the workspace: the one directory the terminal may write in
#                (default: this directory)
#
# What is granted, and nothing else:
#
#   the agent      the model's host, with the key bound to it by nautra (the agent holds a
#                  placeholder); a directory for its record
#   the terminal   the workspace and its own state directory, read and write; reads
#                  elsewhere as the sandbox allows a toolchain; no network unless NET names it
#
#   NAUTRA   the nautra binary        (default: nautra on PATH)
#   MODEL    the model, as almai names it      (default: cf:glm-5.3)
#   KEYS     a file of NAME=VALUE lines holding CLOUDFLARE_ACCOUNT_ID and
#            CLOUDFLARE_API_TOKEN. Required unless PROVIDER_SECRET names another provider.
#            Keep it in a directory of its own: the terminal is barred from reading that
#            whole directory, whatever else it may read
#   NET      hosts the terminal may reach over HTTPS, space separated     (default: none)
#   READS    closed: the terminal reads its mounts and the system directories only;
#            open: anywhere the sandbox allows, for a toolchain installed under the home
#            directory                                                    (default: closed)
#   TOOLS    directories of installed toolchains the terminal may read, space separated
#            (default: the Xcode developer directory, /nix and /opt/homebrew, where they exist)
#   DENY_READ  directories the terminal may never read, space separated; the directory
#            KEYS is in is always one
#   RUNS     where each run's state, record and composition file are kept
#            (default: ~/.cache/comide/runs; not /tmp, which every sandboxed command may write)
#   TIMEOUT  the whole run            (default: 2h)
#
#   Another provider than Cloudflare: PROVIDER_ENV (names or NAME=VALUE the agent is given),
#   PROVIDER_SECRET (NAME@HOST[:PORT]) and PROVIDER_NET (HOST:PORT), with MODEL to match.
#
#   COMIDE_MAX_TOKENS, COMIDE_MAX_STEPS, COMIDE_REASONING_BACK, COMIDE_CHECK pass through.
set -eu

here=$(cd "$(dirname "$0")/.." && pwd)
[ $# -ge 1 ] && [ -n "$1" ] || { echo "usage: nautra/run.sh TASK [--root DIR]" >&2; exit 2; }
task=$1; shift
root=$PWD
while [ $# -gt 0 ]; do
  case $1 in
    --root) root=$2; shift 2 ;;
    *) echo "no option named $1" >&2; exit 2 ;;
  esac
done
root=$(cd "$root" && pwd)

NAUTRA=${NAUTRA:-$(command -v nautra || true)}
[ -n "$NAUTRA" ] && [ -x "$NAUTRA" ] || { echo "no nautra: put it on PATH or name it in NAUTRA" >&2; exit 2; }
for f in comide.wasm comide-shell; do
  [ -f "$here/build/$f" ] || { echo "no build/$f: run nautra/build.sh" >&2; exit 2; }
done

if [ -z "${PROVIDER_SECRET:-}" ]; then
  [ -n "${KEYS:-}" ] && [ -f "$KEYS" ] || { echo "KEYS must name a file holding the model's credentials (or set PROVIDER_SECRET)" >&2; exit 2; }
  set -a; . "$KEYS"; set +a
  keys_dir=$(cd "$(dirname "$KEYS")" && pwd)
  PROVIDER_ENV="CLOUDFLARE_ACCOUNT_ID"
  PROVIDER_SECRET="CLOUDFLARE_API_TOKEN@api.cloudflare.com"
  PROVIDER_NET="api.cloudflare.com:443"
fi

# Where toolchains are installed, read-only. Without these a closed terminal on macOS has
# /usr/bin/python3, cc and git as stubs that find no developer tools behind them.
if [ -z "${TOOLS+set}" ]; then
  TOOLS=""
  # Xcode is taken whole: its tools load frameworks from beside the developer directory.
  xcode=$(xcode-select -p 2>/dev/null || true)
  case $xcode in *.app/Contents/Developer) xcode=${xcode%/Contents/Developer} ;; esac
  for d in "$xcode" /Library/Developer/CommandLineTools /nix /opt/homebrew; do
    [ -n "$d" ] && [ -d "$d" ] || continue
    case " $TOOLS " in *" $d "*) ;; *) TOOLS="$TOOLS $d" ;; esac
  done
fi
tools=""
for d in $TOOLS; do tools="$tools $d:ro"; done

deny=""
for d in ${keys_dir:-} ${DENY_READ:-}; do deny="$deny --deny-read $d"; done

run=${RUNS:-$HOME/.cache/comide/runs}/$(date +%Y%m%d-%H%M%S)-$$
mkdir -p "$run/state" "$run/log"

quoted() { printf '"%s"' "$(printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g')"; }
list() { first=1; for x in "$@"; do [ $first = 1 ] || printf ', '; quoted "$x"; first=0; done; }

settings=""
for name in COMIDE_MAX_TOKENS COMIDE_MAX_STEPS COMIDE_REASONING_BACK COMIDE_CHECK; do
  eval "v=\${$name:-}"
  [ -z "$v" ] || settings="$settings $name=$v"
done

# shellcheck disable=SC2086
{
  echo "# Written by nautra/run.sh for one run. What is here is all the run is given."
  echo "[agent]"
  echo "image = $(quoted "$here/build/comide.wasm")"
  echo "env = [$(list ${PROVIDER_ENV:-} "COMIDE_MODEL=${MODEL:-cf:glm-5.3}" "COMIDE_LOG_DIR=/log" $settings)]"
  echo "secrets = [$(list "$PROVIDER_SECRET")]"
  echo "net = [$(list ${PROVIDER_NET:-})]"
  echo "mounts = [$(list "$run/log:/log")]"
  echo "timeout = $(quoted "${TIMEOUT:-2h}")"
  echo "max_tool_calls = 5000"
  echo
  echo "[tools.shell]"
  echo "command = [$(list "$here/build/comide-shell" "$run/state")]"
  echo "description = \"The terminal: run a command line, wait for a job, stop a job.\""
  echo 'input = { type = "object", properties = { command = { type = "string" }, job = { type = "integer" }, wait_s = { type = "integer" }, stop = { type = "boolean" }, close = { type = "boolean" } } }'
  # The workspace first: a command starts in its first mount. The last is the terminal's
  # own program, which it must be able to read to be started.
  echo "mounts = [$(list "$root" "$run/state" "$here/build:ro" $tools)]"
  [ "${READS:-closed}" != open ] || echo 'reads = "open"'
  # Whatever the terminal may read, it may not read where the keys are kept.
  echo "porta = [$(list $deny)]"
  echo "net = [$(list ${NET:-})]"
  # The host's own temporary directory is not the terminal's to write; /tmp is.
  echo 'env = ["TMPDIR=/tmp"]'
  echo 'timeout = "6m"'
  # The other tools are components, each with the least it needs: read sees the project
  # and cannot write; write has the project and nothing else; reference has nothing at
  # all. None has a network. TOOLS_OFF=1 gives the terminal alone, as before 0.8.
  if [ "${TOOLS_OFF:-0}" != 1 ]; then
    # Reading is hew's when hew is here as a component (HEW_WASM, or build/hew.wasm in a
    # hew checked out beside comide: hew's ci/build-wasm.sh makes it). One program is then
    # four tools, each started with the project read-only and nothing else.
    hew=${HEW_WASM-$here/../hew/build/hew.wasm}
    if [ -n "$hew" ] && [ -f "$hew" ]; then
      hew=$(cd "$(dirname "$hew")" && pwd)/$(basename "$hew")
      hew_tool() { # hew_tool NAME DESCRIPTION INPUT
        echo
        echo "[tools.$1]"
        echo "image = $(quoted "$hew")"
        echo "description = $(quoted "$2")"
        echo "input = $3"
        echo "mounts = [$(list "$root:/work:ro")]"
        echo "env = [$(list "HEW_TOOL=$1" "HEW_ROOT=/work" "HEW_HOST_ROOT=$root")]"
      }
      hew_tool read "Read part of a file of the project, numbered: one function or type by name (symbol), a range of lines (from, to), the lines that match (grep, around), or with only a path a short file whole and a long one as its outline. It cannot write or run anything." \
        '{ type = "object", properties = { path = { type = "string" }, symbol = { type = "string" }, from = { type = "integer" }, to = { type = "integer" }, grep = { type = "string" }, around = { type = "integer" } }, required = ["path"] }'
      hew_tool outline "What a file declares (functions, types, with their line ranges), or the same for every file of a directory. Look here before reading a file you have not seen." \
        '{ type = "object", properties = { path = { type = "string" } }, required = ["path"] }'
      hew_tool search "Search the project's files for a regular expression: the matching lines, each with the function it is in. Narrower than grep in the terminal." \
        '{ type = "object", properties = { pattern = { type = "string" }, path = { type = "string" } }, required = ["pattern"] }'
      hew_tool tree "The project's directories and files, without version-control and build noise." \
        '{ type = "object", properties = { path = { type = "string" }, depth = { type = "integer" } } }'
    else
      echo
      echo "[tools.read]"
      echo "image = $(quoted "$here/build/tool-read.wasm")"
      echo 'description = "Read a file of the project: its lines, numbered. For a long file give from and to (line numbers). It cannot write or run anything."'
      echo 'input = { type = "object", properties = { path = { type = "string" }, from = { type = "integer" }, to = { type = "integer" } }, required = ["path"] }'
      echo "mounts = [$(list "$root:/work:ro")]"
      echo "env = [$(list "ROOT=/work" "HOST_ROOT=$root")]"
    fi
    # Changing a file is golemide's when its edit is here as a component
    # (GOLEMIDE_EDIT_WASM, or build/golemide-edit.wasm in a golemide beside comide): an
    # edit that finds a passage quoted from memory, and a write that will not blank a
    # file. As a component it starts no checker; it reads with the grammars linked into it.
    gol=${GOLEMIDE_EDIT_WASM-$here/../golemide/build/golemide-edit.wasm}
    if [ -n "$gol" ] && [ -f "$gol" ]; then
      gol=$(cd "$(dirname "$gol")" && pwd)/$(basename "$gol")
      echo
      echo "[tools.edit]"
      echo "image = $(quoted "$gol")"
      echo 'description = "Change part of a file of the project: old is the passage as it is now, new what replaces it. Copy old from what read showed, without the line numbers; indentation need not be exact. For passages of more than a few lines give old and new as texts after the object (@body:NAME). The answer is JSON: ok, a diff and what checked the result (checked_by), or the reason it was refused. A result that does not parse is refused (Almide, Go, Rust, Python, JavaScript, TypeScript; brackets for the C family); an empty checked_by means nothing checked it."'
      echo 'input = { type = "object", properties = { path = { type = "string" }, old = { type = "string" }, new = { type = "string" } }, required = ["path", "old", "new"] }'
      echo "mounts = [$(list "$root:/work")]"
      echo "env = [$(list "GOLEMIDE_ROOT=/work" "GOLEMIDE_HOST_ROOT=$root")]"
      echo
      echo "[tools.write]"
      echo "image = $(quoted "$gol")"
      echo 'description = "Write a file of the project, whole: a new file, or a complete rewrite. Give the content as a text after the object (@body:NAME). It writes nowhere but the project and will not blank a file. The answer is JSON: ok, a diff and what checked the file (checked_by), or the reason it was refused. A file that does not parse is refused (Almide, Go, Rust, Python, JavaScript, TypeScript; brackets for the C family); an empty checked_by means nothing checked it."'
      echo 'input = { type = "object", properties = { path = { type = "string" }, content = { type = "string" } }, required = ["path", "content"] }'
      echo "mounts = [$(list "$root:/work")]"
      echo "env = [$(list "GOLEMIDE_ROOT=/work" "GOLEMIDE_HOST_ROOT=$root" "GOLEMIDE_CREATE=1")]"
    else
      echo
      echo "[tools.write]"
      echo "image = $(quoted "$here/build/tool-write.wasm")"
      echo 'description = "Write a file of the project, whole: a new file, or a complete rewrite. Give the content as a text after the object (@body:NAME). It writes nowhere but the project, and does not check syntax."'
      echo 'input = { type = "object", properties = { path = { type = "string" }, content = { type = "string" } }, required = ["path", "content"] }'
      echo "mounts = [$(list "$root:/work")]"
      echo "env = [$(list "ROOT=/work" "HOST_ROOT=$root")]"
    fi
    echo
    echo "[tools.reference]"
    echo "image = $(quoted "$here/build/tool-reference.wasm")"
    echo 'description = "The syntax of a language you may not know well (almide), as one checked program, and how to look up its standard library. Call it before writing that language."'
    echo 'input = { type = "object", properties = { language = { type = "string" } }, required = ["language"] }'
  fi
} > "$run/comide.toml"

echo "comide under nautra: workspace $root, record in $run" >&2
status=0
"$NAUTRA" run --audit "$run/audit.jsonl" -f "$run/comide.toml" "$task" || status=$?
exit $status
