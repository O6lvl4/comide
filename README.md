<p align="center">
  <img src="docs/images/banner.jpg" alt="comide — A coding agent in the terminal. A small low-poly artisan of black stone with glowing amber seams, a tool belt and a tiny golem on its shoulder, writing in the air with a glowing stylus.">
</p>

<p align="center">A coding agent in the terminal, in the line of Claude Code, Codex and Aider,<br>that hands its code changes to golemide.</p>
<p align="center"><a href="README_ja.md">日本語</a></p>

```sh
comide                                # a conversation in this directory; /exit to leave
comide run "fix the flaky tests"      # one request, answered, then exit
comide --yes --root ../project        # run shell and verify commands without asking
```

comide decides what to look at and what to change. Code changes go to
[golemide](https://github.com/O6lvl4/golemide), which edits, runs the tests and retries
until they pass.

## Setup

1. **Almide** develop at `ce7cd7553` or later, until 0.63 is released.
2. **golemide 0.2.0 or later** on `PATH`. comide's edits and `solve` go through it,
   and it says at startup when golemide is missing or too old.
   ```sh
   git clone https://github.com/O6lvl4/golemide && cd golemide
   almide build src/main.almd -o golemide && ln -s "$PWD/golemide" ~/.local/bin/golemide
   ```
3. **comide**
   ```sh
   git clone https://github.com/O6lvl4/comide && cd comide
   almide build src/main.almd -o comide
   ln -s "$PWD/bin/comide" ~/.local/bin/comide
   ```
4. **Credentials**, shared with golemide: Cloudflare Workers AI's
   `CLOUDFLARE_ACCOUNT_ID` and `CLOUDFLARE_API_TOKEN` in `~/.config/golemide/.env`
   (or the project's `.env`, or the environment). golemide's `solve` runs on them.

The conversation's model is `--model PROVIDER:MODEL` (or `/model`):

| `--model` | runs on |
|---|---|
| `cf:glm-5.3` (default) | Cloudflare Workers AI |
| `openai:gpt-5`, `openrouter:…`, `deepseek:…`, `zai:…`, `groq:…`, `ollama:…`, `lmstudio:…` | that OpenAI-compatible service, with `OPENAI_API_KEY` and so on |
| `NAME:MODEL` | any other OpenAI-compatible service: `NAME_BASE_URL` and `NAME_API_KEY` |
| `claude`, `claude:opus` | Claude Code's `claude -p` on your Claude login; comide runs the tools |

`solve` runs on golemide's own models unless `COMIDE_SOLVE_MODEL` (and
`COMIDE_SOLVE_STRONG_MODEL`) name others, in the same form. With `claude`, comide turns
off Claude Code's tools, settings, hooks and MCP servers; your global `CLAUDE.md` and
memory are still read.

Optional: [hew](https://github.com/O6lvl4/hew), [gramide](https://github.com/O6lvl4/gramide)
and [ctxgate](https://github.com/O6lvl4/ctxgate) on `PATH` for reading, mapping and
summarising; a local [SearXNG](#web-search) for `web_search`.

## Tools

The model's tools are programs that already exist:

| Tool | Program |
|---|---|
| `read`, `outline`, `search`, `tree` | hew: a function by name, a range or a match, not whole files |
| `map` | gramide: the project's files ranked against the task |
| `edit`, `write` | `golemide edit`: loose matching for quotes from memory, a syntax check before writing |
| `solve` | `golemide solve --json`: edit, verify, retry until the command passes |
| `shell` | ctxgate: long output summarised, the exit status kept |
| `web_search`, `web_fetch` | SearXNG, and Almide's `http` with every redirect checked |

A shell command, and the verify command `solve` would run, are asked about first.
Pages are read only from the public web.

## Keys

Enter sends · Alt+Enter adds a line · ↑↓ history · Tab completes `/commands` ·
Esc interrupts a turn · Ctrl+D leaves. `/help` lists the rest.

## Web search

`web_search` needs a SearXNG with JSON answers on, bound to this machine:

```sh
mkdir -p ~/.config/searxng
docker run -d --name searxng --restart unless-stopped \
  -p 127.0.0.1:8888:8080 -v ~/.config/searxng:/etc/searxng searxng/searxng
```

In `~/.config/searxng/settings.yml`, set `limiter: false` under `server:` and
`formats: [html, json]` under `search:`, then `docker restart searxng`.
`$COMIDE_SEARXNG_URL` points at another instance.

## License

MIT or Apache-2.0, at your option.
