#!/usr/bin/env bash
# 対話式の共通インストール。最初に環境を選んでからツール＋設定を入れる。
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
DRY_RUN=0
OS_OVERRIDE=""
YES=0
WINDOWS_HOME_OPT=""
AGENT_OVERRIDE=""

usage() {
  cat <<'EOF'
Usage: ./setup.sh [--dry-run] [--os windows|macos|linux|wsl] [--yes]
                 [--windows-home PATH]
                 [--agent cursor|claude|gemini|copilot|codex]

  最初に環境と AI agent を番号で選び、同じ手順でツール導入と設定配置を行う。
  Git と bash と curl だけ先に入れておく（clone に必要）。
  普段はオプションなしで ./setup.sh を実行する。

  --os             メニューを出さず環境を指定する（自動化用）
  --agent          メニューを出さず AI agent を指定する（自動化用）
  --windows-home   WSL 時、WezTerm 設定を置く Windows のホーム
  --yes            確認を省略する（非対話。CI や --os と一緒に使う）
  --dry-run        ダウンロードやコピーをしない
EOF
}

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

detect_os() {
  case "$(uname -s)" in
    MINGW* | MSYS* | CYGWIN*) echo windows ;;
    Darwin) echo macos ;;
    Linux)
      if grep -qiE 'microsoft|wsl' /proc/version 2>/dev/null; then
        echo wsl
      else
        echo linux
      fi
      ;;
    *) echo unknown ;;
  esac
}

windows_home_from_wsl() {
  local p=""
  if command -v cmd.exe >/dev/null 2>&1; then
    p="$(cmd.exe /c 'echo %USERPROFILE%' 2>/dev/null | tr -d '\r' | tail -n 1)"
  fi
  if [[ -z "$p" || "$p" == *%USERPROFILE%* ]]; then
    return 1
  fi
  unix_path "$p"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run) DRY_RUN=1 ;;
    --yes | -y) YES=1 ;;
    --os)
      OS_OVERRIDE="${2:-}"
      shift
      ;;
    --os=*) OS_OVERRIDE="${1#--os=}" ;;
    --windows-home)
      WINDOWS_HOME_OPT="${2:-}"
      shift
      ;;
    --windows-home=*) WINDOWS_HOME_OPT="${1#--windows-home=}" ;;
    --agent)
      AGENT_OVERRIDE="${2:-}"
      shift
      ;;
    --agent=*) AGENT_OVERRIDE="${1#--agent=}" ;;
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

detected="$(detect_os)"
choice="$OS_OVERRIDE"

if [[ -z "$choice" ]]; then
  if [[ ! -t 0 && "$YES" -eq 0 ]]; then
    echo "非対話です。 --os windows|macos|linux|wsl を付けて実行してください。" >&2
    exit 1
  fi

  echo "このマシンの環境を選んでください。"
  echo "  検出: ${detected}"
  echo
  echo "  1) Windows   WezTerm もツールも Windows（Git Bash）"
  echo "  2) macOS"
  echo "  3) Linux     WezTerm もツールも Linux"
  echo "  4) WSL       ツールは Linux、WezTerm の設定だけ Windows へ"
  echo
  default_num=3
  case "$detected" in
    windows) default_num=1 ;;
    macos) default_num=2 ;;
    linux) default_num=3 ;;
    wsl) default_num=4 ;;
  esac
  printf "番号 [%s]: " "$default_num"
  read -r answer || true
  [[ -z "$answer" ]] && answer="$default_num"
  case "$answer" in
    1 | windows | Windows) choice=windows ;;
    2 | macos | macOS | darwin) choice=macos ;;
    3 | linux | Linux) choice=linux ;;
    4 | wsl | WSL) choice=wsl ;;
    *)
      echo "不正な選択: $answer" >&2
      exit 1
      ;;
  esac
fi

case "$choice" in
  windows | macos | linux | wsl) ;;
  *)
    echo "未対応の環境: $choice （windows / macos / linux / wsl）" >&2
    exit 1
    ;;
esac

if [[ "$choice" == windows && "$detected" != windows ]]; then
  echo "Windows を選びましたが、今のシェルは Git Bash ではありません（検出: $detected）。" >&2
  echo "Windows で入れるときは Git Bash から ./setup.sh を実行してください。" >&2
  exit 1
fi
if [[ "$choice" == macos && "$detected" != macos ]]; then
  echo "macOS を選びましたが、今の OS は $detected です。" >&2
  exit 1
fi
if [[ "$choice" == linux && "$detected" == windows ]]; then
  echo "Linux を選びましたが、今のシェルは Windows です。" >&2
  exit 1
fi
if [[ "$choice" == wsl && "$detected" == windows ]]; then
  echo "WSL を選びましたが、今のシェルは Git Bash です。Windows を選んでください。" >&2
  exit 1
fi

agent_choice="${AGENT_OVERRIDE:-}"
if [[ -z "$agent_choice" ]]; then
  if [[ "$YES" -eq 1 || ! -t 0 ]]; then
    agent_choice=cursor
  else
    echo
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
      1 | cursor) agent_choice=cursor ;;
      2 | claude) agent_choice=claude ;;
      3 | gemini) agent_choice=gemini ;;
      4 | copilot) agent_choice=copilot ;;
      5 | codex) agent_choice=codex ;;
      *)
        echo "不正な選択: $agent_answer" >&2
        exit 1
        ;;
    esac
  fi
fi
case "$agent_choice" in
  cursor | claude | gemini | copilot | codex) ;;
  *)
    echo "未対応の AI agent: $agent_choice" >&2
    exit 1
    ;;
esac

BOOTSTRAP_OS="$choice"
WINDOWS_HOME=""
SKIP_WEZTERM=0
if [[ "$choice" == wsl ]]; then
  BOOTSTRAP_OS=linux
  SKIP_WEZTERM=1
  if [[ -n "$WINDOWS_HOME_OPT" ]]; then
    WINDOWS_HOME="$(unix_path "$WINDOWS_HOME_OPT")"
  else
    WINDOWS_HOME="$(windows_home_from_wsl || true)"
  fi
  if [[ -z "$WINDOWS_HOME" ]]; then
    echo "WSL から Windows のユーザーフォルダを取れませんでした。" >&2
    echo "  ./setup.sh --os wsl  の前に cmd.exe が使えるか確認するか、" >&2
    echo "  INSTALL 側は --windows-home '/mnt/c/Users/名前' を付けてください。" >&2
    exit 1
  fi
fi

echo
echo "==== インストール内容 ===="
echo "  環境:     $choice"
echo "  ツールOS: $BOOTSTRAP_OS"
echo "  AI agent: $agent_choice （ペインでは agent 、切替は agent-use）"
if [[ -n "$WINDOWS_HOME" ]]; then
  echo "  WezTerm設定: $WINDOWS_HOME/.wezterm.lua"
  echo "  その他の設定: $HOME"
fi
echo "  作業:     未導入ツールの導入 → 設定ファイルの配置"
[[ "$DRY_RUN" -eq 1 ]] && echo "  モード:   dry-run"
echo

if [[ "$YES" -eq 0 ]]; then
  printf "この内容で進めますか？ [Y/n]: "
  read -r ok || true
  case "$ok" in
    '' | Y | y | yes) ;;
    *)
      echo "中止しました。"
      exit 0
      ;;
  esac
fi

chmod +x "$ROOT/bootstrap.sh" "$ROOT/install.sh" 2>/dev/null || true

bootstrap_args=(--os "$BOOTSTRAP_OS" --agent "$agent_choice")
[[ "$DRY_RUN" -eq 1 ]] && bootstrap_args+=(--dry-run)
[[ "$SKIP_WEZTERM" -eq 1 ]] && bootstrap_args+=(--skip-wezterm)

install_args=(--agent "$agent_choice")
[[ "$DRY_RUN" -eq 1 ]] && install_args+=(--dry-run)
[[ -n "$WINDOWS_HOME" ]] && install_args+=(--windows-home "$WINDOWS_HOME")

echo
echo "==> 1/2  ツール"
"$ROOT/bootstrap.sh" "${bootstrap_args[@]}"

echo
echo "==> 2/2  設定"
"$ROOT/install.sh" "${install_args[@]}"

echo
echo "完了。WezTerm を再起動し、新しいタブで必要ならログインしてください（例: agent login）。"
echo "AI agent の切替: agent-use cursor|claude|gemini|copilot|codex"
if [[ "$choice" == wsl ]]; then
  echo "WSL: WezTerm 本体は Windows 側に入れてください。設定は $WINDOWS_HOME/.wezterm.lua です。"
fi
echo "よく使うフォルダは ~/.wezterm-dirs.txt に 1 行 1 パスで書きます。"
