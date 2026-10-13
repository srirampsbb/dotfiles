# Packages installed

## System packages (via bootstrap)

### macOS (Darwin) — via Homebrew + Brewfile

- `fzf` — fuzzy finder (zsh + git/jira helpers)
- `fd` — fast find (Telescope.nvim)
- `ripgrep` — fast grep (Telescope.nvim)
- `jq` — JSON (jira helpers)
- `gh` — GitHub CLI (octo.nvim)
- `eza` — ls replacement
- `bat` — cat replacement
- `yazi` — terminal file manager
- `git`
- `zsh-autosuggestions` — zsh plugin
- `zsh-syntax-highlighting` — zsh plugin
- `zsh-completions` — zsh completion functions (FPATH)
- `python@3.14`
- `node`
- `go`
- `rust` — provides cargo
- `uv`
- `neovim`
- `tree-sitter`, `tree-sitter-cli`
- `shfmt` — shell formatting (code-checker)
- `prettier` — JSON/YAML/MD formatting (nvim + code-checker)
- `stylua` — Lua formatting (nvim + code-checker)
- `ruff` — Python lint/format (nvim)
- `goimports` — Go formatting (nvim)
- `golangci-lint` — Go linting (code-checker)
- `lua-language-server` — Lua LSP (code-checker)
- `herdr` — agent tool
- `opencode` — agent tool
- `wezterm` (cask)
- `font-hack-nerd-font` (cask)

### Rocky Linux 8 / RHEL family (Linux) — via dnf

Base/system:

- `git`, `zsh`, `curl`, `wget`, `util-linux-user`
- `fzf`, `ripgrep`, `jq`, `fd-find` (symlinked to `fd` in `~/.local/bin`), `neovim`, `tree-sitter`
- `python3`, `nodejs`, `npm`, `go`
- Build deps: `gcc`, `gcc-c++`, `make`, `pkgconfig`, `openssl-devel`, `libgit2-devel`, `zlib-devel`
- `gh` (if available from repo)
- `bat`, `eza` (if available)
- `shfmt`, `stylua`, `prettier`, `golangci-lint`, `lua-language-server` (if available in repos)
  Notes: `yazi`, `herdr`, `opencode`, `wezterm`, Nerd Font may need to come from other sources on Linux.

## Language tools installed by bootstrap

- **cargo** (via `rustup` if missing): `shuck-cli`, `zoxide`
- **uv** (installed if missing): `basedpyright` (via `uv tool install`)

## Neovim (config/nvim/init.lua) — plugins via vim.pack

Core/UI:

- `guess-indent.nvim` (NMAC427/guess-indent.nvim)
- `gitsigns.nvim` (lewis6991/gitsigns.nvim)
- `which-key.nvim` (folke/which-key.nvim)
- `catppuccin.nvim` (catppuccin/nvim)
- `todo-comments.nvim` (folke/todo-comments.nvim)
- `mini.nvim` (nvim-mini/mini.nvim) — includes mini.icons, mini.ai, mini.surround, mini.statusline

Search/navigation:

- `plenary.nvim` (nvim-lua/plenary.nvim)
- `telescope.nvim` (nvim-telescope/telescope.nvim)
- `telescope-ui-select.nvim` (nvim-telescope/telescope-ui-select.nvim)
- `telescope-fzf-native.nvim` (nvim-telescope/telescope-fzf-native.nvim) — built with `make` if available

LSP/formatting/completion/treesitter:

- `fidget.nvim` (j-hui/fidget.nvim)
- `nvim-lspconfig` (neovim/nvim-lspconfig)
- `mason.nvim` (mason-org/mason.nvim)
- `mason-lspconfig.nvim` (mason-org/mason-lspconfig.nvim)
- `mason-tool-installer.nvim` (WhoIsSethDaniel/mason-tool-installer.nvim)
- `conform.nvim` (stevearc/conform.nvim)
- `LuaSnip` (L3MON4D3/LuaSnip, v2.*)
- `blink.cmp` (saghen/blink.cmp, v1.*)
- `nvim-treesitter` (nvim-treesitter/nvim-treesitter, main)

Custom: `custom.plugins` (loaded from `lua/custom/plugins/*.lua`)

## Mason-managed tools (installed by mason-tool-installer from init.lua)

LSP servers (ensure_installed from `servers` keys, excluding `shuck` which is configured to use `~/.cargo/bin/shuck`):

- `basedpyright` (Python)
- `gopls` (Go)
- `jsonls` (JSON)
- `yamlls` (YAML)
- `rust_analyzer` (Rust)
- `lua_ls` (Lua)

Note: `shuck` is not installed via Mason (ignored). The shell LSP comes from `cargo install shuck-cli` and is pointed to explicitly in nvim config.

## External formatters used by conform.nvim

- `shfmt` (zsh/bash/sh; zsh forced via custom formatter)
- `ruff` (ruff_fix/ruff_format/ruff_organize_imports for Python)
- `goimports`, `gofmt` (Go)
- `jq` (JSON)
- `prettier` (YAML)
- `stylua` is configured as the Lua formatter externally (via conform setup context; nvim also uses stylua via system)
- `trim_whitespace` (generic)

## Treesitter parsers (auto-installed)

Baseline: `bash`, `c`, `diff`, `html`, `lua`, `luadoc`, `markdown`, `markdown_inline`, `query`, `vim`, `vimdoc` (others installed on demand by filetype)
