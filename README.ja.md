<p align="center">
  <img src="docs/images/banner.jpg" alt="comide — A coding agent in the terminal. 琥珀色に光る継ぎ目を持つ黒い石のローポリの職人。道具ベルトを締め、肩に小さなゴーレムを乗せ、光るペンで宙に書いている">
</p>

<p align="center">Claude Code、Codex、Aider と同じ種類の、ターミナルのコーディングエージェント。<br>コードの変更は golemide に任せます。</p>
<p align="center">
  <a href="README.md"><img alt="English" src="https://img.shields.io/badge/English-d0d7de?style=flat-square"></a>
  <a href="README.ja.md"><img alt="日本語" src="https://img.shields.io/badge/%E6%97%A5%E6%9C%AC%E8%AA%9E-24292f?style=flat-square"></a>
</p>

```sh
comide                                # このディレクトリで会話する。/exit で終わる
comide run "fix the flaky tests"      # 頼みごとを 1 回だけ実行して終わる
comide --yes --root ../project        # シェルと検証コマンドを確認なしで実行する
comide errand "make the build pass"   # 1 つのタスクを、誰も見ていない端末で最後までやる
```

何を見て何を変えるかは comide が決めます。コードの変更は
[golemide](https://github.com/O6lvl4/golemide) に渡し、golemide が編集・テスト・やり直しを
テストが通るまで繰り返します。

## セットアップ

1. **Almide**：0.70.0 以降。
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
   golemide の `solve` はこれで動きます。

会話のモデルは `--model プロバイダ:モデル`（または `/model`）で選びます。

| `--model` | 動く先 |
|---|---|
| `cf:glm-5.3`（既定） | Cloudflare Workers AI |
| `openai:gpt-5`、`openrouter:…`、`deepseek:…`、`zai:…`、`groq:…`、`ollama:…`、`lmstudio:…` | その OpenAI 互換サービス。`OPENAI_API_KEY` などで認証 |
| `anthropic:claude-sonnet-4-5`、`gemini:gemini-2.5-pro` | Anthropic の Messages API か Gemini。`ANTHROPIC_API_KEY`、または `GEMINI_API_KEY` / `GOOGLE_API_KEY` で認証 |
| `NAME:MODEL` | それ以外の OpenAI 互換サービス。`NAME_BASE_URL` と `NAME_API_KEY` で指定 |
| `claude`、`claude:opus` | Claude Code の `claude -p`（Claude のログインで動く）。ツールは comide が実行 |

`solve` は golemide 自身のモデルで動きます。`COMIDE_SOLVE_MODEL`（と `COMIDE_SOLVE_STRONG_MODEL`）に
同じ形で書けば、別のモデルにできます。`claude` のときは Claude Code のツール・設定・フック・MCP を
切って動かしますが、全体設定の `CLAUDE.md` と自動メモリは読まれます。

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

## 指示ファイル

comide は最初の頼みごとの前に、プロジェクトがエージェント向けに書いたものを読み、
どのファイルを読んだかを表示します。

| ファイル | 誰のものか |
|---|---|
| `~/.config/comide/AGENTS.md` | あなたのもの。どのプロジェクトでも読む |
| プロジェクトの `AGENTS.md`、`CLAUDE.md`、`.claude/CLAUDE.md` | プロジェクトのもの |
| `$COMIDE_INSTRUCTIONS` のファイル（`:` 区切り） | comide を起動する側が名指ししたもの |

`@AGENTS.md` とだけ書いた `CLAUDE.md` や、同じ本文のファイルは 1 回だけ読みます。
24,000 文字を超えるファイルは切り詰め、切り詰めたことを書き添えます。プロジェクトの
ファイルが、プロジェクトの外を指すリンクだった場合は読みません。プロジェクトのスキルも同じです。

ここまでは会話するモデル向けです。編集するモデルは `solve` の先にいる別のモデルなので、
別に伝えます。`$COMIDE_SOLVE_INSTRUCTIONS` のファイルは、タスクのたびに golemide に渡ります。
コードの書き方についてプロジェクトが決めていることは、そちらに書きます。

## スキル

スキルは `SKILL.md` を置いたディレクトリです。ある種類の作業の手順を書いたもので、
冒頭に `name` と `description` を持ちます。comide は最初に名前と説明だけを並べ、
本文は、モデルが `skill` ツールで開いたときに読みます。

探す場所は、プロジェクトの `.claude/skills` と `.agents/skills`、次に
`~/.config/comide/skills`、`~/.claude/skills`、`$COMIDE_SKILLS` のディレクトリ（`:` 区切り）です。
同じ名前のスキルは、先に見つかったものを使います。

## 長い会話

会話が長くなると、古いツール出力は冒頭の数行に切り詰めます。それでも足りず、
1 回の呼び出しの入力が `$COMIDE_COMPACT_TOKENS`（既定 120,000）を超えると、会話を
引き継ぎメモに置き換えます。メモには、頼まれたこと、決まったこと、分かったこと、
変更したこと、途中だったことを書きます。作業中の頼みごとは一字一句そのまま戻し、
作業を続けます。`/compact` で手動でも実行できます。

メモを書くのは `$COMIDE_SUMMARY_MODEL` です。未設定なら会話のモデルが書きます。
メモより前のツール出力は残らないので、モデルには読み直すよう伝えます。
置き換える前の会話は、その実行の一時ディレクトリのファイルに書き出し、場所を表示します。

## 会話に戻る

会話は頼みごとのたびに `~/.comide/sessions/` へ、プロジェクトのパスごとに保存します。
`comide --continue` はそのプロジェクトの直近の会話を、`comide --resume ID` は指定した
会話を続けます。どちらも `run` と一緒に使えます。

戻るのは、メッセージ、それまでの費用、作業を確かめるコマンドです。システムプロンプトは
書き直すので、その後に変わった指示ファイルやスキルは、いまの内容で読みます。
コマンドを実行する許可は保存せず、あらためて確認します。

「直近」は、最後に開始した会話です。保存するのは会話の全体で、ツールの出力のすべてと、
あなた自身の指示ファイルやメモを含むシステムプロンプトが入ります。ファイルはあなただけが
読める権限にしてあり、プロジェクトの外にあります。

## メモリ

プロジェクトごとに、セッションをまたいで残るメモのファイルが 1 つあります。
`~/.comide/memory/<プロジェクトのパス>/MEMORY.md` で、メモ 1 件が日付つきの 1 行です。
そのプロジェクトの会話の最初に毎回読み、モデルは `remember` ツールで書き足します。
書くのは、あなたが直したこと、伝えた好み、探すのに手間がかかった場所などです。
`/memory` でファイルの場所が出ます。メモを直したり消したりするには、ファイルを編集します。
comide が覚えていることは、このファイルがすべてです。

## 目標

頼みごとは、答えが返れば終わります。目標は終わりません。`/goal TEXT`（または
`--goal TEXT`）でセッションの目的を伝えると、目標がある間は、モデルが止まるたびに
comide が「達成したか」を尋ねます。まだなら、モデルは作業を続けます。終わるのは、
モデルが根拠つきで `GOAL MET` と答えたとき、あなたの判断が要ると示したとき、
1 つの頼みごとの中で 25 回尋ねたときです。

目標はあなたの言葉のまま持ちます。会話と一緒に保存するので `--continue` で戻り、
長い会話が引き継ぎメモに置き換わるときも一字一句そのまま戻します。
`/goal` で表示、`/goal clear` で取り消しです。

達成したというのはモデルの申告です。根拠はあなたが読んで確かめるもので、証明ではありません。

## 助手

ある処理がどこにあるかを探すと、20 回読むこともあり、その 20 回分がすべて会話に
残ります。`explore` ツールは、そういう問いを助手に渡します。助手は `--read-only` で
起動した別の comide で、自分の会話の中で調べます。戻ってくるのは答えだけです。

助手のモデルは `$COMIDE_EXPLORE_MODEL` で、未設定なら会話のモデルです。速くて安い
モデルで十分にこなせます。`PATH` 上の `comide`（`$COMIDE_BIN` で別のものを指定可）から
起動し、同じ runner を通り、助手がさらに助手を起動することはできません。
助手が使った費用は、セッションの費用に含めます。

## プランモード

`/plan`（または `--plan`）にすると、comide はプロジェクトを読んで計画で答えます。
何を、どのファイルで、どの順に変えるか、各手順をどう確かめるかです。オンの間は、
ファイルを変えるツールとコマンドを実行するツールは動きません。`/go` で計画を承認して
実行し、`/plan off` でやめます。`comide run "..." --plan` の後は、
`comide run "go ahead" --continue` で計画を実行します。

`--read-only` は、計画なしで同じようにツールを止めます。読むだけの実行です。

## おつかい

`comide errand TASK` は、誰も見ていないところで 1 つのタスクを最後までやります。会話とは
別のループです。モデルにツールは送らず、モデルは毎回、1 つの JSON オブジェクト（見えて
いること、計画、実行するコマンド、終わったかどうか）で答えます。端末は 1 つで、続きます。
移動したディレクトリも `export` した変数も、次のコマンドに残ります。待ち時間を超えた
コマンドは動き続け、あとで待ち直す・続きを読む・止めることができます。モデルが 2 回
「終わった」と言ったら終わりです。

モデルが書いたコマンドは、確認なしですべて実行します。[設定](#設定)は効きます。`deny` の
ルールに当たるコマンドは実行しません。`ask` のルールに当たるコマンドも、聞く相手が
いないので実行しません。`shell` のフックは、コマンドの前後に動きます。おつかいは、端末が
害を及ぼせない場所で始めてください。コンテナの中か、
[nautra](https://github.com/Aid-On/nautra) の上（`nautra/run.sh TASK --root DIR`）です。
nautra の上では、エージェントは鍵を持たない WebAssembly コンポーネントで（鍵はモデルの
ホストへのリクエストに nautra が付けます）、端末は渡されたディレクトリに閉じ込められた
ネイティブのツールです。`ci/check.sh` が、その中から外に出ようと試します。

| | |
|---|---|
| `--model M` | 会話と同じ（既定 `cf:glm-5.3`） |
| `--max-steps N` | モデルを呼ぶ回数の上限（既定 200） |
| `COMIDE_LOG_DIR` | 進みながら記録を書く場所：`trajectory.json`、`cost.txt`、`transcript.json` |
| `COMIDE_REASONING_BACK=0` | モデルの推論をモデルに送り返さない（安くなる。既定は送り返す） |
| `COMIDE_CHECK=1` | 終わったと言われたら、タスクだけを見せた新しい会話でもう一度確かめる |

このループは先に comide の外で書いて測りました。同じモデルで Terminal-Bench 2 のタスクを
解かせると、Harbor の terminus-2 とほぼ同じ数が通ります。

0.7 から、会話、`comide run`、`-p` も同じ芯で動きます。モデルは毎回書いて答え、端末は
頼みごとをまたいで続きます。[ツール](#ツール)は同じもので、ツール呼び出しとして送る
代わりに、モデルが端末のコマンドと並べて `{"tool": "edit", "args": {...}}` と書きます。
`edit`・`write`・`solve` は今までどおり golemide を通り、権限、フック、プランモード、目標、
スキル、メモリ、MCP、助手、長い会話を置き換えるメモも今までどおりです。おつかいとの違いは、
人がいることです。ルールに無い端末のコマンドは、先にあなたに聞きます。`--loop tools`
（または `COMIDE_LOOP=tools`）で、前のループ（ツールをツール呼び出しとして送り、シェルは
コマンドごとに新しい）に戻せます。

ファイルの中身は JSON の文字列に入れると壊れやすいので、モデルは長い文章を JSON の後ろに、
`<<<BODY NAME` の行と `>>>BODY NAME` の行で挟んでそのまま書き、使う場所で名指しできます
（`"content": "@body:NAME"`）。`web_search` は、始めに検索エンジンが答えたときだけ見せます。

## 設定

確認なしで実行してよいものと、実行してはいけないものを、JSON のルールで書きます。

```json
{ "permissions": {
    "allow": ["shell(git status*)", "shell(npm test*)"],
    "ask":   ["shell(git push*)"],
    "deny":  ["read(.env*)", "shell(rm -rf*)"] } }
```

ルールは、ツール名と、括弧の中の「何についての呼び出しか」です。`shell`（と `solve` の
検証コマンド）ならコマンド、`read`・`edit`・`write` ならパス、`web_fetch` なら
`domain:ホスト名` です。`*` は任意の文字列に一致します。`deny` は `ask` より強く、
`ask` は `allow` より強く、どのルールにも当たらない呼び出しは従来どおりに扱います。

| ファイル | 誰のものか |
|---|---|
| `~/.config/comide/settings.json` | あなたのもの。どのプロジェクトでも使う |
| `$COMIDE_SETTINGS` のファイル（`:` 区切り） | comide を起動する側が名指ししたもの |
| プロジェクトの `.comide/settings.json` | プロジェクトのもの |

プロジェクトのファイルは、`ask` と `deny` だけをそのまま使います。この 2 つは comide を
慎重にする方向にしか働かないからです。`allow` のルールとフックは、`--trust-project` を
付けて一度起動した後、ファイルがそのときの内容のままである間だけ使います。

`read` のルールは、読むツールすべて（`read`、`outline`、`search`、`tree`）に効きます。
`edit` のルールは、ファイルを書く 2 つのツールの両方に効きます。パスは書き方ではなく
指している場所で比べます。`a/../.env`、`././.env`、`.ENV` は、`deny` と `ask` にとっては
どれも `.env` です。`edit` と `write` は、リストに何が書いてあっても `.comide/` の下を
拒否します。設定を変えるのはあなたで、モデルではありません。

ルールは目安で、壁ではありません。シェルコマンドでは、`allow` は連結やリダイレクトを
含むコマンドには効きません。`deny` と `ask` は、連結の各部分に対して、括弧、先頭の
`NAME=value`、プログラムのディレクトリを外した形でも照合します。それでも `bash -c`、
エイリアス、スクリプトの中や、別のフラグで同じことをするコマンドは見抜けません。
また、あるファイルへのルールは、そのファイルのあるディレクトリの検索、そこを指すリンク、
それを読むシェルコマンド、golemide が編集する `solve` を止めません。コマンドを閉じ込め、
ファイルをモデルから守るのは runner（`--runner`）の役目です。

### フック

同じファイルに、決まった場面で実行するあなた自身のコマンドを書けます。名前と形は
Claude Code のものなので、そちら向けに書いたフックはそのまま読めます。

```json
{ "hooks": {
    "PreToolUse": [ { "matcher": "shell|edit",
                      "hooks": [ { "type": "command", "command": "./check.sh" } ] } ] } }
```

| イベント | いつ | 終了コード 2 の意味 |
|---|---|---|
| `SessionStart` | 最初の頼みごとの前 | （なし。出力はモデルに伝わる） |
| `UserPromptSubmit` | 頼みごとを送る前 | 送らない |
| `PreToolUse` | ツールを実行する前 | 実行しない |
| `PostToolUse` | ツールを実行した後 | 指摘を結果の下に付ける |
| `Stop` | モデルが答えて止まろうとするとき | 作業は終わっていないので、続ける |

フックは標準入力で JSON を 1 つ受け取ります（`hook_event_name`、`session_id`、`cwd`、
該当するときは `tool_name`、`tool_input`、`tool_response`、`prompt`）。終了コード 0 は続行、
2 は停止で、標準エラーの内容が理由としてモデルに伝わります。それ以外はフック自身の
失敗で、あなたに表示してセッションは続きます。`matcher` は comide のツール名を `|` で
区切ったものです。

フックはあなたの権限で、閉じ込めずに実行します。プロジェクトのフックは、
プロジェクトを信頼する（`--trust-project`）まで使いません。

### MCP サーバー

ほかのプログラムが持つツールは、同じファイルに、どの MCP クライアントでも使う形で書きます。

```json
{ "mcpServers": {
    "files": { "command": "npx", "args": ["-y", "@modelcontextprotocol/server-filesystem", "."] },
    "docs":  { "type": "http", "url": "https://example.com/mcp",
               "headers": { "Authorization": "Bearer ..." } } } }
```

モデルには、サーバーのツールそのものは渡しません。渡すのはサーバーの名前と、そこへ
手を伸ばす 3 つのツールです。`mcp_tools` はサーバーが提供するものの一覧、
`mcp_describe` はツール 1 つの引数、`mcp_call` は呼び出しです。ツールを 50 個持つ
サーバーでも、どれかを見るまでは 1 行分しかかかりません。

どれも 1 回の短いやり取りです。サーバーを起動し（またはアドレスを呼び）、挨拶して、
尋ねて、終わります。呼び出しの間は何も動かし続けないので、前の呼び出しを自分の
メモリに覚えていないと動かないサーバーには向きません。

`mcp_call` は、ルールで許可しない限り（`mcp_call(files/read_file)`、
`mcp_call(files/*)`）実行前に確認し、プランモードでは実行しません。サーバーは
あなたの権限で、閉じ込めずに動きます。プロジェクトのサーバーは、プロジェクトを
信頼するまで使いません。

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
