<p align="center">
  <img src="docs/images/banner.jpg" alt="comide — A coding agent in the terminal. 琥珀色に光る継ぎ目を持つ黒い石のローポリの職人。道具ベルトを締め、肩に小さなゴーレムを乗せ、光るペンで宙に書いている">
</p>

<p align="center">Claude Code、Codex、Aider と同じ種類の、ターミナルのコーディングエージェント。<br>コードの変更は golemide に任せます。</p>
<p align="center"><a href="README.md">English</a></p>

```sh
comide                                # このディレクトリで会話する。/exit で終わる
comide run "fix the flaky tests"      # 頼みごとを 1 回だけ実行して終わる
comide --yes --root ../project        # シェルと検証コマンドを確認なしで実行する
```

何を見て何を変えるかは comide が決めます。コードの変更は
[golemide](https://github.com/O6lvl4/golemide) に渡し、golemide が編集・テスト・やり直しを
テストが通るまで繰り返します。

## セットアップ

1. **Almide**：0.63 が出るまでは develop の `ce7cd7553` 以降。
2. **golemide 0.2.0 以降**を `PATH` に置く。comide の編集と `solve` は golemide を通ります。
   見つからないときや古いときは、起動時にそう表示します。
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
4. **認証情報**は golemide と共通です。Cloudflare Workers AI の `CLOUDFLARE_ACCOUNT_ID` と
   `CLOUDFLARE_API_TOKEN` を `~/.config/golemide/.env` に書きます（プロジェクトの `.env` や環境変数でも可）。

任意：読む・地図を作る・出力を要約するために [hew](https://github.com/O6lvl4/hew)、
[gramide](https://github.com/O6lvl4/gramide)、[ctxgate](https://github.com/O6lvl4/ctxgate) を `PATH` に。
`web_search` には手元の [SearXNG](#web-検索) が要ります。

## ツール

モデルが使うツールは、どれも既にあるプログラムです。

| ツール | プログラム |
|---|---|
| `read`, `outline`, `search`, `tree` | hew：関数名・範囲・一致で読む。ファイル全体は読まない |
| `map` | gramide：頼みごとに関係するファイルを順位付けする |
| `edit`, `write` | `golemide edit`：うろ覚えの引用にも合わせ、書く前に構文を確かめる |
| `solve` | `golemide solve --json`：編集・検証・やり直しを、コマンドが通るまで |
| `shell` | ctxgate：長い出力を要約し、終了ステータスは残す |
| `web_search`, `web_fetch` | SearXNG と Almide の `http`。リダイレクトのたびに行き先を確かめる |

シェルコマンドと、`solve` が実行する検証コマンドは、実行前に確認します。
Web ページは公開されているものだけを読みます。

## キー

Enter で送信 · Alt+Enter で改行 · ↑↓ で履歴 · Tab で `/コマンド` を補完 ·
Esc で中断 · Ctrl+D で終了。ほかは `/help` で出ます。

## Web 検索

`web_search` には、JSON で答える SearXNG を手元だけで動かしておきます。

```sh
mkdir -p ~/.config/searxng
docker run -d --name searxng --restart unless-stopped \
  -p 127.0.0.1:8888:8080 -v ~/.config/searxng:/etc/searxng searxng/searxng
```

`~/.config/searxng/settings.yml` の `server:` に `limiter: false`、`search:` に
`formats: [html, json]` を書いて `docker restart searxng`。別のインスタンスを使うなら
`$COMIDE_SEARXNG_URL` で指定します。

## ライセンス

MIT または Apache-2.0 のどちらかを選べます。
