<h1 align="center">shemide</h1>
<p align="center"><strong>The word that moves the golem.</strong></p>
<p align="center">A coding agent in the terminal, in the line of Claude Code, Codex and Aider,<br>that hands its code changes to golemide.</p>
<p align="center"><a href="README_ja.md">日本語</a></p>

```sh
shemide                               # a conversation in this directory; /exit to leave
shemide run "fix the flaky tests"     # one request, answered, then exit
shemide --yes --root ../project       # run shell and verify commands without asking
```

In the story, a golem moves while a *shem*, a holy name written on paper, is in its
mouth. [golemide](https://github.com/O6lvl4/golemide) is the golem that does the work:
it reads the code, edits it and runs the tests until they pass. shemide (*SHEM-ide*)
is the word that moves it.

## Setup

1. **Almide** develop at `ce7cd7553` or later, until 0.63 is released.
2. **golemide 0.2.0 or later** on `PATH`. shemide's edits and `solve` go through it,
   and it says at startup when golemide is missing or too old.
   ```sh
   git clone https://github.com/O6lvl4/golemide && cd golemide
   almide build src/main.almd -o golemide && ln -s "$PWD/golemide" ~/.local/bin/golemide
   ```
3. **shemide**
   ```sh
   git clone https://github.com/O6lvl4/shemide && cd shemide
   almide build src/main.almd -o shemide
   ln -s "$PWD/bin/shemide" ~/.local/bin/shemide
   ```
4. **Credentials**, shared with golemide: Cloudflare Workers AI's
   `CLOUDFLARE_ACCOUNT_ID` and `CLOUDFLARE_API_TOKEN` in `~/.config/golemide/.env`
   (or the project's `.env`, or the environment).

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
`$SHEMIDE_SEARXNG_URL` points at another instance.

## License

MIT or Apache-2.0, at your option.
