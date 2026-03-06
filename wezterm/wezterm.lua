local wezterm = require 'wezterm'
local act = wezterm.action

local config = {}

config.default_domain = 'WSL:Ubuntu-24.04'
config.default_prog = { 'wsl.exe', '-d', 'Ubuntu-24.04', '--cd', '~' }

-- Font settings
config.font = wezterm.font({
  family = "IosevkaTerm Nerd Font",
  weight = "Medium",
})
config.font_size = 17
config.line_height = 1.05
config.cell_width = 1.1

-- Colors
config.color_scheme = "tokyonight_storm"

-- Appearance
config.window_decorations = "RESIZE"
config.hide_tab_bar_if_only_one_tab = true
config.window_padding = {
  left = 2,
  right = 2,
  top = 2,
  bottom = 2,
}

-- Keybindings
config.keys = {
  -- Horizontal split
  { key = 'e', mods = 'CTRL|SHIFT', action = act.SplitHorizontal { domain = 'CurrentPaneDomain' } },

  -- Vertical split
  { key = 'o', mods = 'CTRL|SHIFT', action = act.SplitVertical { domain = 'CurrentPaneDomain' } },

  -- Pane navigation (vim style)
  { key = 'h', mods = 'CTRL', action = act.ActivatePaneDirection 'Left' },
  { key = 'j', mods = 'CTRL', action = act.ActivatePaneDirection 'Down' },
  { key = 'k', mods = 'CTRL', action = act.ActivatePaneDirection 'Up' },
  { key = 'l', mods = 'CTRL', action = act.ActivatePaneDirection 'Right' },

  -- Pane resizing
  { key = 'h', mods = 'CTRL|ALT', action = act.AdjustPaneSize { 'Left', 5 } },
  { key = 'j', mods = 'CTRL|ALT', action = act.AdjustPaneSize { 'Down', 5 } },
  { key = 'k', mods = 'CTRL|ALT', action = act.AdjustPaneSize { 'Up', 5 } },
  { key = 'l', mods = 'CTRL|ALT', action = act.AdjustPaneSize { 'Right', 5 } },
}

config.disable_default_key_bindings = false

table.insert(config.keys, {
  key = 'L',
  mods = 'CTRL|SHIFT',
  action = wezterm.action.DisableDefaultAssignment,
})

return config
