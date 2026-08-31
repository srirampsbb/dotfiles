# ==============================================================================
# ENVIRONMENT & PATH CONFIGURATION
# ==============================================================================
export LANG="en_US.UTF-8"
export GPG_TTY=$(tty)

# Construct PATH systematically
typeset -U path  # Keep PATH entries unique (no duplicates)
path=(
  /opt/homebrew/bin
  /opt/homebrew/opt/coreutils/libexec/gnubin
  /opt/homebrew/opt/postgresql@17/bin
  /Library/Java/JavaVirtualMachines/openjdk-21.jdk/Contents/Home/bin
  /usr/local/bin
  /usr/local/go/bin
  "$HOME/go/bin"
  "$HOME/.cargo/bin"
  "$HOME/.local/bin"
  "$HOME/bin"
  $path
)

# ==============================================================================
# PROMPT & COMPLETIONS
# ==============================================================================
export PROMPT='%F{248}%D{%m/%d} %F{244}%* %F{39}%~ %F{13}%# %f'

# Initialize Homebrew completions
if type brew &>/dev/null; then
  FPATH="$(brew --prefix)/share/zsh-completions:$FPATH"
  autoload -Uz compinit && compinit
fi

# Completion Styles
zstyle ':completion:*' matcher-list 'm:{a-zA-Z}={A-Za-z}' # Case-insensitive
zstyle ':completion:*' menu select                      # Interactive menu

# Directory Colors
if [[ -f "$HOME/.dircolors" ]]; then
  eval "$(gdircolors -b "$HOME/.dircolors")"
fi

# FZF integration
if command -v fzf &>/dev/null; then
  source <(fzf --zsh)
fi

### MANAGED BY RANCHER DESKTOP START (DO NOT EDIT)
export PATH="/Users/sriram.ravichandran/.rd/bin:$PATH"
### MANAGED BY RANCHER DESKTOP END (DO NOT EDIT)

# ==============================================================================
# SOURCE DOTFILES & MODULES
# ==============================================================================
# Load general personal zsh files
for file in "$HOME/.dotfiles/zsh"/*.zsh; do
  [[ -r "$file" ]] && source "$file"
done

# Load Nutanix local overrides (*ntnx*.zsh)
if [[ -d "$HOME/.dotfiles/zsh/local" ]]; then
  for file in "$HOME/.dotfiles/zsh/local"/*ntnx*.zsh; do
    [[ -r "$file" ]] && source "$file"
  done
fi

# ==============================================================================
# ZSH PLUGINS (MUST BE AT THE VERY END)
# ==============================================================================
# Autosuggestions
if [ -f "$(brew --prefix)/share/zsh-autosuggestions/zsh-autosuggestions.zsh" ]; then
  source "$(brew --prefix)/share/zsh-autosuggestions/zsh-autosuggestions.zsh"
fi

# Syntax Highlighting
if [ -f "$(brew --prefix)/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh" ]; then
  source "$(brew --prefix)/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh"
fi
