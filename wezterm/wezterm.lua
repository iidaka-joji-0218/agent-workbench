-- WezTerm config (Windows / macOS / Linux)
-- Docs: https://wezterm.org/config/files.html

local wezterm = require 'wezterm'
local act = wezterm.action
local config = wezterm.config_builder()

local triple = wezterm.target_triple or ''
local is_windows = triple:find('windows') ~= nil
local is_macos = triple:find('apple') ~= nil or triple:find('darwin') ~= nil

local function path_exists(p)
  local file = io.open(p, 'r')
  if file then
    file:close()
    return true
  end
  return false
end

local function first_existing(paths)
  for _, p in ipairs(paths) do
    if path_exists(p) then
      return p
    end
  end
  return nil
end

-- WezTerm はどの OS でも bash -i（ログインシェル -l は付けない）。
-- macOS のシステム bash 3.2 より Homebrew bash を優先する。
local bash
if is_windows then
  bash = first_existing({
    'C:\\Program Files\\Git\\bin\\bash.exe',
    'C:\\Program Files (x86)\\Git\\bin\\bash.exe',
    wezterm.home_dir .. '\\scoop\\apps\\git\\current\\bin\\bash.exe',
  }) or 'bash'
  -- WSL 環境で入れたときは ./setup.sh が ~/.wezterm-wsl を置く
  if path_exists(wezterm.home_dir .. '/.wezterm-wsl') or path_exists(wezterm.home_dir .. '\\.wezterm-wsl') then
    config.default_prog = { 'wsl.exe', '-e', 'bash', '-i' }
  else
    config.default_prog = { bash, '-i' }
  end
else
  bash = first_existing({
    '/opt/homebrew/bin/bash',
    '/usr/local/bin/bash',
    '/bin/bash',
    '/usr/bin/bash',
  }) or 'bash'
  config.default_prog = { bash, '-i' }
end
config.default_cwd = wezterm.home_dir

if is_windows then
  config.launch_menu = {
    { label = 'Git Bash', args = { bash, '-i' } },
    { label = 'PowerShell 7', args = { 'C:\\Program Files\\PowerShell\\7\\pwsh.exe', '-NoLogo' } },
    { label = 'Windows PowerShell', args = { 'powershell.exe', '-NoLogo' } },
    { label = 'Command Prompt', args = { 'cmd.exe' } },
  }
else
  config.launch_menu = {
    { label = 'bash', args = { bash, '-i' } },
    { label = 'zsh', args = { '/bin/zsh', '-i' } },
  }
end

config.font = wezterm.font_with_fallback({
  'MesloLGLDZ Nerd Font Mono',
  'MesloLGM Nerd Font Mono',
  'JetBrainsMono Nerd Font Mono',
  'Menlo',
  'Consolas',
  'Yu Gothic UI',
  'Hiragino Sans',
  'Noto Sans CJK JP',
})
config.font_size = is_macos and 12.0 or 10.0
config.color_scheme = 'Catppuccin Frappe'
config.hide_tab_bar_if_only_one_tab = false
config.tab_max_width = 40

-- 日本語入力（Windows では IME は常時有効で無効化できない）
-- Builtin は未確定文字列を WezTerm 自身が描くため、右端で切れたり
-- 候補ウィンドウの位置がずれる。System なら OS 側が描画する。
config.use_ime = true
config.ime_preedit_rendering = 'System'

-- パフォーマンス（Intel Iris Xe などの内蔵GPU向け）
config.front_end = 'WebGpu'
config.max_fps = 60
config.animation_fps = 1
config.cursor_blink_rate = 0
config.default_cursor_style = 'SteadyBlock'
config.scrollback_lines = 5000

-- 並列 agent 用レイアウト（現在ペインを起点に分割）
--   Ctrl+Shift+2 … 左右2分割
--   Ctrl+Shift+4 … 左列 lazygit + 右3段 agent
--
-- cwd は「キーを押したペインの現在地」を全ペインに引き継ぐ。
-- これには shell が OSC 7 を送っている必要がある（.bashrc の __osc7）。
-- 取得できないときは config.default_cwd で開く。
local function pane_cwd(pane)
  local ok, url = pcall(function() return pane:get_current_working_dir() end)
  if not ok or not url then return nil end
  if type(url) == 'string' then
    return (url:gsub('^file://[^/]*/', ''))
  end
  return url.file_path
end

local function layout_2(window, pane)
  pane:split { direction = 'Right', size = 0.5, cwd = pane_cwd(pane) }
end

-- ディレクトリ選択は1階層ずつ潜る方式。
-- WezTerm の選択画面に Tab 補完は無いが、階層ごとなら件数が少なく打たずに選べる。
-- ブックマークは一覧の末尾。先頭に - を付けてフォルダと区別する。
-- 未登録フォルダで確定すると追加するか聞く。追加分は ~/.wezterm-dirs.txt に 1 行 1 パス。

-- glob はファイルも返すので除く。
-- Unix ではディレクトリも fopen できるので、`path/.` が glob できるかで判定する。
local function is_dir(p)
  p = (tostring(p):gsub('\\', '/'):gsub('/+$', ''))
  local ok, hits = pcall(wezterm.glob, (p:gsub('%[', '[[]')) .. '/.')
  if ok and hits and #hits > 0 then
    return true
  end
  local file = io.open(p, 'r')
  if file then
    file:close()
    return false
  end
  return true
end

local function normalize_dir(p)
  return (tostring(p):gsub('\\', '/'):gsub('/+$', ''))
end

-- Windows のフォルダ名に使える glob 特殊文字は [ だけ（* ? は名前に使えない）
local function glob_escape(p)
  return (p:gsub('%[', '[[]'))
end

local function subdirs(dir)
  local out = {}
  local ok, hits = pcall(wezterm.glob, glob_escape(dir) .. '/*')
  if ok and hits then
    for _, hit in ipairs(hits) do
      local p = normalize_dir(hit)
      if is_dir(p) then table.insert(out, p) end
    end
  end
  table.sort(out)
  return out
end

local function parent_dir(p)
  local up = p:match('^(.*)/[^/]+$')
  if not up or up == '' then return nil end
  return up
end

local BOOKMARK_FILE = wezterm.home_dir .. '/.wezterm-dirs.txt'

local function bookmarks()
  local out, seen = {}, {}
  local function add(p)
    p = normalize_dir(p)
    if p == '' or seen[p] then return end
    seen[p] = true
    table.insert(out, p)
  end
  -- 案件フォルダなどは ~/.wezterm-dirs.txt に書く（マシン固有のためここには置かない）
  add(wezterm.home_dir)
  local file = io.open(BOOKMARK_FILE, 'r')
  if file then
    for line in file:lines() do
      line = (line:gsub('^%s+', ''):gsub('%s+$', ''))
      if line ~= '' and not line:match('^#') then
        add(line)
      end
    end
    file:close()
  end
  return out
end

local function is_bookmarked(dir)
  dir = normalize_dir(dir)
  for _, mark in ipairs(bookmarks()) do
    if mark == dir then return true end
  end
  return false
end

local function add_bookmark(dir)
  dir = normalize_dir(dir)
  if dir == '' or is_bookmarked(dir) then return end
  local file = io.open(BOOKMARK_FILE, 'a')
  if not file then return end
  file:write(dir .. '\n')
  file:close()
end

-- 未登録なら追加するか聞く。Esc / 「追加しない」でも選択自体は進める。
local function maybe_bookmark(window, pane, dir, then_fn)
  if is_bookmarked(dir) then
    then_fn()
    return
  end
  window:perform_action(
    act.InputSelector {
      title = 'ブックマークに追加しますか？  ' .. dir,
      fuzzy = false,
      choices = {
        { id = 'yes', label = '⭐  追加する  ' .. dir },
        { id = 'no', label = '追加しない' },
      },
      action = wezterm.action_callback(function(_, _, id)
        if id == 'yes' then
          add_bookmark(dir)
        end
        then_fn()
      end),
    },
    pane
  )
end

-- 1階層ずつ潜って決定する。決定・上へ・子フォルダのあと、ブックマーク。
-- title は画面上部に出す説明文（何のためのフォルダか）。
-- fuzzy_desc は fuzzy 入力行の先頭文言（未指定なら title）。
-- 子フォルダはブックマーク済みでも隠さない（末尾の⭐と別扱い）。
-- ブックマークは先頭に - を付けてフォルダと区別する。
local choose_dir
choose_dir = function(window, pane, title, dir, on_pick, fuzzy_desc)
  dir = normalize_dir(dir)

  local choices = {
    { id = '!ok', label = '✓ このフォルダにする  ' .. dir },
  }

  local up = parent_dir(dir)
  if up then
    table.insert(choices, { id = up, label = '..  上へ (' .. up .. ')' })
  end

  for _, sub in ipairs(subdirs(dir)) do
    table.insert(choices, { id = sub, label = '📁  ' .. (sub:match('[^/]+$') or sub) })
  end

  for _, mark in ipairs(bookmarks()) do
    local suffix = (mark == dir) and '  (いまここ)' or ''
    table.insert(choices, {
      id = mark,
      label = wezterm.format {
        { Foreground = { Color = '#a6adc8' } },
        { Text = '-  ⭐  ' .. mark .. suffix },
      },
    })
  end

  window:perform_action(
    act.InputSelector {
      title = title .. '  |  いま見ている場所: ' .. dir,
      choices = choices,
      fuzzy = true,
      fuzzy_description = (fuzzy_desc or title) .. ': ',
      action = wezterm.action_callback(function(win, p, id)
        if not id then return end
        if id == '!ok' then
          maybe_bookmark(win, p, dir, function()
            on_pick(dir)
          end)
        else
          choose_dir(win, p, title, id, on_pick, fuzzy_desc)
        end
      end),
    },
    pane
  )
end

-- 4列（左から lazygit, agent×3）。
-- 比率は lazygit : agent : agent : agent = LG_UNITS : AGENT_UNITS : … （既定 5:3:3:3）。
-- 〜208列幅だと agent 各 ≈45列、lazygit ≈74列になる。
--   1回目: 右帯（agent×3）= 3*AGENT / (LG+3*AGENT)
--   2回目: 右帯の 2/3 を新ペインに（残り agent を等分）
--   3回目: 残りを半分
-- コマンドの自動実行を止めたいときは false にする（ペイン配置だけになる）。
local auto_run = true
local LG_UNITS = 5
local AGENT_UNITS = 3
local AGENT_BAND = (AGENT_UNITS * 3) / (LG_UNITS + AGENT_UNITS * 3) -- 9/14

-- shell 起動直後は最初の1文字が捨てられることがある（`cd` が `d` になる）。
-- 捨てられてもいい改行を先に送ってからコマンド本体を打つ。
local function run_in_pane(pane, cmd)
  pane:send_text '\n'
  wezterm.sleep_ms(300)
  pane:send_text(cmd .. '\n')
end

local function build_agent_layout(pane, lg_dir, agent_dir)
  local a1 = pane:split { direction = 'Right', size = AGENT_BAND, cwd = agent_dir }
  local a2 = a1:split { direction = 'Right', size = 2 / 3, cwd = agent_dir }
  local a3 = a2:split { direction = 'Right', size = 0.5, cwd = agent_dir }

  if auto_run then
    -- 起点ペインは spawn 済みで cwd を渡せないので cd で合わせる。
    -- agent / lazygit は .bashrc の関数・PATH 経由なので shell に打ち込む。
    wezterm.sleep_ms(1200)
    run_in_pane(pane, string.format("cd '%s' && lazygit", lg_dir))
    for _, p in ipairs { a1, a2, a3 } do
      -- ~/.wezterm-agent.conf の provider（agent-use で切替）
      run_in_pane(p, 'agent')
    end
  end
  pane:activate()
end

local function ask_one_dir(window, pane, title, start, on_ready, fuzzy_desc)
  choose_dir(window, pane, title, start or pane_cwd(pane) or wezterm.home_dir, on_ready, fuzzy_desc)
end

-- lazygit 用と agent 用の2回、ディレクトリを聞く。
-- 2回目は1回目に選んだ場所から潜り始めるので、同じ系列なら数キーで済む。
local function ask_dirs(window, pane, on_ready)
  ask_one_dir(window, pane, '1/2  左ペインの lazygit を開くフォルダ', nil, function(lg_dir)
    ask_one_dir(window, pane, '2/2  右3ペインの agent を起動するフォルダ', lg_dir, function(agent_dir)
      on_ready(lg_dir, agent_dir)
    end, 'agentオープンフォルダ')
  end, 'lazygitオープンフォルダ')
end

-- 今のタブをレイアウトにする
local function layout_agents(window, pane)
  ask_dirs(window, pane, function(lg_dir, agent_dir)
    build_agent_layout(pane, lg_dir, agent_dir)
  end)
end

-- 新しいタブを作ってレイアウトにする
local function new_agent_tab(window, pane)
  ask_dirs(window, pane, function(lg_dir, agent_dir)
    local ok, _, new_pane = pcall(function()
      local tab, p = window:mux_window():spawn_tab { cwd = lg_dir }
      return tab, p
    end)
    if ok and new_pane then
      build_agent_layout(new_pane, lg_dir, agent_dir)
    end
  end)
end

-- 先に worktree の有無を聞く。
-- Yes → 今どおり 4 分割。No → 同じフォルダ選択のあと bash だけ。
-- new_tab が true なら今のペインではなく新しいタブで開く。
local function start_session(window, pane, new_tab)
  window:perform_action(
    act.InputSelector {
      title = 'worktree はありますか？',
      fuzzy = false,
      choices = {
        { id = 'yes', label = 'Yes  worktree あり → lazygit + agent を4分割' },
        { id = 'no', label = 'No   worktree なし → bash だけ開く' },
      },
      action = wezterm.action_callback(function(win, p, id)
        if id == 'yes' then
          if new_tab then
            new_agent_tab(win, p)
          else
            layout_agents(win, p)
          end
        elseif id == 'no' then
          ask_one_dir(win, p, 'bash を開くフォルダ', nil, function(dir)
            if new_tab then
              pcall(function()
                window:mux_window():spawn_tab { cwd = dir }
              end)
            else
              wezterm.sleep_ms(1200)
              run_in_pane(p, string.format("cd '%s'", dir))
            end
          end, 'bashオープンフォルダ')
        end
      end),
    },
    pane
  )
end

-- 起動時は worktree の有無から聞く。失敗しても素のウィンドウは残る。
wezterm.on('gui-startup', function(cmd)
  local _, pane, window = wezterm.mux.spawn_window(cmd or {})
  pcall(function()
    window:gui_window():perform_action(
      wezterm.action_callback(function(win, p) start_session(win, p, false) end),
      pane
    )
  end)
end)

-- クリップボードが画像なら一時 PNG を書いてパスを貼る（Claude Code / agent 向け）。
-- Win+Shift+S は PNG 形式だけで ContainsImage() が false になることがある。
-- Git Bash / WSL ではシェルが読める POSIX パスに直す。
local function posix_from_windows(path, wsl)
  local drive, rest = path:match('^([A-Za-z]):[\\/](.*)$')
  if not drive then
    return path:gsub('\\', '/')
  end
  rest = rest:gsub('\\', '/')
  if wsl then
    return '/mnt/' .. drive:lower() .. '/' .. rest
  end
  return '/' .. drive:lower() .. '/' .. rest
end

local function pane_path_style(pane)
  local name, domain = '', ''
  pcall(function()
    name = pane:get_foreground_process_name() or ''
  end)
  pcall(function()
    domain = pane:get_domain_name() or ''
  end)
  local hay = (name .. ' ' .. domain):lower()
  if hay:find('wsl', 1, true) then
    return 'wsl'
  end
  if hay:find('powershell') or hay:find('pwsh') or hay:find('cmd%.exe') then
    return 'windows'
  end
  if is_windows then
    return 'gitbash'
  end
  return 'posix'
end

local function clipboard_image_path()
  if is_windows then
    local ps = [[
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
$files = [System.Windows.Forms.Clipboard]::GetFileDropList()
if ($files -and $files.Count -gt 0) {
  $p = [string]$files[0]
  if ($p -match '\.(png|jpe?g|gif|webp|bmp)$') {
    [Console]::Out.Write($p)
    exit 0
  }
}
$dir = Join-Path (Get-Item -LiteralPath $env:TEMP).FullName 'wezterm-paste'
New-Item -ItemType Directory -Force -Path $dir | Out-Null
$path = Join-Path $dir ('paste-{0:yyyyMMdd-HHmmssfff}.png' -f (Get-Date))
$data = [System.Windows.Forms.Clipboard]::GetDataObject()
if ($data -and $data.GetDataPresent('PNG')) {
  $stream = $data.GetData('PNG')
  $fs = [System.IO.File]::OpenWrite($path)
  try { $stream.CopyTo($fs) } finally { $fs.Close() }
  [Console]::Out.Write((Get-Item -LiteralPath $path).FullName)
  exit 0
}
if ([System.Windows.Forms.Clipboard]::ContainsImage()) {
  $img = [System.Windows.Forms.Clipboard]::GetImage()
  if ($null -eq $img) { exit 2 }
  $img.Save($path, [System.Drawing.Imaging.ImageFormat]::Png)
  [Console]::Out.Write((Get-Item -LiteralPath $path).FullName)
  exit 0
}
exit 2
]]
    local ok, stdout = wezterm.run_child_process({
      'powershell.exe',
      '-NoProfile',
      '-STA',
      '-NonInteractive',
      '-Command',
      ps,
    })
    if not ok or not stdout then
      return nil
    end
    local path = stdout:gsub('[\r\n]+$', '')
    if path == '' then
      return nil
    end
    return path
  end

  if is_macos then
    local dir = '/tmp/wezterm-paste'
    wezterm.run_child_process({ 'mkdir', '-p', dir })
    local path = dir .. '/paste-' .. wezterm.strftime('%Y%m%d-%H%M%S') .. '.png'
    local script = string.format(
      'try\nset imgData to the clipboard as «class PNGf»\nset f to open for access POSIX file "%s" with write permission\nset eof f to 0\nwrite imgData to f\nclose access f\non error\nreturn\nend try',
      path
    )
    local ok = wezterm.run_child_process({ 'osascript', '-e', script })
    if ok and path_exists(path) then
      return path
    end
    return nil
  end

  local dir = '/tmp/wezterm-paste'
  wezterm.run_child_process({ 'mkdir', '-p', dir })
  local path = dir .. '/paste-' .. wezterm.strftime('%Y%m%d-%H%M%S') .. '.png'
  local ok = wezterm.run_child_process({ 'bash', '-lc', string.format(
    'mkdir -p %q; if [ -n "$WAYLAND_DISPLAY" ] && wl-paste --list-types 2>/dev/null | grep -q "^image/"; then wl-paste > %q; elif command -v xclip >/dev/null && xclip -selection clipboard -t TARGETS -o 2>/dev/null | grep -q "^image/"; then xclip -selection clipboard -t image/png -o > %q; else exit 2; fi',
    dir,
    path,
    path
  ) })
  if ok and path_exists(path) then
    return path
  end
  return nil
end

local function smart_paste(window, pane)
  local path = clipboard_image_path()
  if path then
    local style = pane_path_style(pane)
    if style == 'wsl' then
      path = posix_from_windows(path, true)
    elseif style == 'gitbash' then
      path = posix_from_windows(path, false)
    end
    pane:send_paste(path)
    window:toast_notification('WezTerm', '画像: ' .. path, nil, 2500)
    return
  end
  window:perform_action(act.PasteFrom 'Clipboard', pane)
end

-- ペイン操作
--   追加: SHIFT+ALT+矢印（矢印の向きに新しいペインを作る）
--   閉じる: SHIFT+ALT+W（作成と同系統。誤爆防止で confirm あり）
--   移動: ALT+矢印
--   サイズ調整: CTRL+ALT+矢印
--   レイアウト: CTRL+SHIFT+2 / CTRL+SHIFT+4
config.keys = {
  -- ペースト: 既定は CTRL+SHIFT+V のみ。CTRL+V は端末の quoted-insert（^V）に
  -- 予約されていて貼り付けにならないので、上書きして Windows の慣習に合わせる。
  -- 画像なら一時ファイルのパスを bracketed paste する。
  { key = 'v', mods = 'CTRL', action = wezterm.action_callback(smart_paste) },
  { key = 'v', mods = 'CTRL|SHIFT', action = wezterm.action_callback(smart_paste) },
  { key = 'Insert', mods = 'SHIFT', action = wezterm.action_callback(smart_paste) },

  -- 追加
  { key = 'LeftArrow', mods = 'SHIFT|ALT', action = act.SplitPane { direction = 'Left', size = { Percent = 50 } } },
  { key = 'RightArrow', mods = 'SHIFT|ALT', action = act.SplitPane { direction = 'Right', size = { Percent = 50 } } },
  { key = 'UpArrow', mods = 'SHIFT|ALT', action = act.SplitPane { direction = 'Up', size = { Percent = 50 } } },
  { key = 'DownArrow', mods = 'SHIFT|ALT', action = act.SplitPane { direction = 'Down', size = { Percent = 50 } } },

  -- 閉じる（実行中プロセスがあると確認ダイアログ）
  { key = 'w', mods = 'SHIFT|ALT', action = act.CloseCurrentPane { confirm = true } },

  -- 移動
  { key = 'LeftArrow', mods = 'ALT', action = act.ActivatePaneDirection 'Left' },
  { key = 'RightArrow', mods = 'ALT', action = act.ActivatePaneDirection 'Right' },
  { key = 'UpArrow', mods = 'ALT', action = act.ActivatePaneDirection 'Up' },
  { key = 'DownArrow', mods = 'ALT', action = act.ActivatePaneDirection 'Down' },

  -- サイズ調整
  { key = 'LeftArrow', mods = 'CTRL|ALT', action = act.AdjustPaneSize { 'Left', 3 } },
  { key = 'RightArrow', mods = 'CTRL|ALT', action = act.AdjustPaneSize { 'Right', 3 } },
  { key = 'UpArrow', mods = 'CTRL|ALT', action = act.AdjustPaneSize { 'Up', 3 } },
  { key = 'DownArrow', mods = 'CTRL|ALT', action = act.AdjustPaneSize { 'Down', 3 } },

  -- スクロール（1ページ未満。押しっぱなしで連打）
  { key = 'UpArrow', mods = 'SHIFT', action = act.ScrollByLine(-3) },
  { key = 'DownArrow', mods = 'SHIFT', action = act.ScrollByLine(3) },

  -- アクティブペインを一時的に全画面化（作業中の内容をじっくり見る）
  -- 文字キーは phys: で指定する。mapped の文字+CTRL|SHIFT は WezTerm が
  -- SHIFT を落として Ctrl+そのキー になり、Ctrl+Shift+そのキーでは発火しない。
  { key = 'phys:Z', mods = 'CTRL|SHIFT', action = act.TogglePaneZoomState },

  -- 並列 agent 用フォーマット（現在ペインをさらに分割する。既存レイアウトは崩さないよう単ペイン時に使う）
  { key = '2', mods = 'CTRL|SHIFT', action = wezterm.action_callback(layout_2) },
  { key = '4', mods = 'CTRL|SHIFT', action = wezterm.action_callback(layout_agents) },
  -- JIS では Shift+4 が `$` になり、既定の ActivateTab(3) に吸われる
  { key = '$', mods = 'CTRL|SHIFT', action = wezterm.action_callback(layout_agents) },

  -- タブ作成: 先に worktree の有無を聞く（Yes なら4分割、No なら bash のみ）
  -- 既定の Ctrl+Shift+T（素の SpawnTab）を消してから phys で置き換える
  { key = 'mapped:T', mods = 'CTRL|SHIFT', action = act.DisableDefaultAssignment },
  { key = 'phys:T', mods = 'CTRL|SHIFT', action = wezterm.action_callback(function(win, p)
    start_session(win, p, true)
  end) },
  -- 何も聞かない素のタブが欲しいとき
  { key = 't', mods = 'CTRL|ALT', action = act.SpawnTab 'CurrentPaneDomain' },
}

-- 非アクティブペインを暗くして、今どこを見ているか分かりやすくする
config.inactive_pane_hsb = { saturation = 0.85, brightness = 0.65 }


-- 日本語を壊さないよう、バイト数ではなく文字数で切り詰める
local function truncate(text, limit)
  local ok, len = pcall(function() return utf8.len(text) end)
  if not ok or not len then
    -- 不正なバイト列のときは安全側に倒してそのまま返す
    return text
  end
  if len <= limit then
    return text
  end
  local cut = utf8.offset(text, limit)
  if not cut then
    return text
  end
  return text:sub(1, cut - 1) .. '…'
end

-- ペインのラベルを取得: Cursor / Claude Code の hook が書いたタイトルを優先し、
-- 手動 title コマンド、OSC タイトルの順でフォールバックする
local function pane_label(p)
  local label = nil
  local ok_id, pane_id = pcall(function() return p:pane_id() end)
  if ok_id and pane_id then
    for _, sub in ipairs({ '.cursor/pane-titles/', '.claude/pane-titles/' }) do
      local path = wezterm.home_dir .. '/' .. sub .. tostring(pane_id) .. '.txt'
      local file = io.open(path, 'r')
      if file then
        local l = file:read('*l')
        file:close()
        if l and l ~= '' then
          label = l
          break
        end
      end
    end
  end
  if not label or label == '' then
    local ok, vars = pcall(function() return p:get_user_vars() end)
    label = ok and vars and vars.PANE_TITLE or nil
  end
  if not label or label == '' then
    local ok2, t = pcall(function() return p:get_title() end)
    label = (ok2 and t) or '?'
  end
  return truncate(label, 20)
end

-- 全ペインの「番号:タイトル」をタブバー右端に常時表示（アクティブは強調）
-- 画面上の配置順（上→下、左→右）に並べ、区切りで縦横の関係が読めるようにする
wezterm.on('update-status', function(window, pane)
  local ok, items = pcall(function()
    local tab = pane:tab()
    if not tab then return nil end

    local panes = tab:panes_with_info()
    table.sort(panes, function(a, b)
      if a.top ~= b.top then return a.top < b.top end
      return a.left < b.left
    end)

    local out = {}
    local prev_top = nil
    for _, info in ipairs(panes) do
      if prev_top ~= nil then
        -- 行が変わる（上下に並ぶ）ときは / 、同じ行（左右）は | で区切る
        table.insert(out, { Foreground = { Color = '#585b70' } })
        table.insert(out, { Text = info.top ~= prev_top and ' / ' or ' | ' })
      end
      local label = string.format('%d:%s', info.index + 1, pane_label(info.pane))
      if info.is_active then
        table.insert(out, { Foreground = { Color = '#f9e2af' } })
        table.insert(out, { Attribute = { Intensity = 'Bold' } })
        table.insert(out, { Text = label })
        table.insert(out, { Attribute = { Intensity = 'Normal' } })
      else
        table.insert(out, { Foreground = { Color = '#7f849c' } })
        table.insert(out, { Text = label })
      end
      prev_top = info.top
    end
    table.insert(out, { Text = ' ' })
    return out
  end)
  if ok and items then
    window:set_right_status(wezterm.format(items))
  else
    window:set_right_status('')
  end
end)

return config
