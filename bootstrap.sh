#!/usr/bin/env bash
# 不足しているツールをユーザー権限で入れる。設定の配置は install.sh。
# 既定は GitHub / 公式バイナリのポータブル導入（winget / brew に依存しない）。
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
DRY_RUN=0
OS=""
SKIP_WEZTERM=0
AGENT=""

usage() {
  cat <<'EOF'
Usage: ./bootstrap.sh [--dry-run] [--os windows|macos|linux] [--skip-wezterm]
                     [--agent cursor|claude|gemini|copilot|codex]

  未導入のツールだけ入れる。通常は ./setup.sh から呼ぶ。
  WezTerm / Node / lazygit / Neovim / Oh My Posh / フォント / 選んだ AI agent を
  ユーザー領域へ入れる（sudo しない）。

  オプションなしで実行すると、環境と AI agent を番号で選ぶ。
  --os / --agent は対話を省略するとき用。
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
    Linux) echo linux ;;
    *) echo unknown ;;
  esac
}

cpu_kind() {
  case "$(uname -m)" in
    x86_64 | amd64) echo amd64 ;;
    arm64 | aarch64) echo arm64 ;;
    *) uname -m ;;
  esac
}

run() {
  echo "+ $*"
  if [[ "$DRY_RUN" -eq 1 ]]; then
    return
  fi
  "$@"
}

have() {
  command -v "$1" >/dev/null 2>&1
}

download() {
  local url="$1" dest="$2"
  echo "download: $url"
  if [[ "$DRY_RUN" -eq 1 ]]; then
    echo "  -> $dest"
    return
  fi
  mkdir -p "$(dirname "$dest")"
  curl -fL --retry 3 --retry-delay 2 -o "$dest" "$url"
}

url_exists() {
  local code
  code="$(curl -fsL -o /dev/null -w '%{http_code}' -r 0-0 "$1" || true)"
  [[ "$code" == 200 || "$code" == 206 ]]
}

# /releases/latest のリダイレクト先からタグを取る（API 制限を避ける）
github_latest_tag() {
  local repo="$1"
  local url
  url="$(curl -fsSL -o /dev/null -w '%{url_effective}' "https://github.com/${repo}/releases/latest")"
  local tag="${url##*/}"
  if [[ -z "$tag" || "$tag" == latest ]]; then
    return 1
  fi
  echo "$tag"
}

extract_archive() {
  local archive="$1" dest="$2"
  mkdir -p "$dest"
  case "$archive" in
    *.tar.gz | *.tgz) tar -xzf "$archive" -C "$dest" ;;
    *.tar.xz) tar -xJf "$archive" -C "$dest" ;;
    *.zip) tar -xf "$archive" -C "$dest" ;;
    *)
      echo "未知のアーカイブ: $archive" >&2
      return 1
      ;;
  esac
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run) DRY_RUN=1 ;;
    --skip-wezterm) SKIP_WEZTERM=1 ;;
    --agent)
      AGENT="${2:-}"
      shift
      ;;
    --agent=*) AGENT="${1#--agent=}" ;;
    --os)
      OS="${2:-}"
      shift
      ;;
    --os=*) OS="${1#--os=}" ;;
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
if [[ -z "$OS" ]]; then
  if [[ -t 0 ]]; then
    echo "このマシンの環境を選んでください。"
    echo "  検出: ${detected}"
    echo
    echo "  1) Windows"
    echo "  2) macOS"
    echo "  3) Linux"
    echo
    default_num=3
    case "$detected" in
      windows) default_num=1 ;;
      macos) default_num=2 ;;
      linux) default_num=3 ;;
    esac
    printf "番号 [%s]: " "$default_num"
    read -r answer || true
    [[ -z "$answer" ]] && answer="$default_num"
    case "$answer" in
      1 | windows | Windows) OS=windows ;;
      2 | macos | macOS | darwin) OS=macos ;;
      3 | linux | Linux) OS=linux ;;
      *)
        echo "不正な選択: $answer" >&2
        exit 1
        ;;
    esac
  else
    OS="$detected"
  fi
fi
case "$OS" in
  windows | macos | linux) ;;
  *)
    echo "未対応の OS: $OS" >&2
    exit 1
    ;;
esac
if [[ "$OS" == windows && "$detected" != windows ]]; then
  echo "Windows を選びましたが、今のシェルは Git Bash ではありません（検出: $detected）。" >&2
  exit 1
fi
if [[ "$OS" == macos && "$detected" != macos ]]; then
  echo "macOS を選びましたが、今の OS は $detected です。" >&2
  exit 1
fi
if [[ "$OS" == linux && "$detected" == windows ]]; then
  echo "Linux を選びましたが、今のシェルは Windows です。" >&2
  exit 1
fi

if [[ -z "$AGENT" ]]; then
  if [[ -t 0 ]]; then
    echo
    echo "入れる AI agent を選んでください（あとから agent-use で変更できます）。"
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
  else
    AGENT=cursor
  fi
fi
case "$AGENT" in
  cursor | claude | gemini | copilot | codex) ;;
  *)
    echo "未対応の AI agent: $AGENT" >&2
    exit 1
    ;;
esac

ARCH="$(cpu_kind)"
if [[ "$ARCH" != amd64 && "$ARCH" != arm64 ]]; then
  echo "未対応の CPU: $ARCH （amd64 / arm64）" >&2
  exit 1
fi

if ! have curl; then
  echo "curl が必要です。" >&2
  exit 1
fi

LOCALAPPDATA_UNIX=""
if [[ -n "${LOCALAPPDATA:-}" ]]; then
  LOCALAPPDATA_UNIX="$(unix_path "$LOCALAPPDATA")"
fi

TMP="${TMPDIR:-/tmp}/agent-workbench-bootstrap-$$"
mkdir -p "$HOME/.local/bin" "$HOME/.local/opt" "$HOME/Apps" "$TMP"
export PATH="$HOME/.local/bin:$HOME/.local/opt/node:$HOME/.local/opt/node/bin:$PATH"
cleanup() { rm -rf "$TMP"; }
trap cleanup EXIT

echo "OS=$OS arch=$ARCH"

have_wezterm() {
  have wezterm && return 0
  [[ -x "/c/Program Files/WezTerm/wezterm.exe" ]] && return 0
  [[ -x "$HOME/Apps/WezTerm/wezterm.exe" ]] && return 0
  [[ -x "$HOME/Apps/WezTerm/wezterm-gui.exe" ]] && return 0
  [[ -x "$HOME/.local/bin/wezterm" ]] && return 0
  [[ -d "/Applications/WezTerm.app" ]] && return 0
  [[ -d "$HOME/Applications/WezTerm.app" ]] && return 0
  return 1
}

echo "==> WezTerm"
if [[ "$SKIP_WEZTERM" -eq 1 ]]; then
  echo "  skip  （WSL など。本体は Windows 側）"
elif have_wezterm; then
  echo "  OK  既にある"
else
  tag="$(github_latest_tag wezterm/wezterm || true)"
  if [[ -z "$tag" ]]; then
    echo "  --  リリース情報を取れない。https://wezterm.org/"
  else
    case "$OS" in
      windows)
        zip="WezTerm-windows-${tag}.zip"
        download "https://github.com/wezterm/wezterm/releases/download/${tag}/${zip}" "$TMP/$zip"
        if [[ "$DRY_RUN" -eq 0 ]]; then
          rm -rf "$HOME/Apps/WezTerm"
          extract_archive "$TMP/$zip" "$TMP/wezterm"
          inner="$(find "$TMP/wezterm" -maxdepth 2 -type d -name 'WezTerm-windows-*' | head -n 1)"
          if [[ -z "$inner" ]]; then
            inner="$(find "$TMP/wezterm" -maxdepth 1 -mindepth 1 -type d | head -n 1)"
          fi
          mv "$inner" "$HOME/Apps/WezTerm"
          echo "  installed $HOME/Apps/WezTerm"
        fi
        ;;
      macos)
        zip="WezTerm-macos-${tag}.zip"
        download "https://github.com/wezterm/wezterm/releases/download/${tag}/${zip}" "$TMP/$zip"
        if [[ "$DRY_RUN" -eq 0 ]]; then
          extract_archive "$TMP/$zip" "$TMP/wezterm"
          app="$(find "$TMP/wezterm" -type d -name 'WezTerm.app' | head -n 1)"
          mkdir -p "$HOME/Applications"
          rm -rf "$HOME/Applications/WezTerm.app"
          cp -R "$app" "$HOME/Applications/WezTerm.app"
          xattr -dr com.apple.quarantine "$HOME/Applications/WezTerm.app" 2>/dev/null || true
          echo "  installed $HOME/Applications/WezTerm.app"
        fi
        ;;
      linux)
        appimage=""
        for dist in Ubuntu22.04 Ubuntu24.04 Ubuntu20.04; do
          candidate="https://github.com/wezterm/wezterm/releases/download/${tag}/WezTerm-${tag}-${dist}.AppImage"
          if url_exists "$candidate"; then
            appimage="$candidate"
            break
          fi
        done
        if [[ -z "$appimage" ]]; then
          echo "  --  AppImage が見つからない。https://wezterm.org/install/linux.html"
        else
          download "$appimage" "$TMP/wezterm.AppImage"
          if [[ "$DRY_RUN" -eq 0 ]]; then
            chmod +x "$TMP/wezterm.AppImage"
            if (cd "$TMP" && ./wezterm.AppImage --appimage-extract >/dev/null 2>&1); then
              rm -rf "$HOME/.local/opt/wezterm"
              mv "$TMP/squashfs-root" "$HOME/.local/opt/wezterm"
              if [[ -x "$HOME/.local/opt/wezterm/usr/bin/wezterm" ]]; then
                ln -sfn "$HOME/.local/opt/wezterm/usr/bin/wezterm" "$HOME/.local/bin/wezterm"
              fi
              if [[ -x "$HOME/.local/opt/wezterm/usr/bin/wezterm-gui" ]]; then
                ln -sfn "$HOME/.local/opt/wezterm/usr/bin/wezterm-gui" "$HOME/.local/bin/wezterm-gui"
              fi
              echo "  installed $HOME/.local/bin/wezterm （展開済み AppImage）"
            else
              mv "$TMP/wezterm.AppImage" "$HOME/.local/bin/wezterm"
              echo "  installed $HOME/.local/bin/wezterm （AppImage）"
            fi
          fi
        fi
        ;;
    esac
  fi
fi

echo "==> bash"
if have bash; then
  echo "  OK  $(command -v bash)"
else
  echo "  --  bash が無い。Git for Windows / Homebrew / 配布パッケージで入れてから再実行。"
fi

have_node() {
  have node && return 0
  [[ -x "$HOME/.local/opt/node/node.exe" ]] && return 0
  [[ -x "$HOME/.local/opt/node/bin/node" ]] && return 0
  return 1
}

node_lts_ver() {
  # SHASUMS 先頭の node-vX.Y.Z を LTS ライン（22）から取る
  local sums
  sums="$(curl -fsSL "https://nodejs.org/dist/latest-v22.x/SHASUMS256.txt")"
  echo "$sums" | grep -oE 'node-v[0-9]+\.[0-9]+\.[0-9]+' | head -n 1
}

echo "==> Node.js"
if have_node; then
  echo "  OK  既にある"
else
  nver="$(node_lts_ver || true)"
  if [[ -z "$nver" ]]; then
    echo "  --  バージョンを取れない。https://nodejs.org/ （LTS）"
  else
    nv="${nver#node-}"
    asset=""
    case "$OS-$ARCH" in
      windows-amd64) asset="${nver}-win-x64.zip" ;;
      windows-arm64) asset="${nver}-win-arm64.zip" ;;
      macos-amd64) asset="${nver}-darwin-x64.tar.gz" ;;
      macos-arm64) asset="${nver}-darwin-arm64.tar.gz" ;;
      linux-amd64) asset="${nver}-linux-x64.tar.gz" ;;
      linux-arm64) asset="${nver}-linux-arm64.tar.gz" ;;
    esac
    if [[ -z "$asset" ]]; then
      echo "  --  未対応の組み合わせ: $OS $ARCH"
    else
      download "https://nodejs.org/dist/${nv}/${asset}" "$TMP/$asset"
      if [[ "$DRY_RUN" -eq 0 ]]; then
        rm -rf "$HOME/.local/opt/node"
        extract_archive "$TMP/$asset" "$TMP/node"
        inner="$(find "$TMP/node" -maxdepth 1 -mindepth 1 -type d | head -n 1)"
        mv "$inner" "$HOME/.local/opt/node"
        echo "  installed $HOME/.local/opt/node"
      fi
    fi
  fi
fi

have_lazygit() {
  have lazygit && return 0
  [[ -x "$HOME/.local/bin/lazygit" ]] && return 0
  [[ -x "$HOME/.local/bin/lazygit.exe" ]] && return 0
  return 1
}

echo "==> lazygit"
if have_lazygit; then
  echo "  OK  既にある"
else
  tag="$(github_latest_tag jesseduffield/lazygit || true)"
  ver="${tag#v}"
  asset=""
  case "$OS-$ARCH" in
    windows-amd64) asset="lazygit_${ver}_Windows_x86_64.zip" ;;
    windows-arm64) asset="lazygit_${ver}_Windows_arm64.zip" ;;
    macos-amd64) asset="lazygit_${ver}_Darwin_x86_64.tar.gz" ;;
    macos-arm64) asset="lazygit_${ver}_Darwin_arm64.tar.gz" ;;
    linux-amd64) asset="lazygit_${ver}_Linux_x86_64.tar.gz" ;;
    linux-arm64) asset="lazygit_${ver}_Linux_arm64.tar.gz" ;;
  esac
  if [[ -z "$tag" || -z "$asset" ]]; then
    echo "  --  リリース情報を取れない。https://github.com/jesseduffield/lazygit/releases"
  else
    download "https://github.com/jesseduffield/lazygit/releases/download/${tag}/${asset}" "$TMP/$asset"
    if [[ "$DRY_RUN" -eq 0 ]]; then
      extract_archive "$TMP/$asset" "$TMP/lazygit"
      bin="$(find "$TMP/lazygit" -maxdepth 2 \( -name lazygit -o -name lazygit.exe \) -type f | head -n 1)"
      dest="$HOME/.local/bin/lazygit"
      [[ "$bin" == *.exe ]] && dest="$HOME/.local/bin/lazygit.exe"
      mv "$bin" "$dest"
      chmod +x "$dest" 2>/dev/null || true
      echo "  installed $dest"
    fi
  fi
fi

have_nvim() {
  have nvim && return 0
  [[ -x "$HOME/.local/opt/nvim-win64/bin/nvim.exe" ]] && return 0
  [[ -x "$HOME/.local/opt/nvim/bin/nvim.exe" ]] && return 0
  [[ -x "$HOME/.local/opt/nvim/bin/nvim" ]] && return 0
  return 1
}

echo "==> Neovim"
if have_nvim; then
  echo "  OK  既にある"
else
  case "$OS" in
    windows)
      nvim_zip="nvim-win64.zip"
      nvim_dir="nvim-win64"
      if [[ "$ARCH" == arm64 ]]; then
        if url_exists "https://github.com/neovim/neovim/releases/latest/download/nvim-win-arm64.zip"; then
          nvim_zip="nvim-win-arm64.zip"
          nvim_dir="nvim-win-arm64"
        fi
      fi
      download "https://github.com/neovim/neovim/releases/latest/download/${nvim_zip}" "$TMP/$nvim_zip"
      if [[ "$DRY_RUN" -eq 0 ]]; then
        rm -rf "$HOME/.local/opt/$nvim_dir" "$HOME/.local/opt/nvim-win64"
        extract_archive "$TMP/$nvim_zip" "$HOME/.local/opt"
        if [[ "$nvim_dir" != nvim-win64 && -d "$HOME/.local/opt/$nvim_dir" ]]; then
          ln -sfn "$HOME/.local/opt/$nvim_dir" "$HOME/.local/opt/nvim-win64" 2>/dev/null || true
        fi
        echo "  installed $HOME/.local/opt/${nvim_dir}/bin/nvim.exe"
      fi
      ;;
    macos)
      asset="nvim-macos-x86_64.tar.gz"
      dir="nvim-macos-x86_64"
      [[ "$ARCH" == arm64 ]] && { asset="nvim-macos-arm64.tar.gz"; dir="nvim-macos-arm64"; }
      download "https://github.com/neovim/neovim/releases/latest/download/$asset" "$TMP/$asset"
      if [[ "$DRY_RUN" -eq 0 ]]; then
        extract_archive "$TMP/$asset" "$HOME/.local/opt"
        ln -sfn "$HOME/.local/opt/$dir" "$HOME/.local/opt/nvim"
        xattr -dr com.apple.quarantine "$HOME/.local/opt/nvim" 2>/dev/null || true
        echo "  installed $HOME/.local/opt/nvim/bin/nvim"
      fi
      ;;
    linux)
      asset="nvim-linux-x86_64.tar.gz"
      dir="nvim-linux-x86_64"
      [[ "$ARCH" == arm64 ]] && { asset="nvim-linux-arm64.tar.gz"; dir="nvim-linux-arm64"; }
      download "https://github.com/neovim/neovim/releases/latest/download/$asset" "$TMP/$asset"
      if [[ "$DRY_RUN" -eq 0 ]]; then
        extract_archive "$TMP/$asset" "$HOME/.local/opt"
        ln -sfn "$HOME/.local/opt/$dir" "$HOME/.local/opt/nvim"
        echo "  installed $HOME/.local/opt/nvim/bin/nvim"
      fi
      ;;
  esac
fi

echo "==> Oh My Posh"
OMP_WIN="$HOME/Apps/oh-my-posh/oh-my-posh.exe"
OMP_UNIX="$HOME/.local/bin/oh-my-posh"
if [[ -x "$OMP_WIN" || -x "$OMP_UNIX" ]] || { have oh-my-posh && [[ "$(command -v oh-my-posh)" != *WindowsApps* ]]; }; then
  echo "  OK  既にある"
else
  case "$OS" in
    windows)
      omp_asset="posh-windows-amd64.exe"
      [[ "$ARCH" == arm64 ]] && omp_asset="posh-windows-arm64.exe"
      download "https://github.com/JanDeDobbeleer/oh-my-posh/releases/latest/download/$omp_asset" "$OMP_WIN"
      if [[ "$DRY_RUN" -eq 0 ]]; then
        chmod +x "$OMP_WIN" 2>/dev/null || true
        echo "  installed $OMP_WIN"
      fi
      ;;
    macos | linux)
      omp_asset="posh-linux-amd64"
      [[ "$OS" == macos && "$ARCH" == amd64 ]] && omp_asset="posh-darwin-amd64"
      [[ "$OS" == macos && "$ARCH" == arm64 ]] && omp_asset="posh-darwin-arm64"
      [[ "$OS" == linux && "$ARCH" == arm64 ]] && omp_asset="posh-linux-arm64"
      download "https://github.com/JanDeDobbeleer/oh-my-posh/releases/latest/download/${omp_asset}" "$OMP_UNIX"
      if [[ "$DRY_RUN" -eq 0 ]]; then
        chmod +x "$OMP_UNIX"
        echo "  installed $OMP_UNIX"
      fi
      ;;
  esac
fi

OMP_BIN=""
if [[ -x "$OMP_WIN" ]]; then
  OMP_BIN="$OMP_WIN"
elif [[ -x "$OMP_UNIX" ]]; then
  OMP_BIN="$OMP_UNIX"
elif have oh-my-posh; then
  OMP_BIN="$(command -v oh-my-posh)"
fi

echo "==> Meslo Nerd Font"
font_installed=0
for dir in \
  "${LOCALAPPDATA_UNIX:-/dev/null}/Microsoft/Windows/Fonts" \
  "/c/Windows/Fonts" \
  "$HOME/Library/Fonts" \
  "$HOME/.local/share/fonts" \
  "/usr/local/share/fonts" \
  "/usr/share/fonts"
do
  [[ -d "$dir" ]] || continue
  if ls "$dir"/MesloLGLDZ* >/dev/null 2>&1 || ls "$dir"/MesloLG*Nerd* >/dev/null 2>&1; then
    font_installed=1
    break
  fi
done
if [[ "$font_installed" -eq 1 ]]; then
  echo "  OK  Meslo Nerd Font 系あり"
elif [[ -n "$OMP_BIN" && "$DRY_RUN" -eq 0 ]]; then
  if "$OMP_BIN" font install meslo; then
    echo "  OK  oh-my-posh font install meslo"
    if have fc-cache; then
      fc-cache -f "$HOME/.local/share/fonts" 2>/dev/null || true
    fi
  else
    echo "  --  フォント自動導入に失敗。docs/prerequisites.md へ"
  fi
elif [[ "$DRY_RUN" -eq 1 ]]; then
  echo "  would install Meslo Nerd Font"
else
  echo "  --  docs/prerequisites.md の手動手順へ"
fi

run_npm() {
  if [[ -x "$HOME/.local/opt/node/npm" ]]; then
    "$HOME/.local/opt/node/npm" "$@"
  elif [[ -f "$HOME/.local/opt/node/npm.cmd" ]]; then
    "$HOME/.local/opt/node/npm.cmd" "$@"
  elif have npm; then
    npm "$@"
  else
    echo "  --  npm が無い。Node.js の導入を確認してください。"
    return 1
  fi
}

have_agent_cli() {
  case "$1" in
    cursor)
      [[ -n "$LOCALAPPDATA_UNIX" && -f "$LOCALAPPDATA_UNIX/cursor-agent/agent.cmd" ]] && return 0
      [[ -x "$HOME/.local/bin/agent" ]] && return 0
      have agent && return 0
      return 1
      ;;
    claude) have claude ;;
    gemini) have gemini ;;
    copilot) have copilot ;;
    codex) have codex ;;
    *) return 1 ;;
  esac
}

install_cursor_agent() {
  case "$OS" in
    windows)
      echo "  PowerShell で公式インストーラを実行します"
      if [[ "$DRY_RUN" -eq 1 ]]; then
        echo "  would run: irm 'https://cursor.com/install?win32=true' | iex"
      else
        powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "irm 'https://cursor.com/install?win32=true' | iex" \
          || echo "  --  失敗。docs/prerequisites.md"
      fi
      ;;
    *)
      echo "  公式スクリプトを実行します"
      if [[ "$DRY_RUN" -eq 1 ]]; then
        echo "  would run: curl https://cursor.com/install -fsS | bash"
      else
        curl https://cursor.com/install -fsS | bash \
          || echo "  --  失敗。docs/prerequisites.md"
      fi
      ;;
  esac
}

install_claude() {
  case "$OS" in
    windows)
      echo "  PowerShell で Claude Code を入れます"
      if [[ "$DRY_RUN" -eq 1 ]]; then
        echo "  would run: irm https://claude.ai/install.ps1 | iex"
      else
        powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "irm 'https://claude.ai/install.ps1' | iex" \
          || echo "  --  失敗。https://docs.anthropic.com/en/docs/claude-code"
      fi
      ;;
    *)
      echo "  公式スクリプトで Claude Code を入れます"
      if [[ "$DRY_RUN" -eq 1 ]]; then
        echo "  would run: curl -fsSL https://claude.ai/install.sh | bash"
      else
        curl -fsSL https://claude.ai/install.sh | bash \
          || echo "  --  失敗。https://docs.anthropic.com/en/docs/claude-code"
      fi
      ;;
  esac
}

install_npm_cli() {
  local pkg="$1" bin="$2"
  echo "  npm -g $pkg → $bin"
  if [[ "$DRY_RUN" -eq 1 ]]; then
    echo "  would run: npm install -g $pkg"
    return 0
  fi
  run_npm install -g "$pkg" || echo "  --  npm install 失敗: $pkg"
}

echo "==> AI agent CLI ($AGENT)"
if have_agent_cli "$AGENT"; then
  echo "  OK  既にある"
else
  case "$AGENT" in
    cursor) install_cursor_agent ;;
    claude) install_claude ;;
    gemini) install_npm_cli "@google/gemini-cli" gemini ;;
    copilot) install_npm_cli "@github/copilot" copilot ;;
    codex) install_npm_cli "@openai/codex" codex ;;
  esac
fi

echo
echo "ツール導入はここまで。続けて ./install.sh （または ./setup.sh の残り）。"
echo "選んだ AI agent は $AGENT。切替は agent-use。初回は各 CLI の login。"
echo "PATH は ~/.bashrc 経由。今のシェルでは source ~/.bashrc か再起動。"
