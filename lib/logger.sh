#!/bin/bash
# logger.sh - Logging utilities for loglyze

# Make sure colors are loaded
if [[ -z "$RED" ]]; then
    # shellcheck disable=SC1091
    source "$(dirname "${BASH_SOURCE[0]}")/colors.sh"
fi

# Default verbosity level
# 0 = Quiet (errors only)
# 1 = Normal (errors, warnings, info)
# 2 = Verbose (errors, warnings, info, debug)
VERBOSITY=1

# Set verbosity level
set_verbosity() {
    VERBOSITY=$1
}

# Log a debug message (only shown in verbose mode)
log_debug() {
    [[ $VERBOSITY -ge 2 ]] && echo -e "${CYAN}[DEBUG]${NC} $*" >&2
}

# Log an info message
log_info() {
    [[ $VERBOSITY -ge 1 ]] && echo -e "${GREEN}[INFO]${NC} $*" >&2
}

# Log a warning message
log_warning() {
    [[ $VERBOSITY -ge 1 ]] && echo -e "${YELLOW}[WARNING]${NC} $*" >&2
}

# Log an error message
log_error() {
    echo -e "${RED}[ERROR]${NC} $*" >&2
}

echo "Loading logger.sh library..."
echo "Logger library loaded successfully" 