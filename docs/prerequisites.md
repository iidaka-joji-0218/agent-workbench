# 前提ツールの入れ方

Windows / macOS / Linux。バイナリは Git に含めない。

通常は `./setup.sh` が環境選択のあと、未導入分をユーザー領域へ入れる。[README](../README.md) の構築手順を先に見る。ここは **手動で入れるとき・setup が失敗したとき**。

WezTerm の既定シェルはどの OS でも **bash -i**。macOS のログインシェルが zsh でも、この環境では bash を使う。WSL 選択時は Windows の WezTerm が `wsl.exe -e bash -i` を起動する。

## 早見

| ツール | 必須 | 自動配置（setup / bootstrap） |
| --- | --- | --- |
| Git + bash | 必須（clone 前） | 入れない。Git for Windows / Xcode CLT / 配布パッケージ |
| WezTerm | 必須 | Windows: `~/Apps/WezTerm` ／ macOS: `~/Applications/WezTerm.app` ／ Linux: `~/.local/bin/wezterm` |
| Node.js LTS | 必須 | `~/.local/opt/node` |
| AI agent CLI | 必須（1つ） | setup で選択。Cursor / Claude / Gemini / Copilot / Codex |
| Meslo Nerd Font | 必須（見た目） | `oh-my-posh font install meslo` |
| Neovim | 推奨 | `~/.local/opt/nvim` または `nvim-win64` |
| lazygit | 推奨 | `~/.local/bin/lazygit` |
| Oh My Posh | 推奨 | Windows: `~/Apps/oh-my-posh/oh-my-posh.exe` ／ 他: `~/.local/bin` |

テーマは `install.sh` が `~/.config/oh-my-posh/light.omp.json` へ置く。

---

## Git + bash

**Windows**

1. https://git-scm.com/download/win
2. または `winget install -e --id Git.Git --accept-package-agreements --accept-source-agreements`
3. Git Bash で `git --version`

**macOS**

```bash
xcode-select --install   # git が無いとき
# Homebrew があるとき
brew install git bash
```

**Linux（Debian / Ubuntu 例）**

```bash
sudo apt update
sudo apt install -y git bash curl unzip tar
```

---

## WezTerm

setup は GitHub の zip / AppImage をユーザー領域へ入れる。失敗したら https://wezterm.org/

- Windows: `~/Apps/WezTerm/wezterm-gui.exe`
- macOS: `~/Applications/WezTerm.app`
- Linux: `~/.local/bin/wezterm`

確認: `wezterm --version`

---

## Node.js（LTS）

ペインタイトル監視が `node` を使う。setup は Node 22 LTS を `~/.local/opt/node` へ入れる。

手動: https://nodejs.org/ （LTS）

確認: `node -v`

---

## AI agent CLI

`./setup.sh` で 1 つ選ぶ。あとから `agent-use claude` など。WezTerm は常に `agent` を起動する。

| provider | コマンド | 入れ方 |
| --- | --- | --- |
| cursor | `agent` / `cursor-agent` | Windows: `irm 'https://cursor.com/install?win32=true' \| iex` ／ 他: `curl https://cursor.com/install -fsS \| bash` |
| claude | `claude` | Windows: `irm https://claude.ai/install.ps1 \| iex` ／ 他: `curl -fsSL https://claude.ai/install.sh \| bash` |
| gemini | `gemini` | `npm install -g @google/gemini-cli` |
| copilot | `copilot` | `npm install -g @github/copilot` |
| codex | `codex` | `npm install -g @openai/codex` |

Cursor 配置: Windows `%LOCALAPPDATA%\cursor-agent\agent.cmd`、他 `~/.local/bin/agent`

初回は各 CLI のログイン（Cursor なら `agent login`）。

---

## Oh My Posh

**Windows（ポータブル。WindowsApps は使わない）**

```bash
mkdir -p "$HOME/Apps/oh-my-posh"
curl -fL -o "$HOME/Apps/oh-my-posh/oh-my-posh.exe" \
  https://github.com/JanDeDobbeleer/oh-my-posh/releases/latest/download/posh-windows-amd64.exe
```

**macOS / Linux**

GitHub の `posh-darwin-*` / `posh-linux-*` を `~/.local/bin/oh-my-posh` へ。

---

## Meslo Nerd Font

```bash
oh-my-posh font install meslo
# Linux は続けて
fc-cache -f "$HOME/.local/share/fonts"
```

手動: https://github.com/ryanoasis/nerd-fonts/releases/latest/download/Meslo.zip を展開し、`MesloLGLDZNerdFontMono-*.ttf` を OS のフォントに入れる。

フォールバック: MesloLGLDZ Nerd Font Mono → MesloLGM / JetBrainsMono Nerd → Menlo / Consolas → Yu Gothic UI / Hiragino Sans / Noto Sans CJK JP。

---

## Neovim

**Windows**

```bash
mkdir -p "$HOME/.local/opt"
curl -fL -o /tmp/nvim-win64.zip \
  https://github.com/neovim/neovim/releases/latest/download/nvim-win64.zip
tar -xf /tmp/nvim-win64.zip -C "$HOME/.local/opt"
```

設定は `install.sh` が `%LOCALAPPDATA%\nvim\` へ。

**macOS / Linux:** GitHub の tar を `~/.local/opt` へ展開し、`~/.local/opt/nvim` にシンボリックリンク。設定は `~/.config/nvim/`。

lazygit の editor は `bashrc` が `nvim` / `nvim.exe` を `EDITOR` にする。

---

## lazygit

GitHub の最新リリースを `~/.local/bin/lazygit` へ。

---

## 構築後の確認

WezTerm を再起動した新しいタブで:

```bash
command -v wezterm || ls "$HOME/Apps/WezTerm/wezterm.exe"
command -v node && command -v lazygit
command -v nvim && echo nvim_ok
command -v oh-my-posh || test -x "$HOME/Apps/oh-my-posh/oh-my-posh.exe"
command -v agent || command -v claude || command -v gemini
```

`install.sh` の末尾でも近いチェックを出す。
