#!/usr/bin/env bash
# WezTerm のペインタイトルを、直近のプロンプトの先頭部分で更新する。
# UserPromptSubmit hook から stdin 経由で JSON を受け取る。
set -euo pipefail

[ -n "${WEZTERM_PANE:-}" ] || exit 0

input=$(cat)
prompt=$(jq -r '.prompt // empty' <<<"$input" 2>/dev/null || echo "")
[ -n "$prompt" ] || exit 0

title=$(printf '%s' "$prompt" | tr '\n\r' '  ' | cut -c1-30)

dir="$HOME/.claude/pane-titles"
mkdir -p "$dir"
printf '%s' "$title" > "$dir/${WEZTERM_PANE}.txt"
