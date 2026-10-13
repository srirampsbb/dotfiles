# ==============================================================================
# Brewfile — macOS packages required by this dotfiles repo
#   brew bundle --file ~/.dotfiles/Brewfile
# ==============================================================================

# --- Shell & CLI --------------------------------------------------------------
brew "fzf"                     # fuzzy finder (zsh, git + jira helpers)
brew "fd"                      # fast find (telescope.nvim)
brew "ripgrep"                 # fast grep (telescope.nvim)
brew "jq"                      # JSON (jira helpers)
brew "gh"                      # GitHub CLI (octo.nvim)
brew "eza"                     # ls replacement (ll/l aliases)
brew "bat"                     # cat replacement
brew "yazi"                    # terminal file manager
brew "sevenzip"                # 7-Zip archiver (7z)
brew "git"
brew "zsh-autosuggestions"     # zsh plugin (sourced from brew share)
brew "zsh-syntax-highlighting" # zsh plugin (sourced from brew share)
brew "zsh-completions"         # zsh completion functions (FPATH)

# --- Languages & runtimes -----------------------------------------------------
brew "python@3.14"             # keep in sync with HOMEBREW_PYTHON_VERSION (zsh/zshrc)
brew "node"
brew "go"
brew "rust"                    # provides cargo for `cargo install` tools
brew "uv"

# --- Editor & formatting tooling ---------------------------------------------
brew "neovim"
brew "tree-sitter"
brew "tree-sitter-cli"
brew "shfmt"                   # shell formatting (code-checker)
brew "prettier"               # json/yaml/md formatting (nvim + code-checker)
brew "stylua"                  # lua formatting (nvim + code-checker)
brew "tombi"                   # toml formatting + linting (code-checker)
brew "ruff"                    # python lint/format (nvim)
brew "goimports"               # go formatting (nvim)
brew "golangci-lint"           # go linting (code-checker)
brew "lua-language-server"     # lua checks (code-checker)

# --- Agent tools --------------------------------------------------------------
brew "herdr"                   # core formula with native Linux bottles too

# --- Casks --------------------------------------------------------------------
cask "wezterm" if OS.mac?              # macOS-only GUI app
cask "font-hack-nerd-font"             # font cask: macOS + Linux (~/.local/share/fonts)
