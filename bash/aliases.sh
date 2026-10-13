# ==============================================================================
# Shell & Navigation Aliases (bash)
# ------------------------------------------------------------------------------
# Derived from zsh/aliases.zsh, minus the zsh-specific aliases (src, zreset,
# zrc, als). Keep this file to plain, POSIX/bash-compatible alias syntax so it
# stays safe to source from ~/.bashrc.
# ==============================================================================
alias h='history'
alias p='pwd'
alias cl='clear'
alias rl='readlink -f'
# Directory Navigation
alias u='cd ..'
alias uu='cd ../../'
alias uuu='cd ../../../'
alias uuuu='cd ../../../../'
alias uuuuu='cd ../../../../../'

# Listing Options (GNU gls)
alias ll="eza -l"
alias l="eza"
alias cat="bat"
alias fe="yazi"
# herdr
alias tm='herdr'
alias tmn='herdr'
alias hr='herdr'
alias hrc='nvim ~/.config/herdr/config.toml'

# Always use Neovim instead of Vim or Vi
alias vim="nvim"
alias vi="nvim"
alias nv="nvim"
alias nvc="nvim ~/.dotfiles/config/nvim/init.lua"

# ==============================================================================
# Git Aliases
# ==============================================================================
alias gs='git status'
alias gsu='git submodule update --init --recursive'
alias gb='git branch'
alias gd='git diff HEAD'
alias gc='git commit -a'
alias ga='git add .'
alias gpull='git pull --rebase'
alias gpush='git push'
alias gcafp='git commit -a --amend --no-edit && git push -f'
alias gl='git log --oneline -n'
alias gco='git checkout'

# wezterm
alias wzc='nvim ~/.config/wezterm/wezterm.lua'
