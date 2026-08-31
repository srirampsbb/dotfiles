# ==============================================================================
# Shell & Navigation Aliases
# ==============================================================================
alias src='source ~/.zshrc'
alias zrc='nvim ~/.dotfiles/zsh/zshrc'
alias als='nvim ~/.dotfiles/zsh/aliases.zsh'
alias fns='nvim ~/.dotfiles/zsh/functions.zsh'
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
# Use gls on macOS (Coreutils) if present, otherwise fallback to standard ls
if type gls &>/dev/null; then
  alias ls="gls --color=auto"
  alias ll="gls -l --color=auto"
  alias la="gls -A --color=auto"
  alias l="gls -lrt --color=auto"
else
  alias ls="ls --color=auto"
  alias ll="ls -l --color=auto"
  alias la="ls -A --color=auto"
  alias l="ls -lrt --color=auto"
fi

# herdr
alias tm='herdr'
alias tmn='herdr'
alias her='herdr'
alias hrc='nvim ~/.config/herdr/config.toml'

# Always use Neovim instead of Vim or Vi
alias vim="nvim"
alias vi="nvim"
alias nv="nvim"
alias nvi="nvim /Users/sriram.ravichandran/.dotfiles/config/nvim/init.lua"

# ==============================================================================
# Git Aliases
# ==============================================================================
alias gs='git status'
alias gsu='git status -uno'
alias gb='git branch'
alias gd='git diff HEAD'
alias gc='git commit -a'
alias ga='git add .'
alias gpull='git pull --rebase'
alias gpush='git push'
alias gcafp='git commit -a --amend --no-edit && git push -f'
alias gl='git log --oneline -n'
alias gco='git checkout'
alias gwr='git worktree remove'

