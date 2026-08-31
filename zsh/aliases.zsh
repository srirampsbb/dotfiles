# ==============================================================================
# Shell & Navigation Aliases
# ==============================================================================
alias src='source ~/.dotfiles/zsh/.zshrc'
alias zrc='nvim ~/.dotfiles/zsh/.zshrc'
alias als='nvim ~/.dotfiles/zsh/aliases.zsh'
alias fns='nvim ~/.dotfiles/zsh/functions.zsh'
alias h='history'
alias p='pwd'
alias cl='clear'
alias rl='readlink -f'

# Directory Navigation
alias cdr='cd ~/code/repos'
alias cdw='cd ~/code/worktrees'
alias u='cd ..'
alias uu='cd ../../'
alias uuu='cd ../../../'
alias uuuu='cd ../../../../'
alias uuuuu='cd ../../../../../'

# Listing Options (GNU gls)
alias ls='gls --color=auto'
alias ll='gls -l --color=auto'
alias la='gls -A --color=auto'
alias l='gls -lrt --color=auto'

# Tmux
alias tm='tmux attach -t Base'
alias tmn='tmux new -s Base'

# ==============================================================================
# Git Aliases
# ==============================================================================
alias gs='git status'
alias gsu='git status -uno'
alias gb='git branch'
alias gd='git diff HEAD'
alias gdo='git diff origin/main'
alias gr='git remote show origin'
alias gc='git commit -a'
alias ga='git add .'
alias gpull='git pull --rebase'
alias gpush='git push'
alias gcafp='git commit -a --amend --no-edit && git push -f'
alias gl='git log --oneline -n'
alias gln='git log -n'
alias gco='git checkout'
alias gwl='git worktree list'
alias gwr='git worktree remove'

