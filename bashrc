# If not running interactively, don't do anything (leave this at the top of this file)
[[ $- != *i* ]] && return

# ==============================================================================
# PATH Configuration (consolidated)
# ==============================================================================
export PATH="$HOME/.local/bin:$HOME/.opencode/bin:$HOME/.bun/bin:$HOME/.lmstudio/bin:/usr/local/bin:/usr/bin:$PATH"

# ==============================================================================
# History Settings
# ==============================================================================
HISTSIZE=10000
HISTFILESIZE=20000
HISTCONTROL=ignoreboth:erasedups
shopt -s histappend

# ==============================================================================
# Shell Options
# ==============================================================================
shopt -s cdspell      # Autocorrect minor spelling errors in cd
shopt -s dirspell     # Autocorrect directory names during completion
shopt -s autocd       # Type directory name to cd into it

# ==============================================================================
# Sources
# ==============================================================================
source ~/.local/share/omarchy/default/bash/rc
source ~/.bash_completions/basecamp
. "$HOME/.cargo/env"

# ==============================================================================
# Tool Initialization
# ==============================================================================
# mise (version manager)
if command -v mise >/dev/null 2>&1; then
  eval "$(mise activate bash)"
fi

# bun
export BUN_INSTALL="$HOME/.bun"

# ==============================================================================
# Safety Nets
# ==============================================================================
alias rm="rm -i"
alias mv="mv -i"
alias cp="cp -i"

# ==============================================================================
# ls Aliases
# ==============================================================================
alias ls="ls --color=auto"
alias ll="ls -lah"
alias la="ls -A"

# ==============================================================================
# Directory Navigation
# ==============================================================================
alias ..="cd .."
alias ...="cd ../.."
alias ....="cd ../../.."
alias code="cd ~/code"

# ==============================================================================
# Git Aliases
# ==============================================================================
alias gs="git status"
alias ga="git add"
alias gaa="git add -A"
alias gd="git diff"
alias gp="git push"
alias gl="git pull"
alias gc="git checkout"
alias gco="git checkout"
alias gcm="git commit -m"
alias gb="git branch"
alias glog="git log --oneline --graph --decorate -10"
alias lg="lazygit"

# ==============================================================================
# Custom Aliases
# ==============================================================================
alias rpi-imager='env QT_STYLE_OVERRIDE= /usr/bin/rpi-imager'
alias danger="claude --dangerously-skip-permissions"
alias cdx="/home/matsilva/cmds/cdx"
alias getpw="$HOME/dotfiles/unlock-bw.sh"
alias basecamp=/home/matsilva/code/go/bc4/bc4

# ==============================================================================
# Utility Functions
# ==============================================================================

# Create and cd into directory
mkcd() { mkdir -p "$1" && cd "$1"; }

# Extract any archive
extract() {
  case "$1" in
    *.tar.bz2) tar xjf "$1" ;;
    *.tar.gz)  tar xzf "$1" ;;
    *.tar.xz)  tar xJf "$1" ;;
    *.zip)     unzip "$1" ;;
    *.gz)      gunzip "$1" ;;
    *.7z)      7z x "$1" ;;
    *) echo "Unknown archive format: $1" ;;
  esac
}

# Quick find file by name
ff() { find . -name "*$1*" 2>/dev/null; }

# Quick grep in files
qg() { grep -rn "$1" . 2>/dev/null; }
