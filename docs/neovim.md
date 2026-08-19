# Neovim

設定ファイルは OS ごとに置く。`install.sh` がこのリポジトリの `nvim/` をコピーする。

- Windows: `%LOCALAPPDATA%\nvim\`
- macOS / Linux: `~/.config/nvim/`

本体は `./bootstrap.sh` か [prerequisites.md](prerequisites.md)。

## 内容

| ファイル | 役割 |
| --- | --- |
| `init.lua` | leader、表示、プラグイン |
| `lazy-lock.json` | lazy.nvim のピン留め |

プラグインマネージャは [lazy.nvim](https://github.com/folke/lazy.nvim)。初回起動時に `~/.local/share/nvim-data/lazy/lazy.nvim` 相当へ clone する。

| プラグイン | 用途 |
| --- | --- |
| render-markdown.nvim | Markdown プレビュー |
| gitsigns.nvim | 行の追加・変更表示と hunk 操作 |

## キー（gitsigns）

leader は Space。

| キー | 動作 |
| --- | --- |
| `]c` / `[c` | 次 / 前の hunk |
| `<leader>hp` | hunk プレビュー |
| `<leader>hs` | hunk を stage |
| `<leader>hr` | hunk を戻す |
| `<leader>hb` | 行 blame |

## EDITOR

`bashrc` が使える `nvim`（Windows は `nvim.exe`）を `EDITOR` にする。lazygit の `e` から開くため。
