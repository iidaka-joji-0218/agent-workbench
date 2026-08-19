#!/usr/bin/env bash
# このリポジトリの設定をホームへ配置する（Windows / macOS / Linux）。
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
TS="$(date +%Y%m%d%H%M%S)"
DRY_RUN=0

usage() {
  cat <<'EOF'
Usage: ./install.sh [--dry-run] [--windows-home PATH] [--agent NAME]

  このリポジトリの設定をホームへコピーする。
  通常は ./setup.sh から呼ぶ。ツール本体が無いときは ./bootstrap.sh。

  オプションなしで実行すると、AI agent を番号で選ぶ。
  --windows-home  WSL 利用時、WezTerm 設定だけ Windows のホームへ置く
  --agent         対話を省略して provider を指定（cursor / claude / ...）
EOF
}

WINDOWS_HOME=""
AGENT=""

unix_path() {
  local p="$1"
  if command -v cygpath >/dev/null 2>&1; then
    cygpath -u "$p"
    return
  fi
  p="${p//\\//}"
  if [[ "$p" =~ ^([A-Za-z]):/(.*)$ ]]; then
    echo "/${BASH_REMATCH[1],,}/${BASH_REMATCH[2]}"
  else
    echo "$p"
  fi
}

is_windows() {
  case "$(uname -s)" in
    MINGW* | MSYS* | CYGWIN*) return 0 ;;
    *) return 1 ;;
  esac
}

backup() {
  local dest="$1"
  if [[ -e "$dest" || -L "$dest" ]]; then
    if [[ "$DRY_RUN" -eq 1 ]]; then
      echo "backup: $dest -> ${dest}.bak.${TS}"
      return
    fi
    cp -a "$dest" "${dest}.bak.${TS}"
    echo "backup: $dest -> ${dest}.bak.${TS}"
  fi
}

install_file() {
  local src="$1" dest="$2"
  echo "install: $src -> $dest"
  if [[ "$DRY_RUN" -eq 1 ]]; then
    return
  fi
  mkdir -p "$(dirname "$dest")"
  backup "$dest"
  cp "$src" "$dest"
}

ensure_bash_profile() {
  # macOS の login bash は .bashrc を読まない。WezTerm は -i なので通常不要だが保険。
  [[ "$(uname -s)" != Darwin ]] && return 0
  local profile="$HOME/.bash_profile"
  if [[ -f "$profile" ]] && grep -q 'ai-agent-dotfiles' "$profile" 2>/dev/null; then
    echo "keep: $profile （source bashrc 済み）"
    return
  fi
  echo "install: source ~/.bashrc -> $profile"
  if [[ "$DRY_RUN" -eq 1 ]]; then
    return
  fi
  if [[ -f "$profile" ]]; then
    backup "$profile"
  fi
  {
    [[ -f "$profile" ]] && cat "$profile"
    cat <<'EOF'

# >>> ai-agent-dotfiles >>>
if [ -f "$HOME/.bashrc" ]; then
  . "$HOME/.bashrc"
fi
# <<< ai-agent-dotfiles <<<
EOF
  } >"$profile.dotfiles-new"
  mv "$profile.dotfiles-new" "$profile"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run) DRY_RUN=1 ;;
    --windows-home)
      WINDOWS_HOME="${2:-}"
      shift
      ;;
    --windows-home=*) WINDOWS_HOME="${1#--windows-home=}" ;;
    --agent)
      AGENT="${2:-}"
      shift
      ;;
    --agent=*) AGENT="${1#--agent=}" ;;
    -h | --help)
      usage
      exit 0
      ;;
    *)
      echo "unknown option: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
  shift
done

if [[ -z "$AGENT" ]]; then
  if [[ -t 0 ]]; then
    echo "右ペインで使う AI agent を選んでください（あとから agent-use で変更できます）。"
    echo "  1) cursor    Cursor CLI（cursor-agent）"
    echo "  2) claude    Claude Code"
    echo "  3) gemini    Gemini CLI"
    echo "  4) copilot   GitHub Copilot CLI"
    echo "  5) codex     OpenAI Codex CLI"
    echo
    printf "番号 [1]: "
    read -r agent_answer || true
    [[ -z "$agent_answer" ]] && agent_answer=1
    case "$agent_answer" in
      1 | cursor) AGENT=cursor ;;
      2 | claude) AGENT=claude ;;
      3 | gemini) AGENT=gemini ;;
      4 | copilot) AGENT=copilot ;;
      5 | codex) AGENT=codex ;;
      *)
        echo "不正な選択: $agent_answer" >&2
        exit 1
        ;;
    esac
  fi
fi
if [[ -n "$AGENT" ]]; then
  case "$AGENT" in
    cursor | claude | gemini | copilot | codex) ;;
    *)
      echo "未対応の AI agent: $AGENT" >&2
      exit 1
      ;;
  esac
fi

if [[ -n "$WINDOWS_HOME" ]]; then
  WINDOWS_HOME="$(unix_path "$WINDOWS_HOME")"
fi
WEZTERM_HOME="${WINDOWS_HOME:-$HOME}"

if is_windows; then
  NVIM_DIR="$(unix_path "${LOCALAPPDATA:-$HOME/AppData/Local}")/nvim"
else
  NVIM_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/nvim"
fi

echo "==> WezTerm"
install_file "$ROOT/wezterm/wezterm.lua" "$WEZTERM_HOME/.wezterm.lua"
if [[ ! -f "$WEZTERM_HOME/.wezterm-dirs.txt" ]]; then
  install_file "$ROOT/wezterm/wezterm-dirs.txt.example" "$WEZTERM_HOME/.wezterm-dirs.txt"
else
  echo "keep: $WEZTERM_HOME/.wezterm-dirs.txt （既存のため上書きしない）"
fi
if [[ -n "$WINDOWS_HOME" ]]; then
  echo "  WezTerm 設定先: $WEZTERM_HOME （Windows）"
  if [[ "$DRY_RUN" -eq 0 ]]; then
    printf 'wsl\n' >"$WEZTERM_HOME/.wezterm-wsl"
    echo "install: $WEZTERM_HOME/.wezterm-wsl （default_prog を wsl.exe にする印）"
  fi
fi

echo "==> bashrc"
install_file "$ROOT/bash/bashrc" "$HOME/.bashrc"
ensure_bash_profile

echo "==> Neovim"
install_file "$ROOT/nvim/init.lua" "$NVIM_DIR/init.lua"
install_file "$ROOT/nvim/lazy-lock.json" "$NVIM_DIR/lazy-lock.json"

echo "==> Cursor hook"
install_file "$ROOT/cursor/hooks/wezterm-title-watch.js" "$HOME/.cursor/hooks/wezterm-title-watch.js"

echo "==> Claude hook"
install_file "$ROOT/claude/hooks/update-pane-title.sh" "$HOME/.claude/scripts/update-pane-title.sh"
if [[ "$DRY_RUN" -eq 0 ]]; then
  chmod +x "$HOME/.claude/scripts/update-pane-title.sh"
fi
if [[ "$AGENT" == "claude" ]]; then
  CLAUDE_SETTINGS="$HOME/.claude/settings.json"
  if [[ ! -f "$CLAUDE_SETTINGS" ]]; then
    install_file "$ROOT/claude/settings.hooks.json.example" "$CLAUDE_SETTINGS"
  elif ! command -v jq >/dev/null 2>&1; then
    echo "  --  jq が無いため $CLAUDE_SETTINGS への UserPromptSubmit フック追加をスキップ（手動で hooks.UserPromptSubmit に update-pane-title.sh を登録してください）"
  elif jq -e '.hooks.UserPromptSubmit and (.hooks.UserPromptSubmit | length > 0)' "$CLAUDE_SETTINGS" >/dev/null 2>&1; then
    echo "keep: $CLAUDE_SETTINGS （既存の UserPromptSubmit フックがあるため変更しない）"
  else
    echo "install: $CLAUDE_SETTINGS に WezTerm タイトル用の UserPromptSubmit フックを追加"
    if [[ "$DRY_RUN" -eq 0 ]]; then
      backup "$CLAUDE_SETTINGS"
      MERGED="$(jq '.hooks.UserPromptSubmit = [{"hooks":[{"type":"command","command":"~/.claude/scripts/update-pane-title.sh"}]}]' "$CLAUDE_SETTINGS")"
      printf '%s\n' "$MERGED" >"$CLAUDE_SETTINGS"
    fi
  fi
fi

echo "==> AI agent"
AGENT_CONF="$HOME/.wezterm-agent.conf"
if [[ -n "$AGENT" ]]; then
  echo "install: provider=$AGENT -> $AGENT_CONF"
  if [[ "$DRY_RUN" -eq 0 ]]; then
    backup "$AGENT_CONF"
    {
      echo "# managed-by: ai-agent-dotfiles"
      echo "provider=$AGENT"
    } >"$AGENT_CONF"
  fi
elif [[ ! -f "$AGENT_CONF" ]]; then
  install_file "$ROOT/agent/agent.conf.example" "$AGENT_CONF"
else
  echo "keep: $AGENT_CONF （既存のため上書きしない）"
fi

echo "==> Oh My Posh theme"
install_file "$ROOT/oh-my-posh/light.omp.json" "$HOME/.config/oh-my-posh/light.omp.json"
if is_windows; then
  install_file "$ROOT/oh-my-posh/light.omp.json" "$HOME/Apps/oh-my-posh/light.omp.json"
fi

echo
echo "==> 前提ツール"
check() {
  local name="$1"
  shift
  if command -v "$1" >/dev/null 2>&1; then
    echo "  OK  $name ($1)"
  else
    echo "  --  $name （未検出: $1）"
  fi
}

if command -v wezterm >/dev/null 2>&1 \
  || [[ -x "$HOME/Apps/WezTerm/wezterm.exe" ]] \
  || [[ -x "$HOME/.local/bin/wezterm" ]] \
  || [[ -d "$HOME/Applications/WezTerm.app" ]]; then
  echo "  OK  WezTerm"
else
  echo "  --  WezTerm （未検出）"
fi
check "bash" bash
if command -v node >/dev/null 2>&1 \
  || [[ -x "$HOME/.local/opt/node/node.exe" ]] \
  || [[ -x "$HOME/.local/opt/node/bin/node" ]]; then
  echo "  OK  Node.js"
else
  echo "  --  Node.js （未検出: node）"
fi
if command -v lazygit >/dev/null 2>&1 \
  || [[ -x "$HOME/.local/bin/lazygit" ]] \
  || [[ -x "$HOME/.local/bin/lazygit.exe" ]]; then
  echo "  OK  lazygit"
else
  echo "  --  lazygit （未検出: lazygit）"
fi
if [[ -x "$HOME/.local/opt/nvim-win64/bin/nvim.exe" ]]; then
  echo "  OK  Neovim ($HOME/.local/opt/nvim-win64/bin/nvim.exe)"
elif [[ -x "$HOME/.local/opt/nvim/bin/nvim" ]]; then
  echo "  OK  Neovim ($HOME/.local/opt/nvim/bin/nvim)"
elif command -v nvim >/dev/null 2>&1; then
  echo "  OK  Neovim ($(command -v nvim))"
else
  echo "  --  Neovim （未検出）"
fi
if [[ -x "$HOME/Apps/oh-my-posh/oh-my-posh.exe" ]]; then
  echo "  OK  Oh My Posh"
elif [[ -x "$HOME/.local/bin/oh-my-posh" ]]; then
  echo "  OK  Oh My Posh ($HOME/.local/bin/oh-my-posh)"
elif command -v oh-my-posh >/dev/null 2>&1; then
  echo "  OK  Oh My Posh ($(command -v oh-my-posh))"
else
  echo "  --  Oh My Posh （未検出）"
fi
if [[ -n "${LOCALAPPDATA:-}" && -f "$(unix_path "$LOCALAPPDATA")/cursor-agent/agent.cmd" ]] \
  || [[ -x "$HOME/.local/bin/agent" ]] \
  || command -v agent >/dev/null 2>&1 \
  || command -v claude >/dev/null 2>&1 \
  || command -v gemini >/dev/null 2>&1 \
  || command -v copilot >/dev/null 2>&1 \
  || command -v codex >/dev/null 2>&1; then
  echo "  OK  AI agent CLI"
else
  echo "  --  AI agent CLI （未検出）"
fi
echo "  conf  $HOME/.wezterm-agent.conf （agent-use で切替）"

if [[ "$DRY_RUN" -eq 1 ]]; then
  echo
  echo "dry-run のためファイルは書いていません。"
else
  echo
  echo "配置しました。WezTerm を再起動し、新しいタブで設定を読み込んでください。"
  echo "ブックマークは ~/.wezterm-dirs.txt を編集します。"
  echo "未検出のツールは先に ./bootstrap.sh 、詳細は docs/prerequisites.md 。"
fi
