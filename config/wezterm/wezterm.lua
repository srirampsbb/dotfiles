local wezterm = require 'wezterm'
local config = wezterm.config_builder()

-- Set default window dimensions (in columns and rows)
config.initial_cols = 120
config.initial_rows = 35

-- Set the scrollback buffer size to 10,000 lines per tab
config.scrollback_lines = 10000

-- Remove Top Bar (Hides window title bar, macOS traffic lights, and tab bar)
config.window_decorations = "RESIZE"
config.hide_tab_bar_if_only_one_tab = true

-- Font & Colors
config.font = wezterm.font("Hack Nerd Font")
config.font_size = 15.0
config.default_cursor_style = 'SteadyBar'
-- Set background to pure black
config.colors = {
  background = '#000000',
}

-- Translucency & Styling
config.window_background_opacity = 0.60
config.inactive_pane_hsb = {
  hue = 1.0,
  saturation = 1.0,
  brightness = 0.8, -- adjust this value to control dimming (0.0 to 1.0)
}
config.macos_window_background_blur = 50
-- config.color_scheme = "rose-pine-moon"
-- config.color_scheme = 'Kanagawa (Gogh)'
-- config.color_scheme = 'Catppuccin Mocha'
config.color_scheme = 'Tokyo Night'

-- Option Key Behavior
config.send_composed_key_when_left_alt_is_pressed = false
config.send_composed_key_when_right_alt_is_pressed = false

-- REQUIRED FOR macOS: Enable progressive key reporting for Ctrl + Arrows
config.enable_csi_u_key_encoding = true

-- Disable confirmation prompt when closing a window
config.window_close_confirmation = 'NeverPrompt'

-- Keep the macOS app process running when all tabs/windows are closed
config.quit_when_all_windows_are_closed = false

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
  -- Set to ToggleFullScreen for window-level, or TogglePaneZoomState for pane-level
  {
    key = 'Enter',
    mods = 'CMD',
    action = wezterm.action.ToggleFullScreen,
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
