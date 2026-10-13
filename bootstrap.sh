#!/usr/bin/env bash
# ------------------------------------------------------------------------------
# bootstrap.sh — provision a machine from this dotfiles repo (macOS or Rocky Linux 8+)
#
#   ~/.dotfiles/bootstrap.sh
#
# Installs, in order:
#   1. git submodules (nvim config lives in a submodule)
#   2. OS packages (Homebrew + Brewfile on macOS; dnf + extras on Rocky/RHEL)
#   3. language-specific packages (cargo/rustup, go, npm, uv)
#   4. symlinks into $HOME ("Option A": real ~/.config + per-entry links)
#
# Safe to re-run.
# ------------------------------------------------------------------------------
set -euo pipefail

REPO="${DOTFILES:-$HOME/.dotfiles}"
CONFIG="${XDG_CONFIG_HOME:-$HOME/.config}"
OS="$(uname -s)"

c_info=$'\033[1;34m'
c_warn=$'\033[1;33m'
c_err=$'\033[1;31m'
c_off=$'\033[0m'
log() { printf '%s==>%s %s\n' "$c_info" "$c_off" "$*"; }
warn() { printf '%s!!%s %s\n' "$c_warn" "$c_off" "$*" >&2; }
die() {
	printf '%sxx%s %s\n' "$c_err" "$c_off" "$*" >&2
	exit 1
}

[[ -d "$REPO/.git" ]] || die "dotfiles repo not found at '$REPO' (set DOTFILES=/path)"

# Detect Rocky/RHEL family on Linux
is_rocky_rhel=false
if [[ "$OS" == "Linux" ]] && [[ -r /etc/os-release ]]; then
	# shellcheck disable=SC1091
	source /etc/os-release
	if [[ "${ID:-}" == "rocky" || "${ID_LIKE:-}" == *"rhel"* || "${ID:-}" == "rhel" || "${ID:-}" == "centos" ]]; then
		is_rocky_rhel=true
	fi
fi

log "Detected OS: $OS (rocky/rhel family: $is_rocky_rhel)"

# 1 ── git submodules ----------------------------------------------------------
log "Initialising git submodules"
git -C "$REPO" submodule update --init --recursive

# 2 ── OS packages -------------------------------------------------------------
if [[ "$OS" == "Darwin" ]]; then
	# Homebrew + Brewfile
	if ! command -v brew >/dev/null 2>&1; then
		log "Installing Homebrew"
		NONINTERACTIVE=1 /bin/bash -c \
			"$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
	fi
	if [[ -x /opt/homebrew/bin/brew ]]; then
		eval "$(/opt/homebrew/bin/brew shellenv)"
	elif [[ -x /usr/local/bin/brew ]]; then
		eval "$(/usr/local/bin/brew shellenv)"
	fi
	log "Installing Homebrew bundle"
	brew bundle --file "$REPO/Brewfile"
elif [[ "$is_rocky_rhel" == true ]]; then
	log "Rocky/RHEL detected: using dnf"
	# Base utilities
	sudo dnf -y install dnf-plugins-core curl wget git zsh util-linux-user
	# EPEL + CRB (needed for some tools on EL8)
	if ! dnf repolist | grep -q epel 2>/dev/null; then
		sudo dnf -y install epel-release || warn "epel-release install failed"
	fi
	sudo dnf config-manager --set-enabled crb 2>/dev/null || sudo dnf config-manager --set-enabled powertools 2>/dev/null || true
	sudo dnf -y makecache || true

	# Core CLI/editor tools
	sudo dnf -y install \
		fzf \
		ripgrep \
		jq \
		fd-find \
		neovim \
		tree-sitter \
		git \
		python3 \
		nodejs \
		npm \
		go \
		gcc \
		gcc-c++ \
		make \
		pkgconfig \
		openssl-devel \
		libgit2-devel \
		zlib-devel ||
		warn "some dnf packages failed"

	# bat/eza may not be in base EL8 repos; try EPEL/COPR lightly or skip (can use cargo)
	sudo dnf -y install bat eza 2>/dev/null || log "bat/eza not in repos (will try cargo if needed)"

	# gh (GitHub CLI) on EL8: often available via gh repo or EPEL in newer streams; try
	if ! command -v gh >/dev/null 2>&1; then
		log "Attempting to install GitHub CLI (gh)"
		sudo dnf -y config-manager --add-repo https://cli.github.com/packages/rpm/gh-cli.repo 2>/dev/null || true
		sudo dnf -y install gh 2>/dev/null || warn "gh install via repo failed (optional)"
	fi

	# yazi: not always in EL8 repos; skip here (can be installed via cargo/binary later)
	command -v yazi >/dev/null 2>&1 || log "yazi not found (optional; install via cargo or release if desired)"

	# shfmt/stylua/prettier/golangci-lint/lua-language-server: try to install if available; else rely on cargo/npm/uv/go as appropriate
	sudo dnf -y install shfmt golangci-lint 2>/dev/null || true
	sudo dnf -y install stylua 2>/dev/null || true
	sudo dnf -y install lua-language-server 2>/dev/null || true
	sudo dnf -y install prettier 2>/dev/null || true

	# Ensure fd binary name matches expectations (fd-find -> fd)
	if command -v fd-find >/dev/null 2>&1 && ! command -v fd >/dev/null 2>&1; then
		mkdir -p "$HOME/.local/bin"
		ln -sf "$(command -v fd-find)" "$HOME/.local/bin/fd"
		export PATH="$HOME/.local/bin:$PATH"
		log "linked fd-find -> $HOME/.local/bin/fd"
	fi

	# herdr/opencode: may not be packaged on EL8; warn if missing
	command -v herdr >/dev/null 2>&1 || warn "herdr not installed (optional; can install via binary/cargo if needed)"
	command -v opencode >/dev/null 2>&1 || warn "opencode not installed (optional; can install via binary/npm/cargo if needed)"

	# GUI/font not applicable on headless Linux
	log "Skipping GUI casks (wezterm, Nerd Font) on Linux"
else
	warn "Unsupported OS '$OS' — treating as best-effort (no native pkg manager configured)"
fi

# 3 ── language packages -------------------------------------------------------
# Ensure cargo via rustup if missing (works cross-OS)
if ! command -v cargo >/dev/null 2>&1; then
	if command -v rustup >/dev/null 2>&1; then
		log "rustup found; sourcing env"
		# shellcheck disable=SC1090
		source "$HOME/.cargo/env" 2>/dev/null || true
	else
		log "Installing rustup (Rust toolchain)"
		curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --profile minimal
		# shellcheck disable=SC1090
		source "$HOME/.cargo/env"
	fi
fi
# Install cargo tools
if command -v cargo >/dev/null 2>&1; then
	log "cargo: shuck-cli, zoxide"
	cargo install shuck-cli zoxide 2>/dev/null || warn "some cargo packages failed (maybe already installed)"
else
	warn "cargo not found; skipping cargo packages"
fi

# go: gopls installed by nvim/mason; log GOPATH
if command -v go >/dev/null 2>&1; then
	log "go: $(go env GOPATH)/bin (gopls handled by nvim/mason)"
else
	warn "go not found; skipping go packages"
fi

# npm global packages (none by default)
if command -v npm >/dev/null 2>&1; then
	log "npm global packages: (none)"
else
	warn "npm not found; skipping npm packages"
fi

# uv
if ! command -v uv >/dev/null 2>&1; then
	log "Installing uv"
	curl -LsSf https://astral.sh/uv/install.sh | sh
	export PATH="$HOME/.local/bin:$HOME/.cargo/bin:$PATH"
fi
if command -v uv >/dev/null 2>&1; then
	log "uv tool: basedpyright"
	uv tool install basedpyright 2>/dev/null || warn "uv tool install basedpyright failed"
else
	warn "uv not found; skipping uv tools"
fi

# Ensure common bin dirs in PATH for future shells
mkdir -p "$HOME/.local/bin" "$HOME/.cargo/bin"

# 4 ── symlinks (Option A) -----------------------------------------------------
link() { # link <target> <source>
	local target="$1" source="$2"
	mkdir -p "$(dirname "$target")"
	if [[ -L "$target" ]]; then
		if [[ "$(readlink "$target")" == "$source" ]]; then
			log "ok    $target"
			return 0
		fi
		warn "relinking $target"
		rm -f "$target"
	elif [[ -e "$target" ]]; then
		warn "moving existing $target -> $target.bak"
		mv "$target" "$target.bak"
	fi
	ln -s "$source" "$target"
	log "link  $target -> $source"
}

log "Creating symlinks"

# Whole-entry links (no runtime state in their config dir)
link "$HOME/.zshrc" "$REPO/zsh/zshrc"
link "$CONFIG/nvim" "$REPO/config/nvim"
# wezterm config only useful on macOS/GUI; link if present in repo (safe)
if [[ -d "$REPO/config/wezterm" ]]; then
	link "$CONFIG/wezterm" "$REPO/config/wezterm"
fi

# opencode
if [[ -L "$CONFIG/opencode" ]]; then rm -f "$CONFIG/opencode"; fi
mkdir -p "$CONFIG/opencode"
if [[ -f "$REPO/config/opencode/service.json" ]]; then
	mv -f "$REPO/config/opencode/service.json" "$CONFIG/opencode/service.json" 2>/dev/null || true
fi
[[ -f "$REPO/config/opencode/cli.json" ]] && link "$CONFIG/opencode/cli.json" "$REPO/config/opencode/cli.json"
[[ -f "$REPO/config/opencode/tui.json" ]] && link "$CONFIG/opencode/tui.json" "$REPO/config/opencode/tui.json"
[[ -d "$REPO/config/opencode/commands" ]] && link "$CONFIG/opencode/commands" "$REPO/config/opencode/commands"

# herdr
mkdir -p "$CONFIG/herdr"
[[ -f "$REPO/config/herdr/config.toml" ]] && link "$CONFIG/herdr/config.toml" "$REPO/config/herdr/config.toml"

# 5 ── misc --------------------------------------------------------------------
if command -v zsh >/dev/null 2>&1; then
	if [[ "${SHELL:-}" != "$(command -v zsh)" ]]; then
		log "Setting login shell to zsh (may prompt for your password)"
		chsh -s "$(command -v zsh)" 2>/dev/null || warn "chsh failed; set login shell to zsh manually"
	fi
	# Ensure zsh in /etc/shells on Linux
	if [[ "$OS" == "Linux" ]]; then
		zsh_bin="$(command -v zsh)"
		if ! grep -q "^$zsh_bin$" /etc/shells 2>/dev/null; then
			log "Adding $zsh_bin to /etc/shells"
			echo "$zsh_bin" | sudo tee -a /etc/shells >/dev/null 2>&1 || warn "failed to add zsh to /etc/shells"
		fi
	fi
else
	warn "zsh not installed; skipping shell change"
fi

log "Done. Open a new terminal (or run: exec zsh)."
log "If on Linux, add ~/.local/bin and ~/.cargo/bin to PATH in your shell if needed."
