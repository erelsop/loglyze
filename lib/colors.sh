#!/bin/bash
# colors.sh - Terminal color definitions for loglyze

# Use explicit escape character for better control
ESC=$(printf '\033')

# ANSI color codes with explicit escaping
export RED="${ESC}[0;31m"
export GREEN="${ESC}[0;32m"
export YELLOW="${ESC}[0;33m"
export BLUE="${ESC}[0;34m"
export MAGENTA="${ESC}[0;35m"
export CYAN="${ESC}[0;36m"
export WHITE="${ESC}[0;37m"
export GRAY="${ESC}[0;90m"
export BOLD="${ESC}[1m"
export NC="${ESC}[0m" # No Color

# Function to enable or disable colors
enable_colors() {
    if [[ $1 == "false" ]]; then
        RED=''
        GREEN=''
        YELLOW=''
        BLUE=''
        MAGENTA=''
        CYAN=''
        WHITE=''
        GRAY=''
        BOLD=''
        NC=''
    fi
}

# Check if the terminal supports colors
if [[ -t 1 ]] && [[ -n "$TERM" ]] && [[ "$TERM" != "dumb" ]]; then
    USE_COLORS=true
else
    USE_COLORS=false
    enable_colors $USE_COLORS
fi 