# bench

Scripts that put comide to work unattended and write down what came of it. None of them is
needed to use comide. Those that call a model cost money, and say so below; each of those
takes a limit in dollars and a credentials file of its own (`KEYS`, a file of `NAME=VALUE`
lines holding `CLOUDFLARE_ACCOUNT_ID` and `CLOUDFLARE_API_TOKEN`). Keep that file apart from
the one you use comide with: in some of these runs the key sits unconfined beside the model's
commands.

Records of runs are written outside the repository (`~/.cache/comide/bench/runs` unless
told otherwise). They hold the whole of what was sent to the model and what it answered.

## tb2: Terminal-Bench 2, through Harbor

| script | what it does | calls a model |
|---|---|---|
| `tb2/run.sh` | every task, comide from the bundle, confined or not | yes |
| `tb2/measure.sh` | one agent over a fixed set of tasks, stopped at `LIMIT` dollars; rows and conditions written down | yes |
| `tb2/series.sh` | several such runs inside one budget | yes |
| `tb2/summary.py` | runs side by side: the mean and the band between them | no |
| `tb2/buildable.sh` | whether each task's container builds and starts here | no |
| `tb2/select.py` | the held-out tasks, chosen by name alone | no |

`measure.sh` runs one of: `terminus-2` (Harbor's own agent, the baseline), `comide` (the
bundle, `comide -p TASK --yes`), `errand` (`comide errand TASK`, the binary alone, built by
`tb2/linux/build.sh`), `meta-harness` (the agent published with that paper).

Two sets of ten tasks. `tasks-dev.txt`: their runs may be read and changes made because of
them; their score decides nothing. `tasks-held-out.txt`: nothing of them is read but their
names and a measurement's rows. One run of ten tasks varies by about three tasks from one
time to the next, with nothing changed: a difference smaller than that is not a difference.

`ci/bench-check.sh` checks all of it with a stand-in for Harbor: no model, no container.

## ipi: instructions hidden in what the agent reads

`ipi/ipi.py` puts the samples of CodeIPI (UK AISI Inspect Evals, `ipi_coding_agent`, MIT) to
comide inside the lab (`nautra/lab.sh`), and reads from each run whether the hidden
instruction was followed and whether anything left the enclosure. It calls a model. The
samples are read from a checkout of that dataset (`IPI_DATASET`); none of their text is in
this repository. Samples that carry an injection are run in the lab only.

`ipi/replay.py` asks of runs already made what comide's gate on copied command lines would
have held. It calls nothing.

## convo: a guard for the conversation's prompt

`convo/convo.py` puts twelve small tasks to `comide run`, one request each, and counts
replies, replies that could not be read, and cost. It calls a model. Its tasks carry no
injection (CodeIPI's ten without one, and two that make the model write a longer file). All
twelve are usually passed, so it can show that a change made things worse, not that it made
them better.
