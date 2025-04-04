#!/usr/bin/env bash
#
# Core functionality for loglyze
# Provides logging, error handling, and other essential functions

# Set error handling
set -e

# Colors for terminal output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[0;33m'
readonly CYAN='\033[0;36m'
readonly NC='\033[0m' # No Color

# Fix for CONFIG_DIR that might not be set when sourced
if [[ -z "$CONFIG_DIR" ]]; then
    # Try to determine based on script location
    SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
    CONFIG_DIR="$( cd "$SCRIPT_DIR/../config" && pwd 2>/dev/null || echo "$SCRIPT_DIR/../config" )"
    echo "CONFIG_DIR not set, using: $CONFIG_DIR" >&2
fi

# Global configuration
CONFIG_FILE="${CONFIG_DIR}/loglyze.conf"
VERBOSE=${VERBOSE:-false}

# Check if CONFIG_FILE exists
if [[ ! -f "$CONFIG_FILE" ]]; then
    echo "Warning: Config file not found at $CONFIG_FILE" >&2
fi

# Logging functions
log_debug() {
    [[ "$VERBOSE" == true ]] && echo -e "${CYAN}[DEBUG]${NC} $*" >&2
}

log_info() {
    echo -e "${GREEN}[INFO]${NC} $*" >&2
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $*" >&2
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $*" >&2
}

# Error handling
handle_error() {
    local exit_code=$1
    local error_message=$2
    log_error "${error_message}"
    exit "${exit_code}"
}

# Load configuration
load_config() {
    if [[ -f "$CONFIG_FILE" ]]; then
        log_debug "Loading configuration from ${CONFIG_FILE}"
        # shellcheck source=/dev/null
        source "$CONFIG_FILE"
    else
        log_debug "No configuration file found, using defaults"
    fi
}

# Generate a summary of the log file
generate_summary() {
    local log_file=$1
    
    log_info "Generating summary for ${log_file}"
    
    # Basic statistics
    local total_lines
    local error_count
    local warning_count
    local info_count
    
    total_lines=$(wc -l < "$log_file")
    error_count=$(grep -ci "error" "$log_file" || echo 0)
    warning_count=$(grep -ci "warn" "$log_file" || echo 0)
    info_count=$(grep -ci "info" "$log_file" || echo 0)
    
    # Time range detection (basic implementation, will be improved)
    local first_timestamp
    local last_timestamp
    
    # Try to find timestamps in common formats
    # This is a basic implementation and will be enhanced in the parser module
    first_timestamp=$(grep -oE '[0-9]{4}-[0-9]{2}-[0-9]{2}[T ][0-9]{2}:[0-9]{2}:[0-9]{2}' "$log_file" | head -1)
    last_timestamp=$(grep -oE '[0-9]{4}-[0-9]{2}-[0-9]{2}[T ][0-9]{2}:[0-9]{2}:[0-9]{2}' "$log_file" | tail -1)
    
    # Display summary
    echo "=== Log Summary ==="
    echo "File: ${log_file}"
    echo "Total Lines: ${total_lines}"
    echo "Error Count: ${error_count}"
    echo "Warning Count: ${warning_count}"
    echo "Info Count: ${info_count}"
    echo -e "Time Range: ${first_timestamp:-Unknown} to ${last_timestamp:-Unknown}\n"
    
    # Top 5 most frequent errors
    echo "=== Top 5 Frequent Errors ==="
    grep -i "error" "$log_file" | sort | uniq -c | sort -nr | head -5 | while read -r count message; do
        echo "  ${count} occurrences: ${message}"
    done
    echo ""
}

# Initialize the loglyze environment
init_environment() {
    # Ensure required directories exist
    if [[ -d "${CONFIG_DIR}" ]]; then
        log_debug "Config directory exists: ${CONFIG_DIR}"
    else
        echo "Warning: Config directory does not exist: ${CONFIG_DIR}" >&2
        mkdir -p "${CONFIG_DIR}" 2>/dev/null || true
    fi
    
    # Load configuration
    load_config
    
    # Set up any required environment variables
    export LC_ALL=C
    
    log_debug "Environment initialized"
}

echo "Core library loaded successfully" >&2
# Call init_environment when this script is sourced
init_environment 