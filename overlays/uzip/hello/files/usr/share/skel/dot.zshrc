# Lines configured by zsh-newuser-install
HISTFILE=~/.histfile
HISTSIZE=1000
SAVEHIST=1000
bindkey -e
# End of lines configured by zsh-newuser-install
# The following lines were added by compinstall
zstyle :compinstall filename '/home/liveuser/.zshrc'

autoload -Uz compinit
compinit
# End of lines added by compinstall

# Fix 'Delete' key in zsh
bindkey "^[[3~" delete-char

# Do not leak these environment variables to child processes
unset LAUNCHED_BUNDLE
unset LAUNCHED_EXECUTABLE

# Get cwd into window title of QTerminal
# As a side effect, it also shows up in the command line prompt
PROMPT=$'\e]0;%~\a%n@%m:%~ $ '
