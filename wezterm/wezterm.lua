local wezterm = require 'wezterm'
local act = wezterm.action

local config = {}

local is_windows = wezterm.target_triple:find('windows') ~= nil

if is_windows then
  config.default_domain = 'WSL:Ubuntu-24.04'
  config.default_prog = { 'wsl.exe', '-d', 'Ubuntu-24.04', '--cd', '~' }
end

-- Font settings
config.font = wezterm.font_with_fallback({
  { family = "IosevkaTerm Nerd Font", weight = "Medium" },
  { family = "Symbols Nerd Font Mono" },
  { family = "FiraCode Nerd Font" },
})
config.font_size = 15
config.line_height = 1.05
config.cell_width = 1.1

-- Suppress missing-glyph popups. Some Neovim plugins still emit legacy
-- Nerd Fonts v2 codepoints (e.g. U+F8D6) that were removed in v3; placeholder
-- squares render in their place but the warning itself is just noise.
config.warn_about_missing_glyphs = false

-- Colors — inlined to avoid intermittent named-scheme lookup failures
config.colors = {
  foreground    = "#c0caf5",
  background    = "#24283b",
  cursor_bg     = "#c0caf5",
  cursor_fg     = "#24283b",
  cursor_border = "#c0caf5",
  selection_fg  = "#c0caf5",
  selection_bg  = "#364a82",
  scrollbar_thumb = "#292e42",
  split         = "#7aa2f7",
  ansi = {
    "#1d202f", -- black
    "#f7768e", -- red
    "#9ece6a", -- green
    "#e0af68", -- yellow
    "#7aa2f7", -- blue
    "#bb9af7", -- magenta
    "#7dcfff", -- cyan
    "#a9b1d6", -- white
  },
  brights = {
    "#414868", -- bright black
    "#f7768e", -- bright red
    "#9ece6a", -- bright green
    "#e0af68", -- bright yellow
    "#7aa2f7", -- bright blue
    "#bb9af7", -- bright magenta
    "#7dcfff", -- bright cyan
    "#c0caf5", -- bright white
  },
}

-- Appearance
config.window_decorations = "RESIZE"
config.hide_tab_bar_if_only_one_tab = true
config.window_padding = {
  left = 2,
  right = 2,
  top = 2,
  bottom = 2,
}

-- Pane navigation/resize cooperates with smart-splits.nvim. When the focused
-- pane is running (n)vim, the key is forwarded to nvim and smart-splits decides
-- whether to move within nvim or fall back out to wezterm. When the pane is
-- not running nvim, wezterm acts on the pane directly.
local direction_for = {
  h = 'Left',
  j = 'Down',
  k = 'Up',
  l = 'Right',
}

local function is_vim(pane)
  -- User var set by smart-splits.nvim (reliable on WSL2 where process name
  -- inspection sees wsl.exe instead of nvim)
  if pane:get_user_vars().IS_NVIM == 'true' then
    return true
  end
  local procname = pane:get_foreground_process_name() or ''
  return procname:match('n?vim$') ~= nil
end

local function smart_split_action(mode, key)
  local mods = mode == 'resize' and 'ALT' or 'CTRL'
  return wezterm.action_callback(function(win, pane)
    if is_vim(pane) then
      win:perform_action(act.SendKey { key = key, mods = mods }, pane)
    elseif mode == 'resize' then
      win:perform_action(act.AdjustPaneSize { direction_for[key], 3 }, pane)
    else
      win:perform_action(act.ActivatePaneDirection(direction_for[key]), pane)
    end
  end)
end

config.keys = {
  -- Horizontal split
  { key = 'e', mods = 'CTRL|SHIFT', action = act.SplitHorizontal { domain = 'CurrentPaneDomain' } },

  -- Vertical split
  { key = 'o', mods = 'CTRL|SHIFT', action = act.SplitVertical { domain = 'CurrentPaneDomain' } },

  -- Close current pane (not tab/window)
  { key = 'w', mods = 'CTRL|ALT', action = act.CloseCurrentPane { confirm = false } },

  -- Pane navigation (Ctrl+hjkl) — smart-splits-aware
  { key = 'h', mods = 'CTRL', action = smart_split_action('move', 'h') },
  { key = 'j', mods = 'CTRL', action = smart_split_action('move', 'j') },
  { key = 'k', mods = 'CTRL', action = smart_split_action('move', 'k') },
  { key = 'l', mods = 'CTRL', action = smart_split_action('move', 'l') },

  -- Pane resizing (Alt+hjkl) — smart-splits-aware
  { key = 'h', mods = 'ALT', action = smart_split_action('resize', 'h') },
  { key = 'j', mods = 'ALT', action = smart_split_action('resize', 'j') },
  { key = 'k', mods = 'ALT', action = smart_split_action('resize', 'k') },
  { key = 'l', mods = 'ALT', action = smart_split_action('resize', 'l') },
}

config.disable_default_key_bindings = false

table.insert(config.keys, {
  key = 'L',
  mods = 'CTRL|SHIFT',
  action = wezterm.action.DisableDefaultAssignment,
})

local local_config_path = wezterm.home_dir .. '/.config/wezterm/local.lua'
local ok, local_config = pcall(dofile, local_config_path)

if ok and type(local_config) == 'table' then
  for k, v in pairs(local_config) do
    config[k] = v
  end
end

return config
