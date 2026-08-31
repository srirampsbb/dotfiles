local wezterm = require 'wezterm'
local config = wezterm.config_builder()


-- Set default window dimensions (in columns and rows)
config.initial_cols = 120
config.initial_rows = 35

-- Remove Top Bar (Hides window title bar, macOS traffic lights, and tab bar)
config.window_decorations = "RESIZE"
config.hide_tab_bar_if_only_one_tab = true

-- Font & Colors
config.font = wezterm.font("Hack Nerd Font")
config.font_size = 15.0
config.default_cursor_style = 'SteadyBar'

-- macOS Translucency & Styling
config.window_background_opacity = 0.80
config.macos_window_background_blur = 50
-- config.color_scheme = "rose-pine-moon"
config.color_scheme = 'Kanagawa (Gogh)'
-- config.color_scheme = 'Tokyo Night'

-- Option Key Behavior
config.send_composed_key_when_left_alt_is_pressed = false
config.send_composed_key_when_right_alt_is_pressed = false


-- REQUIRED FOR macOS: Enable progressive key reporting for Ctrl + Arrows
config.enable_csi_u_key_encoding = true

-- Native macOS Shortcuts & Text Navigation
config.keys = {
  -- Word Jumping (Option + Left/Right Arrow)
  {
    key = 'LeftArrow',
    mods = 'OPT',
    action = wezterm.action.SendKey { key = 'b', mods = 'ALT' },
  },
  {
    key = 'RightArrow',
    mods = 'OPT',
    action = wezterm.action.SendKey { key = 'f', mods = 'ALT' },
  },

  -- Line Jump Start/End (Cmd + Left/Right Arrow)
  {
    key = 'LeftArrow',
    mods = 'CMD',
    action = wezterm.action.SendKey { key = 'a', mods = 'CTRL' },
  },
  {
    key = 'RightArrow',
    mods = 'CMD',
    action = wezterm.action.SendKey { key = 'e', mods = 'CTRL' },
  },
  -- Cmd + Shift + L opens the Launcher Menu (shows SSH: ubvm, local shell, etc.)
  {
    key = 'L',
    mods = 'CMD|SHIFT',
    action = wezterm.action.ShowLauncher,
  },
  -- Cmd + Shift + P opens the Command Palette
  {
    key = 'P',
    mods = 'CMD|SHIFT',
    action = wezterm.action.ActivateCommandPalette,
  },
}

-- Automatically imports host details from your ~/.ssh/config
config.ssh_domains = {
  {
    name = 'ubvm',
    remote_address = 'ubvm',
    multiplexing = 'None',
  },
}
return config
