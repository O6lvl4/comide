#!/usr/bin/env python3
"""What a run has cost so far, worked out from the tokens its trials recorded.

    bench/tb2/cost.py RUN_DIR [MODEL]         prints the dollars, one number

terminus-2 writes no cost: Workers AI reports none through LiteLLM. It does write the
tokens of every step into each trial's agent/trajectory.json as it goes, so the cost of a
run can be read while it is still running, which is what the limit in bench/terminus2.sh
needs. A trial of an agent that writes its own cost (agent/cost.txt, "$0.1234") is taken
at its word instead.

Prices are dollars per million tokens: input not read from cache, input read from cache,
output. The cached tokens are counted inside the prompt tokens, as the providers report
them.
"""
import json
import os
import sys
from pathlib import Path

# Cloudflare Workers AI, as its pricing page had them on 2026-11-19.
PRICES = {
    "@cf/zai-org/glm-5.3": (1.4, 0.26, 4.4),
}


def of_tokens(prompt: int, cached: int, completion: int, price: tuple) -> float:
    fresh, read, out = price
    return ((prompt - cached) * fresh + cached * read + completion * out) / 1_000_000


# An agent that does not record how much of its prompt was read from cache would be
# charged here as if none of it was, three to four times what Workers AI bills: it caches
# whatever the agent does. The published Meta-Harness agent is one (it reads the count from
# a field only Anthropic sends). For such a record, and only where a step has no
# cached_tokens at all, this share of the prompt is taken as cached. terminus-2's records on
# the same model and provider show 0.93 to 0.96; a run that sets it says so in its
# conditions, and its cost is an estimate.
def assumed_cached() -> float:
    try:
        return min(max(float(os.environ.get("ASSUMED_CACHED", "0")), 0.0), 1.0)
    except ValueError:
        return 0.0


def of_trajectory(path: Path, price: tuple) -> float:
    try:
        steps = json.loads(path.read_text()).get("steps") or []
    except (OSError, ValueError):
        return 0.0
    share = assumed_cached()
    total = 0.0
    for s in steps:
        m = s.get("metrics") or {}
        prompt = m.get("prompt_tokens") or 0
        cached = m["cached_tokens"] or 0 if "cached_tokens" in m else int(prompt * share)
        total += of_tokens(prompt, cached, m.get("completion_tokens") or 0, price)
    return total


def of_trial(trial: Path, price: tuple) -> float:
    said = trial / "agent" / "cost.txt"
    try:
        return float(said.read_text().strip().lstrip("$"))
    except (OSError, ValueError):
        pass
    # A trajectory continued after a summary is written as trajectory.cont-N.json beside
    # the first; each holds its own steps.
    return sum(of_trajectory(p, price) for p in sorted((trial / "agent").glob("trajectory*.json")))


def trial_dirs(run: Path) -> list:
    return sorted(p.parent for p in run.rglob("agent") if p.is_dir() and (p.parent / "config.json").exists())


def of_run(run: Path, price: tuple) -> float:
    return sum(of_trial(t, price) for t in trial_dirs(run))


def main(argv: list) -> int:
    if len(argv) < 2:
        print(__doc__, file=sys.stderr)
        return 2
    model = argv[2] if len(argv) > 2 else "@cf/zai-org/glm-5.3"
    if model not in PRICES:
        print(f"no price for {model}: add it to bench/tb2/cost.py with where it was read", file=sys.stderr)
        return 2
    print(f"{of_run(Path(argv[1]), PRICES[model]):.4f}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
