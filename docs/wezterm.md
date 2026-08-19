# WezTerm 構成（AI 並列エージェント）

Windows / macOS / Linux で、複数の AI agent を並べて同時に走らせる設定。既定シェルは bash。起動コマンドは常に `agent` で、実体は `~/.wezterm-agent.conf`（`agent-use`）で切り替える。

本体は `wezterm/wezterm.lua`（配置先 `~/.wezterm.lua`）。

## カスタマイズ一覧

lua で既定から変えているもの。詳細は各節。

| 領域 | 内容 |
| --- | --- |
| シェル | どの OS も `bash -i`（`-l` なし）。Windows は Git Bash、macOS は Homebrew bash を優先 |
| WSL | `~/.wezterm-wsl` があるときだけ `wsl.exe -e bash -i` |
| 起動 cwd | ホームディレクトリ |
| ランチャー | Windows: Git Bash / pwsh / Windows PowerShell / cmd。他: bash / zsh |
| フォント | MesloLGLDZ Nerd Font Mono を先頭にフォールバック列。サイズ Windows・Linux 10、macOS 12 |
| 色 | Catppuccin Frappe。非アクティブペインを暗くする。タブバー右端の題名色 |
| IME | 有効。未確定文字列は OS 側描画（`System`） |
| 描画 | WebGpu、60fps、アニメ 1fps、点滅なしのブロックカーソル |
| 履歴 | スクロールバック 5000 行 |
| タブバー | タブが1つでも出す。幅上限 40。右端に全ペインの `番号:題名` |
| 起動時 | `gui-startup` で worktree の有無を聞く |
| 貼り付け | `Ctrl+V` も貼り付け。画像なら一時 PNG のパスを貼る |
| レイアウト | lazygit + agent×3（比率 5:3:3:3）、左右2分割、ディレクトリ選択、ブックマーク |
| キー | ペイン分割・移動・サイズ・ズーム・閉じる・スクロール（後述） |

## 全体像

```
  タブバー右端（常時）  1:lazygit | 2:update_schema修正 | 3:フォント導入 | 4:OCI MCP
                       番号:作業内容。いま操作中のペインは黄色＋太字
┌─────────────┬────────────┬────────────┬────────────┐
│             │ agent      │ agent      │ agent      │
│   lazygit   │ プロンプト │ プロンプト │ プロンプト │
│             │ から題名化 │ から題名化 │ から題名化 │
└─────────────┴────────────┴────────────┴────────────┘
  比率 lazygit : agent : agent : agent = 5 : 3 : 3 : 3
```

- **左列**: lazygit。Git の状態をまとめて見る
- **右3列**: それぞれ独立した AI agent。同じフォルダでも会話はペインごとに別
- **作業内容の見え方（タブバー）**: 各 agent に最初に投げた一文を短くして、タブバー右端に `番号:題名` で常時出す。ペインを拡大しなくても、どの列が何のタスクか分かる
- 並びは画面上の配置順（上→下、左→右）。左右は `|`、上下は `/`
- アクティブなペインの題名は黄色＋太字。非アクティブなペイン自体は少し暗くする
- プロンプト行の先頭にも `[題名]` が出る（Oh My Posh の `PANE_TITLE`）
- 起動直後と `/clear` のあとは題名を `未着手` に固定する。最初のプロンプトが入ると差し替わる
- 自動題名が付く前・付け直したいときは `title 作業名`

## AI agent の切替

WezTerm は常に `agent` を打つ。実体だけ変える。

```bash
agent-use cursor     # Cursor CLI（題名を最初のプロンプトから自動）
agent-use claude     # Claude Code
agent-use gemini     # Gemini CLI
agent-use copilot    # GitHub Copilot CLI
agent-use codex      # OpenAI Codex CLI
agent-use custom 'npx my-agent'
```

設定ファイルは `~/.wezterm-agent.conf`。新しいペインから有効。Cursor 以外は起動時にプロバイダ名を題名にし、細かい題名は `title` で付ける。

仕組み（Cursor の監視スクリプトや優先順位）は後述の「ペインタイトル」。

起動時と `Ctrl+Shift+T` では、先に worktree の有無を聞く。

- Yes → ディレクトリを2回選んで 4 分割
- No → ディレクトリを1回選んで bash だけ

## レイアウト生成キー

| キー | 動作 |
| --- | --- |
| `Ctrl+Shift+4` | 今のタブを「lazygit + agent×3」にする |
| `Ctrl+Shift+T` | worktree の有無を聞いて新しいタブを作る |
| `Ctrl+Shift+2` | 現在ペインを左右2分割 |
| `Ctrl+Alt+T` | 質問なしの素のタブ |

JIS では `Shift+4` が `$` になるため、`$` にも同じレイアウトを割り当てている。既定の `Ctrl+Shift+T`（素の SpawnTab）は無効化して置き換えている。新規タブで始める操作は `Ctrl+Shift+T`。

### ディレクトリ選択

1. `[1/2] lazygit` … Git リポジトリの場所
2. `[2/2] agent×3` … エージェントを動かす場所（1回目の選択地点から潜り始める）

InputSelector の fuzzy 検索付き。1階層ずつ潜る。「このフォルダにする」「上へ」と子フォルダのあと、末尾にブックマーク（`~/.wezterm-dirs.txt`、先頭 `-` で区別）。未登録フォルダで確定すると追加するか聞く。Esc / 「追加しない」でも選択は進む。

### 自動起動

`wezterm.lua` の `auto_run = true` のとき:

- 左: `cd '<場所>' && lazygit`
- 右3: `agent`（`~/.wezterm-agent.conf` の provider）

shell 起動直後は最初の1文字が捨てられることがあるため、空改行を送ってから約 300ms 待ってコマンドを打つ。分割後は約 1200ms 待ってから打ち込む。コマンド自動実行を止めたいときは `auto_run = false`（配置だけ）。

4列の幅は単位 `5:3:3:3`（lazygit : agent×3）。cwd はキーを押したペインの現在地を引き継ぐ（`.bashrc` の OSC 7）。取れないときはホーム。

## クリップボード（貼り付け）

既定は `Ctrl+Shift+V` だけが貼り付けで、`Ctrl+V` は端末の quoted-insert（`^V`）のまま。Windows の慣習に合わせて次を全部 `smart_paste` にする。

| キー | 動作 |
| --- | --- |
| `Ctrl+V` | スマート貼り付け |
| `Ctrl+Shift+V` | 同じ |
| `Shift+Insert` | 同じ |

- **テキスト** … 普通にクリップボードから貼る
- **画像** … 一時 PNG を書いて、そのパスを bracketed paste する（Claude Code / agent にスクショを渡す用）
  - Windows: クリップボードのファイル、PNG 生データ、ビットマップ。`Win+Shift+S` は PNG 形式だけで画像判定が false になることがあるので PNG 生データも見る
  - macOS: `osascript` で PNG
  - Linux: Wayland は `wl-paste`、X11 は `xclip`
  - 保存先: Windows は `%TEMP%/wezterm-paste/`、他は `/tmp/wezterm-paste/`
  - ペインが WSL なら `/mnt/c/...`、Git Bash なら `/c/...` に直す。PowerShell / cmd はそのまま Windows パス
  - 成功時はトーストでパスを出す

## 色・見た目

| 項目 | 値 |
| --- | --- |
| カラースキーム | Catppuccin Frappe |
| 非アクティブペイン | 彩度 0.85、明るさ 0.65（今見ている列が分かるように暗くする） |
| タブバー右端・操作中 | `#f9e2af`（黄）＋太字 |
| タブバー右端・非操作 | `#7f849c`（灰） |
| タブバー右端・区切り `\|` `/` | `#585b70` |
| ディレクトリ選択のブックマーク行 | `#a6adc8` |
| カーソル | 点滅なしのブロック（`SteadyBlock`、点滅間隔 0） |
| タブバー | タブが1つでも表示。タブ幅上限 40 |

プロンプト色は Oh My Posh のテーマ（`oh-my-posh/light.omp.json`）側。

## ペインタイトル

```
agent 実行
  └─ .bashrc の __agent_run
       ├─ node wezterm-title-watch.js（chat ID を監視）
       └─ cursor-agent --resume <chatId>

wezterm.lua の update-status
  └─ ~/.cursor/pane-titles/<paneId>.txt をタブバー右端に表示
```

`cursor-agent` CLI は `beforeSubmitPrompt` hook を発火しないため、チャットファイルを監視する。同じディレクトリで複数ペインを開くので、cwd ではなく起動側で決めた chat ID で特定する。

手動: `title fix-sg`

優先順位: pane-titles → user var `PANE_TITLE` → OSC タイトル。題名は文字数 20 で切り詰め（バイト数ではない。日本語を壊さない）。

## タブバー

全ペインを画面配置順（上→下、左→右）に並べて右端に表示。

- 左右並びは `|`、上下並びは `/`
- 色は上の「色・見た目」

## shell 連携

| 機能 | 内容 |
| --- | --- |
| `agent` | `~/.wezterm-agent.conf` の CLI を起動。Cursor のときはタイトル監視 |
| `agent-use` | provider を書き換える |
| `cursor-agent` | Cursor CLI を直接起動（タイトル監視つき） |
| `title` | ペインタイトルを手動設定 |
| OSC 7（`__osc7`） | cd のたびに cwd を WezTerm へ通知。分割時に同じ作業ディレクトリを引き継ぐ |
| oh-my-posh | ポータブル実体 + 軽量テーマ。init をキャッシュ |

## 基本設定

| 項目 | 値 |
| --- | --- |
| デフォルト shell | bash `-i`（Windows は Git Bash、macOS は Homebrew bash があればそれを優先。`-l` なし） |
| WSL 起動 | `~/.wezterm-wsl` があるとき `wsl.exe -e bash -i`（`setup.sh` が置く） |
| 起動ディレクトリ | ホーム |
| ランチャー（Windows） | Git Bash / PowerShell 7 / Windows PowerShell / Command Prompt |
| ランチャー（他） | bash / zsh |
| フォント | MesloLGLDZ → MesloLGM → JetBrainsMono → Menlo / Consolas → 日本語 UI フォント |
| フォントサイズ | Windows・Linux 10、macOS 12 |
| カラースキーム | Catppuccin Frappe |
| レンダラ | WebGpu / max_fps 60 / animation_fps 1 |
| スクロールバック | 5000 行 |
| IME | `use_ime = true` + `ime_preedit_rendering = 'System'`（Builtin だと未確定が右端で切れたり候補位置がずれる） |

## ショートカット

### AI・レイアウト

| ショートカット | 動作 |
| --- | --- |
| `Ctrl+Shift+4`（JIS は `Ctrl+Shift+$` も） | lazygit + agent×3 |
| `Ctrl+Shift+T` | worktree 確認つき新規タブ |
| `Ctrl+Shift+2` | 左右2分割 |
| `Ctrl+Alt+T` | 素のタブ |

### ペイン

| ショートカット | 動作 |
| --- | --- |
| `Shift+Alt+矢印` | その方向にペイン追加（50%） |
| `Shift+Alt+W` | 現在ペインを閉じる（実行中プロセスがあると確認） |
| `Alt+矢印` | 移動 |
| `Ctrl+Alt+矢印` | サイズ調整（3セル） |
| `Ctrl+Shift+Z` | ズーム（`phys:Z`。mapped だと Shift が落ちて発火しない） |
| `Shift+↑` / `Shift+↓` | 3行スクロール |

### 貼り付け

| ショートカット | 動作 |
| --- | --- |
| `Ctrl+V` / `Ctrl+Shift+V` / `Shift+Insert` | スマート貼り付け（画像ならパス） |

覚え方: `Ctrl+Shift+T` で作業場、`Alt+矢印` で移動、`Ctrl+Shift+Z` で拡大、`Shift+Alt+W` で閉じる。
