local wezterm = require("wezterm")
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
config.default_cursor_style = "SteadyBar"

-- Translucency & Styling
config.window_background_opacity = 0.80
config.macos_window_background_blur = 50
-- config.color_scheme = "rose-pine-moon"
-- config.color_scheme = 'Kanagawa (Gogh)'
-- config.color_scheme = 'Catppuccin Mocha'
config.color_scheme = "Tokyo Night"

-- Option Key Behavior
config.send_composed_key_when_left_alt_is_pressed = false
config.send_composed_key_when_right_alt_is_pressed = false

-- Let apps (e.g. herdr) request the Kitty keyboard protocol so WezTerm can
-- forward Super/Cmd and disambiguated Ctrl/Alt chords.
-- Do NOT use enable_csi_u_key_encoding = true here; it rewrites modified keys
-- unconditionally and breaks apps that can't opt out.
config.enable_kitty_keyboard = true

-- Disable confirmation prompt when closing a window
config.window_close_confirmation = "NeverPrompt"

-- Keep the macOS app process running when all tabs/windows are closed
config.quit_when_all_windows_are_closed = false

-- Native macOS Shortcuts & Text Navigation
-- NB: these consume Option/Cmd+Arrows before herdr ever sees them, so don't
-- bind herdr actions to those chords (herdr pane nav is prefix+h/j/k/l).
config.keys = {
	-- Use SendString (raw bytes) rather than SendKey: the shell wants these
	-- exact legacy sequences (ESC b, ESC f, ESC DEL, 0x01, 0x05) and
	-- SendString emits them directly, without keyboard-protocol re-encoding.
	-- Word Jumping (Option + Left/Right Arrow / Backspace)
	{
		key = "LeftArrow",
		mods = "OPT",
		action = wezterm.action.SendString("\x1bb"),
	},
	{
		key = "RightArrow",
		mods = "OPT",
		action = wezterm.action.SendString("\x1bf"),
	},
	{
		key = "Backspace",
		mods = "OPT",
		action = wezterm.action.SendString("\x1b\x7f"),
	},

	-- Page Up/Down (Fn + Up/Down)
	-- On this Mac, Fn+Up/Down arrive as Alt+Up/Alt+Down, so we translate those
	-- into the standard legacy PageUp/PageDown sequences (ESC [ 5 ~ / ESC [ 6 ~).
	-- This makes Fn+Up/Down page in TUIs (opencode, vim, less, man, ...).
	-- NB: because Fn and Option are indistinguishable at the byte level here,
	-- Option+Up/Down are remapped too.
	{
		key = "UpArrow",
		mods = "ALT",
		action = wezterm.action.SendString("\x1b[5~"),
	},
	{
		key = "DownArrow",
		mods = "ALT",
		action = wezterm.action.SendString("\x1b[6~"),
	},

	-- Line Jump Start/End (Cmd + Left/Right Arrow)
	{
		key = "LeftArrow",
		mods = "CMD",
		action = wezterm.action.SendString("\x01"),
	},
	{
		key = "RightArrow",
		mods = "CMD",
		action = wezterm.action.SendString("\x05"),
	},
	-- Delete to start of line (Cmd + Backspace)
	-- No WezTerm default exists for this; make it explicit so it survives the
	-- Kitty keyboard negotiation inside herdr instead of degrading to one char.
	{
		key = "Backspace",
		mods = "CMD",
		action = wezterm.action.SendString("\x15"), -- Ctrl+U: zsh emacs kill-whole-line
	},
	-- Cmd + Shift + L opens the Launcher Menu (shows SSH: ubvm, local shell, etc.)
	{
		key = "L",
		mods = "CMD|SHIFT",
		action = wezterm.action.ShowLauncher,
	},
	-- Cmd + Shift + P opens the Command Palette
	{
		key = "P",
		mods = "CMD|SHIFT",
		action = wezterm.action.ActivateCommandPalette,
	},
	-- Set to ToggleFullScreen for window-level, or TogglePaneZoomState for pane-level
	{
		key = "Enter",
		mods = "CMD",
		action = wezterm.action.ToggleFullScreen,
	},
}

-- Automatically imports host details from your ~/.ssh/config
config.ssh_domains = {
	{
		name = "ubvm",
		remote_address = "ubvm",
		multiplexing = "None",
	},
}

return config
