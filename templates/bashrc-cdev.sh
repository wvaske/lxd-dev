# =============================================================================
# Claude Code Development Environment - Shell Configuration
# =============================================================================
# This file is appended to ~/.bashrc in cdev containers

# Colored prompt with git branch
__git_branch() {
    local branch
    branch=$(git symbolic-ref --short HEAD 2>/dev/null || git describe --tags --exact-match 2>/dev/null)
    [[ -n "$branch" ]] && echo " ($branch)"
}

# Only set prompt if interactive
if [[ $- == *i* ]]; then
    # Prompt: user@container:path (branch)$
    # Colors are hardcoded to avoid escaping issues
    PS1='\[\033[0;32m\]\u\[\033[0m\]@\[\033[0;36m\]\h\[\033[0m\]:\[\033[0;34m\]\w\[\033[0;33m\]$(__git_branch)\[\033[0m\]\$ '
fi

# Enable color support
export CLICOLOR=1
export LSCOLORS=GxFxCxDxBxegedabagaced
export GCC_COLORS='error=01;31:warning=01;35:note=01;36:caret=01;32:locus=01:quote=01'

if [ -x /usr/bin/dircolors ]; then
    test -r ~/.dircolors && eval "$(dircolors -b ~/.dircolors)" || eval "$(dircolors -b)"
    alias ls='ls --color=auto'
    alias grep='grep --color=auto'
    alias fgrep='fgrep --color=auto'
    alias egrep='egrep --color=auto'
    alias diff='diff --color=auto'
fi

# Aliases - file listing
alias ll='ls -alF --color=auto'
alias la='ls -A --color=auto'
alias l='ls -CF --color=auto'

# Aliases - git
alias gs='git status'
alias gd='git diff'
alias gds='git diff --staged'
alias gc='git commit'
alias gca='git commit --amend'
alias gp='git push'
alias gpl='git pull'
alias gl='git log --oneline -20'
alias glo='git log --oneline --graph --all -20'
alias gco='git checkout'
alias gb='git branch'
alias gba='git branch -a'

# Aliases - navigation
alias ..='cd ..'
alias ...='cd ../..'
alias ....='cd ../../..'

# Aliases - safety
alias rm='rm -i'
alias cp='cp -i'
alias mv='mv -i'

# Better history
export HISTSIZE=10000
export HISTFILESIZE=20000
export HISTCONTROL=ignoreboth:erasedups
export HISTTIMEFORMAT="%F %T "
shopt -s histappend

# Useful shell options
shopt -s checkwinsize   # Update LINES/COLUMNS after each command
shopt -s cdspell        # Autocorrect typos in cd
shopt -s dirspell 2>/dev/null  # Autocorrect directory names
shopt -s autocd 2>/dev/null    # cd into directory by typing its name
shopt -s globstar 2>/dev/null  # ** matches recursively

# Make less more friendly for non-text input files
[ -x /usr/bin/lesspipe ] && eval "$(SHELL=/bin/sh lesspipe)"

# Change to workspace on login (if exists)
if [[ -d ~/workspace ]]; then
    cd ~/workspace 2>/dev/null || true
fi
