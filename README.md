# dotfiles

This repo provisions a fresh machine (macOS or Rocky Linux 8+) via [`bootstrap.sh`](./bootstrap.sh). It's safe to re-run.

## Quick start

```bash
git clone git@github.com-personal:srirampsbb/dotfiles.git ~/.dotfiles
cd ~/.dotfiles
./bootstrap.sh
```

Override repo location: `DOTFILES=/path/to/repo ./bootstrap.sh`.

---

## What bootstrap.sh does

### 1. Git submodules

- `git submodule update --init --recursive`
- Submodules: `config/nvim` → [`git@github.com-personal:srirampsbb/nvim-config.git`](https://github.com-personal/srirampsbb/nvim-config.git)

### 2. OS packages

**macOS (Darwin)**

- Installs Homebrew if missing (non-interactive)
- Sets up Homebrew env (`/opt/homebrew` or `/usr/local`)
- Runs `brew bundle --file Brewfile`

**Rocky Linux 8 / RHEL family (Linux)**

- Installs base tools via `dnf` (git, zsh, curl/wget, util-linux-user)
- Enables EPEL and CRB/Powertools
- Installs CLI/editor tools via dnf (fzf, ripgrep, jq, fd-find→fd, neovim, tree-sitter, python3, nodejs/npm, go, build deps)
- Tries bat/eza, gh, shfmt/stylua/prettier/golangci-lint/lua-language-server if available
- Skips GUI casks (wezterm/Nerd Font); logs guidance
- Notes optional tools (herdr/opencode/yazi) if not packaged

See [packages.md](./packages.md) for the full list of packages.

### 3. Language packages

- **Rust/cargo**: if `cargo` missing, installs `rustup` (minimal profile) and sources env; then `cargo install shuck-cli zoxide`
- **Go**: logs `$(go env GOPATH)/bin` (gopls handled by nvim/mason)
- **npm**: no global packages by default
- **uv**: installs `uv` via official script if missing; runs `uv tool install basedpyright`

Creates `~/.local/bin` and `~/.cargo/bin` as needed.

### 4. Symlinks (Option A)

Keeps real `~/.config` dirs so runtime state (sockets/logs/caches, `service.json`) stays outside git.

| Target              | Source                                                  |
| ------------------- | ------------------------------------------------------- |
| `~/.zshrc`          | `zsh/zshrc`                                             |
| `~/.bashrc`         | `bash/bashrc` (prompt + PATH only)                      |
| `~/.bash_profile`   | `bash/bash_profile` (symlinked, or appended if present) |
| `~/.config/nvim`    | `config/nvim` (submodule)                               |
| `~/.config/wezterm` | `config/wezterm` (linked only if present)               |

**opencode** (real dir; runtime preserved):

- Moves `service.json` to real config if present; links `cli.json`, `tui.json`, `commands/`

**herdr** (real dir):

- Links only `config.toml`

### 5. Misc

- Installs zsh if needed but leaves the existing login shell unchanged

---

## Python version

`zsh/zshrc` pins which Homebrew Python `python`, `python3`, `pip`, and `pip3`
resolve to, through a single variable:

```zsh
HOMEBREW_PYTHON_VERSION=3.14
```

Homebrew's versioned Python is keg-only: it links only `python3.14` into
`$HOMEBREW_PREFIX/bin`, while the unversioned `python`/`python3`/`pip`/`pip3`
symlinks live in `$HOMEBREW_PREFIX/opt/python@<version>/libexec/bin`. The `zshrc`
prepends that directory to `PATH`, so both names point at the pinned version and
take precedence over `/usr/bin/python3`.

The variable is the single source of truth for the shell, but the version also
appears in the `Brewfile` formula name — keep the two in sync:

| Place       | Value                          |
| ----------- | ------------------------------ |
| `zsh/zshrc` | `HOMEBREW_PYTHON_VERSION=3.14` |
| `Brewfile`  | `brew "python@3.14"`           |

To upgrade (e.g. to 3.15):

1. Set `HOMEBREW_PYTHON_VERSION=3.15` in `zsh/zshrc`.
2. Change the `Brewfile` line to `brew "python@3.15"`.
3. Install it — `brew install python@3.15` or re-run `./bootstrap.sh`.
4. `exec zsh` (or open a new terminal) to pick up the new `PATH`.

---

## Directory layout

```
.
├── Brewfile
├── bootstrap.sh
├── packages.md
├── bash/
│   ├── bashrc
│   ├── bash_profile
│   └── aliases.sh
├── config/
│   ├── herdr/config.toml
│   ├── nvim/          # git submodule
│   ├── opencode/
│   │   ├── cli.json
│   │   ├── commands/
│   │   │   ├── code-checker.md
│   │   │   └── code-checker.zsh
│   │   └── tui.json
│   └── wezterm/wezterm.lua
└── zsh/
    ├── aliases.zsh
    ├── git-functions.zsh
    ├── jira-funcs.zsh
    └── zshrc
```

## Package inventory

See [packages.md](packages.md) for a complete table of system packages, language tools, Neovim plugins, Mason-managed tools, formatters, and Treesitter parsers.

## Notes

- Safe to re-run across macOS and Rocky/RHEL.
- Some tools may come via cargo/npm/uv on Linux if dnf lacks them.
- `cargo install` won't upgrade existing crates; re-runs are idempotent.
- opencode `service.json` is runtime state and not symlinked.
- `gopls` installed by nvim/mason.
