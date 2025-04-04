#!/bin/bash
#
# Interactive mode module for loglyze
# Provides an interactive interface for exploring log files

# TODO: Severity patterns not being properly extracted during export
# TODO: Add support for stacking filters (need visual indicator)


# Get the script directory
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

# Source libraries
# shellcheck disable=SC1091
source "$SCRIPT_DIR/time_utils.sh"

# Initialize default values
DEBUG_MODE=0

# Check if script is being executed (not sourced)
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    # Process command line arguments
    for arg in "$@"; do
        case $arg in
            --debug)
                DEBUG_MODE=1
                ;;
        esac
    done
    
    echo "Time utils library loaded successfully"
    
    # Log debug information
    [[ $DEBUG_MODE -eq 1 ]] && log_debug "Interactive mode module has been completely loaded"
fi

# Make sure we have colors
if [[ -z "$RED" && -f "$SCRIPT_DIR/colors.sh" ]]; then
    # shellcheck disable=SC1091
    source "$SCRIPT_DIR/colors.sh"
fi

# Default color fallbacks if still not defined
if [[ -z "$RED" ]]; then
    RED='\033[0;31m'
    YELLOW='\033[0;33m'
    BLUE='\033[0;34m'
    NC='\033[0m' # No Color
fi

# Default timestamp patterns if time_utils wasn't loaded
if [[ -z "$TIMESTAMP_PATTERNS" ]]; then
    declare -a TIMESTAMP_PATTERNS
    TIMESTAMP_PATTERNS=(
        '[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}(\.[0-9]+)?([+-][0-9]{2}:[0-9]{2}|Z)?'  # ISO 8601 with T and optional ms/tz
        '[0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}:[0-9]{2}(\.[0-9]+)?'  # ISO 8601 with space and optional ms
        '[A-Za-z]{3} [A-Za-z]{3} [0-9 ]{2} [0-9]{2}:[0-9]{2}:[0-9]{2} [0-9]{4}'  # Syslog
        '[0-9]{2}/[0-9]{2}/[0-9]{4} [0-9]{2}:[0-9]{2}:[0-9]{2}'  # MM/DD/YYYY HH:MM:SS
    )
fi

# Default severity patterns if not defined
if [[ -z "$SEVERITY_PATTERNS" ]]; then
    declare -a SEVERITY_PATTERNS
    SEVERITY_PATTERNS=(
        'ERROR|WARN|INFO|DEBUG|TRACE|FATAL'  # Common log levels
        'CRITICAL|NOTICE|WARNING'  # Additional log levels
        'ERR|EMERG|ALERT|CRIT|NOTICE'  # Syslog severity levels
    )
fi

# Variables for interactive mode
declare -a FILTERED_LOGS
current_page=1
entries_per_page=40
current_filter=""
current_search=""
original_terminal_settings=""

# Variables for stacking filters
declare -a ACTIVE_FILTERS=()
ERRORS_ONLY="false"

# Define a helper function for clearing the screen safely
clear_screen() {
    # Check if terminal is in a sane state before clearing
    tput clear 2>/dev/null || clear
    
    # Reset cursor position to top-left
    tput cup 0 0 2>/dev/null || echo -e "\033[H"
}

# Initialize interactive mode
init_interactive_mode() {
    log_debug "Initializing interactive mode"
    
    # Save original terminal settings
    original_terminal_settings=$(stty -g)
    
    # Set terminal settings for interactive mode
    # Don't use raw mode - it can interfere with text alignment
    # Just disable echo for single key input
    stty -echo
    
    # Hide cursor
    echo -e "\033[?25l"
    
    # Clear screen
    clear_screen
    
    # Simple left-aligned output without any centering
    echo "================================================"
    echo "Welcome to LogLyze Interactive Mode"
    echo "================================================"
    echo
    echo "This mode allows you to explore and analyze log files interactively."
    echo "You can navigate, filter, search, and export log data with simple keystrokes."
    echo
    
    # Use tput instead of ANSI codes for colors
    tput setaf 3 # Yellow
    echo "Key Features:"
    tput sgr0 # Reset
    
    echo "- Navigate with arrow keys or j/k"
    echo "- Filter logs by text (f), errors only (e), or time range (r)"
    echo "- Search within logs (/) and jump between matches (n/p)"
    echo "- Export current view to CSV (x)"
    echo "- View detailed help with 'h' key"
    echo
    
    tput setaf 3 # Yellow
    echo "Keyboard Shortcuts:"
    tput sgr0 # Reset
    
    echo "- Use h for help"
    echo "- Use q to quit"
    echo
    echo "Press any key to continue to interactive mode..."
    
    # Wait for keypress
    read -r -n 1 -s
}

# Clean up when exiting interactive mode
cleanup_interactive_mode() {
    log_debug "Cleaning up interactive mode"
    
    # Show cursor
    echo -e "\033[?25h"
    
    # Return to normal terminal mode
    # Reset colors first
    tput sgr0
    
    # Clear the current line
    tput el
    
    # Restore terminal settings if we saved them
    if [[ -n "$original_terminal_settings" ]]; then
        stty "$original_terminal_settings"
    else
        # Fallback if we don't have original settings
        stty sane
    fi
    
    # Re-enable echo
    stty echo
    
    # Clean exit message
    clear_screen
    tput setaf 6 # Cyan
    echo "Thank you for using LogLyze!"
    tput sgr0 # Reset
    echo
    
    log_debug "Interactive mode cleanup complete"
}

# Display help information
show_help() {
    clear
    echo -e "${BLUE}=== Loglyze Interactive Mode Help ===${NC}"
    echo -e "${YELLOW}Navigation:${NC}"
    echo -e "  Up/Down Arrow: Scroll through entries"
    echo -e "  PageUp/PageDown: Jump multiple entries"
    echo -e "  Home/End: Go to beginning/end of log"
    echo -e ""
    echo -e "${YELLOW}Filtering:${NC}"
    echo -e "  e: Show only ERROR entries"
    echo -e "  w: Show only WARNING entries"
    echo -e "  i: Show only INFO entries"
    echo -e "  a: Show all entries (clear filters)"
    echo -e "  f: Filter by time range"
    echo -e ""
    echo -e "${YELLOW}Searching:${NC}"
    echo -e "  /: Search for a pattern"
    echo -e "  n: Next search result"
    echo -e "  p: Previous search result"
    echo -e ""
    echo -e "${YELLOW}Time Navigation:${NC}"
    echo -e "  t: Jump to specific timestamp"
    echo -e ""
    echo -e "${YELLOW}Actions:${NC}"
    echo -e "  s: Show summary statistics"
    echo -e "  c: Export current view to CSV"
    echo -e "  q: Quit interactive mode"
    echo -e ""
    echo -e "${BLUE}----------------------------------------${NC}"
    echo -e "Press any key to return..."
    read -r -n 1
}

# Load log file into memory with optional filtering
load_log_file() {
    local log_file=$1
    local filter=$2
    
    log_debug "Loading log file '$log_file' with filter: '$filter'"
    
    # Check if file exists
    if [[ ! -f "$log_file" ]]; then
        log_error "File not found: $log_file"
        return 1
    fi
    
    # Reset array and make sure it's explicitly an array
    unset FILTERED_LOGS
    declare -ga FILTERED_LOGS=()
    
    # Count lines in the file first
    local total_lines
    total_lines=$(wc -l < "$log_file")
    log_debug "Total lines in log file: $total_lines"
    
    # If the file is large, use a more efficient approach
    if [[ $total_lines -gt 10000 ]]; then
        log_debug "Large file detected, using efficient loading approach"
        
        # Use grep for filtering if a filter is specified
        if [[ -n "$filter" ]]; then
            mapfile -t FILTERED_LOGS < <(grep -i "$filter" "$log_file")
        else
            # Load whole file efficiently
            mapfile -t FILTERED_LOGS < "$log_file"
        fi
    else
        # Standard approach for smaller files - read line by line
        local line
        while IFS= read -r line; do
            if [[ -n "$filter" ]]; then
                if grep -qi "$filter" <<< "$line"; then
                    FILTERED_LOGS+=("$line")
                fi
            else
                FILTERED_LOGS+=("$line")
            fi
        done < "$log_file"
    fi
    
    log_debug "Loaded ${#FILTERED_LOGS[@]} entries from log file"
    
    # Reset page
    current_page=1
    
    # Return success status
    return 0
}

# Function to safely execute grep with extended regex
safe_grep() {
    local pattern="$1"
    local input="$2"
    local options="$3"
    
    # Handle empty input gracefully
    if [[ -z "$input" ]]; then
        return 1
    fi
    
    # Escape special characters for literal searches
    # Only do this for simple text searches, not when using regex options
    if [[ ! "$options" =~ "E" && ! "$options" =~ "P" ]]; then
        local escaped_pattern
        # Replace special regex characters with their escaped versions using bash parameter expansion
        escaped_pattern="${pattern//\\/\\\\}"  # Escape backslashes first
        escaped_pattern="${escaped_pattern//\./\\.}"
        escaped_pattern="${escaped_pattern//\*/\\*}"
        escaped_pattern="${escaped_pattern//\+/\\+}"
        escaped_pattern="${escaped_pattern//\?/\\?}"
        escaped_pattern="${escaped_pattern//\(/\\(}"
        escaped_pattern="${escaped_pattern//\)/\\)}"
        escaped_pattern="${escaped_pattern//\{/\\{}"
        escaped_pattern="${escaped_pattern//\}/\\}}"
        escaped_pattern="${escaped_pattern//\[/\\[}"
        escaped_pattern="${escaped_pattern//\]/\\]}"
        escaped_pattern="${escaped_pattern//\^/\\^}"
        escaped_pattern="${escaped_pattern//\$/\\$}"
        escaped_pattern="${escaped_pattern//\|/\\|}"
        pattern="$escaped_pattern"
    fi
    
    # Use grep with here-string to avoid issues with large inputs
    if grep -E "${options}" "$pattern" <<< "$input" 2>/dev/null; then
        return 0
    else
        return 1
    fi
}

# Search for a pattern in the logs
search_logs() {
    local pattern="$1"
    local start_index="$2"
    local direction="${3:-forward}"
    
    log_debug "Searching for '$pattern' from index $start_index ($direction)"
    
    local i
    local result_index=255  # Default no match found
    
    if [[ "$direction" == "forward" ]]; then
        # Search forward
        for ((i=start_index; i<${#FILTERED_LOGS[@]}; i++)); do
            if echo "${FILTERED_LOGS[$i]}" | grep -q -i -F -- "$pattern"; then
                # Found a match
                result_index=$i
                break
            fi
        done
    else
        # Search backward
        for ((i=start_index; i>=0; i--)); do
            if echo "${FILTERED_LOGS[$i]}" | grep -q -i -F -- "$pattern"; then
                # Found a match
                result_index=$i
                break
            fi
        done
    fi
    
    return $result_index
}

# Draw command help bar at the bottom of the screen
draw_command_bar() {
    # Get terminal height and width
    local term_height
    term_height=$(tput lines)
    local term_width
    term_width=$(tput cols)
    
    # Save cursor position
    tput sc
    
    # Move to the bottom of the screen (last line)
    tput cup $((term_height - 1)) 0
    
    # Set background to blue, text to white
    tput setab 4  # Blue background
    tput setaf 7  # White text
    
    # Create a help string with actual commands 
    local help_str="^Q Quit  ^H Help  f Filter  e Errors  t Time  g GoTo  x Export  r Range  c Clear  s Summary  ↑↓/j/k Navigate"
    
    # Truncate help string if it's too long for the terminal width
    if (( ${#help_str} > term_width )); then
        help_str="${help_str:0:$((term_width - 3))}..."
    fi
    
    # Fill the entire line with spaces (to color the background)
    printf "%-${term_width}s" " "
    
    # Move cursor back to start of line and print the help string
    tput cup $((term_height - 1)) 0
    printf "%s" "$help_str"
    
    # Reset colors
    tput sgr0
    
    # Restore cursor position
    tput rc
}

# Display logs with pagination
display_logs() {
    local current_page=$1
    local total_pages=$2
    local show_page_summary=${3:-true}  # Show page summary by default
    
    # Calculate range
    local start_idx=$(( (current_page - 1) * entries_per_page ))
    local end_idx=$(( start_idx + entries_per_page - 1 ))
    
    # Make sure end_idx doesn't exceed array bounds
    if [[ $end_idx -ge ${#FILTERED_LOGS[@]} ]]; then
        end_idx=$(( ${#FILTERED_LOGS[@]} - 1 ))
    fi
    
    # Clear screen
    clear_screen
    
    # Display simple left-aligned header
    tput setaf 4 # Blue
    echo "=== LogLyze Interactive Mode ==="
    tput sgr0 # Reset
    
    tput setaf 2 # Green
    echo -n "Showing page $current_page"
    tput sgr0 # Reset
    
    echo -n " of "
    
    tput setaf 2 # Green
    echo -n "$total_pages"
    tput sgr0 # Reset
    
    echo " (${#FILTERED_LOGS[@]} entries)"
    
    # Show a message if we have active filters
    local active_filters=""
    
    # Build a description of active filters
    if [[ ${#ACTIVE_FILTERS[@]} -gt 0 ]]; then
        for filter in "${ACTIVE_FILTERS[@]}"; do
            [[ -n "$active_filters" ]] && active_filters+=", "
            active_filters+="$filter"
        done
    fi
    
    if [[ -n "$active_filters" ]]; then
        echo -n "Active filters: "
        tput setaf 3 # Yellow
        echo "$active_filters"
        tput sgr0 # Reset
    fi
    
    # If showing page summary
    if [[ "$show_page_summary" == "true" ]]; then
        # Calculate page-specific summary
        local page_errors=0
        local page_warnings=0
        local page_info=0
        
        for ((i=start_idx; i<=end_idx; i++)); do
            if [[ $i -ge ${#FILTERED_LOGS[@]} ]]; then
                break
            fi
            
            local line="${FILTERED_LOGS[$i]}"
            
            # Count errors, warnings, and info messages
            if [[ "$line" =~ [Ee][Rr][Rr][Oo][Rr] ]]; then
                ((page_errors++))
            elif [[ "$line" =~ [Ww][Aa][Rr][Nn] ]]; then
                ((page_warnings++))
            elif [[ "$line" =~ [Ii][Nn][Ff][Oo] ]]; then
                ((page_info++))
            fi
        done
        
        echo -n "Current page summary: "
        
        tput setaf 1 # Red
        echo -n "Errors: $page_errors"
        tput sgr0 # Reset
        
        echo -n ", "
        
        tput setaf 3 # Yellow
        echo -n "Warnings: $page_warnings"
        tput sgr0 # Reset
        
        echo -n ", "
        
        tput setaf 2 # Green
        echo -n "Info: $page_info"
        tput sgr0 # Reset
        
        echo
    fi
    
    echo "" # Empty line before log entries
    
    # Display logs
    for ((i=start_idx; i<=end_idx; i++)); do
        if [[ $i -lt ${#FILTERED_LOGS[@]} ]]; then
            local line="${FILTERED_LOGS[$i]}"
            
            # Calculate line number
            local line_num=$(( i + 1 ))
            
            # Pad line number for alignment
            local line_num_padded
            printf -v line_num_padded "%4d" "$line_num"
            
            # Determine color based on severity
            if [[ "$line" =~ [Ee][Rr][Rr][Oo][Rr] ]]; then
                echo -n "$line_num_padded: "
                tput setaf 1 # Red
                echo "$line"
                tput sgr0 # Reset
            elif [[ "$line" =~ [Ww][Aa][Rr][Nn] ]]; then
                echo -n "$line_num_padded: "
                tput setaf 3 # Yellow
                echo "$line"
                tput sgr0 # Reset
            elif [[ "$line" =~ [Ii][Nn][Ff][Oo] ]]; then
                echo -n "$line_num_padded: "
                tput setaf 2 # Green
                echo "$line"
                tput sgr0 # Reset
            elif [[ "$line" =~ [Dd][Ee][Bb][Uu][Gg] ]]; then
                echo -n "$line_num_padded: "
                tput setaf 4 # Blue
                echo "$line"
                tput sgr0 # Reset
            else
                echo "$line_num_padded: $line"  # Plain text
            fi
        fi
    done
    
    # Draw the command bar at the bottom
    draw_command_bar
}

# Read input from user with enhanced visibility
read_input() {
    local prompt="$1"
    local input=""
    
    # Move cursor to known position
    tput cup 5 0
    tput el
    
    # Display prompt with clear visual indication
    tput bold
    tput setaf 3 # Yellow
    echo -e "$prompt"
    tput sgr0 # Reset
    
    # Create an input line with background for visibility
    tput setaf 0 # Black text
    tput setab 7 # White background
    echo -n "► "
    
    # Show cursor and enable echo for input
    tput cnorm
    stty echo
    
    # Read the input with proper handling
    read -r input
    
    # Hide cursor again and disable echo
    tput civis
    stty -echo
    
    # Reset colors
    tput sgr0
    
    # Debug what was received
    log_debug "User input received: '$input'"
    
    # Return the input
    echo "$input"
}

# Display an error message with visual emphasis
show_error() {
    local message="$1"
    local pause_time="${2:-2}"  # Default pause of 2 seconds
    
    # Clear screen for visibility
    clear_screen
    
    # Show error in a visible format
    tput setaf 1 # Red
    echo "╔═════════════════════════════ ERROR ═════════════════════════════╗"
    echo "║                                                                 ║"
    printf "║ %-65s ║\n" "$message"
    echo "║                                                                 ║"
    echo "╚═════════════════════════════════════════════════════════════════╝"
    tput sgr0 # Reset
    
    echo
    echo "Press any key to continue..."
    
    # Wait for keypress or timeout
    read -r -n 1 -t "$pause_time" -s
}

# Display a success message with visual emphasis
show_success() {
    local message="$1"
    local pause_time="${2:-1}"  # Default pause of 1 second
    
    # Clear screen for visibility
    clear_screen
    
    # Show success in a visible format
    tput setaf 2 # Green
    echo "╔═════════════════════════════ SUCCESS ═══════════════════════════╗"
    echo "║                                                                 ║"
    printf "║ %-65s ║\n" "$message"
    echo "║                                                                 ║"
    echo "╚═════════════════════════════════════════════════════════════════╝"
    tput sgr0 # Reset
    
    # Pause to ensure message is seen
    sleep "$pause_time"
}

# Filter logs by text with better feedback
filter_by_text() {
    local log_file="$LOG_FILE"  # Use the global LOG_FILE variable
    
    # Clear screen
    clear_screen
    echo -e "${BLUE}=== Text Filter ===${NC}\n"
    
    # Show currently active filters if any
    if [[ ${#ACTIVE_FILTERS[@]} -gt 0 ]]; then
        echo -e "${YELLOW}Currently active filters:${NC}"
        for filter in "${ACTIVE_FILTERS[@]}"; do
            echo "- $filter"
        done
        echo
    fi
    
    # Get filter text directly - don't use the read_input function
    echo "Enter text to filter by (case-insensitive):"
    echo -n "> "
    stty echo
    read -r filter_text
    stty -echo
    
    if [[ -z "$filter_text" ]]; then
        show_error "No filter text provided. Keeping current view."
        return 0
    fi
    
    # Log what we're searching for
    log_debug "Filtering by text: '$filter_text'"
    
    # Create a new array for filtered entries
    local temp_filtered=()
    
    # Show processing message
    clear_screen
    echo "Filtering logs containing \"$filter_text\"..."
    echo
    
    # For stacking filters: Apply new filter to FILTERED_LOGS instead of original file
    # if filters are already active
    local source_data=()
    
    if [[ ${#ACTIVE_FILTERS[@]} -gt 0 ]]; then
        # Use current filtered logs as source for stacking
        source_data=("${FILTERED_LOGS[@]}")
        echo "Applying filter to already filtered data (${#source_data[@]} entries)..."
    else
        # First filter, use the whole log file
        if [[ -s "$log_file" ]]; then
            mapfile -t source_data < "$log_file"
        else
            # Fallback - use ALL_LOGS if file can't be read
            source_data=("${ALL_LOGS[@]}")
        fi
        echo "Applying filter to full dataset (${#source_data[@]} entries)..."
    fi
    
    # Create a temporary file for grep output to handle large logs efficiently
    local temp_file
    if ! temp_file=$(mktemp); then
        show_error "Failed to create temporary file for text filtering"
        return 1
    fi
    
    # Write source data to temp file
    printf '%s\n' "${source_data[@]}" > "$temp_file"
    
    # Simple grep-based filtering - read from the source data
    # Use -i for case-insensitive matching and --fixed-strings for literal text search
    if grep -i -F -- "$filter_text" "$temp_file" > "$temp_file.new"; then
        mapfile -t temp_filtered < "$temp_file.new"
    fi
    
    # Clean up
    rm -f "$temp_file" "$temp_file.new"
    
    # Update filtered logs and show feedback
    if [[ ${#temp_filtered[@]} -gt 0 ]]; then
        FILTERED_LOGS=("${temp_filtered[@]}")
        current_page=1
        
        # Add this filter to active filters list if not already present
        local filter_description="Text: \"$filter_text\""
        
        # Check if we already have a text filter
        local text_filter_index=-1
        for i in "${!ACTIVE_FILTERS[@]}"; do
            if [[ "${ACTIVE_FILTERS[i]}" == Text:* ]]; then
                text_filter_index=$i
                break
            fi
        done
        
        if [[ $text_filter_index -ge 0 ]]; then
            # Replace existing text filter
            ACTIVE_FILTERS[text_filter_index]="$filter_description"
        else
            # Add new text filter
            ACTIVE_FILTERS+=("$filter_description")
        fi
        
        # Store current filter text for metadata
        current_filter="$filter_text"
        
        # Recalculate total pages
        local total_pages
        total_pages=$(( (${#FILTERED_LOGS[@]} + entries_per_page - 1) / entries_per_page ))
        if [[ $total_pages -lt 1 ]]; then
            total_pages=1
        fi
        
        show_success "Found ${#FILTERED_LOGS[@]} entries containing \"$filter_text\"."
    else
        show_error "No entries found containing \"$filter_text\"."
    fi
    
    return 0
}

# Extract timestamp from a log line
extract_timestamp() {
    local line="$1"
    local ts=""
    
    # Try different timestamp formats in order of likelihood
    
    # 1. ISO 8601 format with timezone: YYYY-MM-DDThh:mm:ss.msec+00:00 or Z
    ts=$(echo "$line" | grep -oE '[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}(\.[0-9]+)?([+-][0-9]{2}:[0-9]{2}|Z)?' | head -1)
    if [[ -n "$ts" ]]; then
        # Extract just the date and time part, ignore milliseconds and timezone
        local base_ts
        if [[ "$ts" =~ ([0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}) ]]; then
            base_ts="${BASH_REMATCH[1]}"
            # Normalize timestamp by replacing T with space
            echo "${base_ts//T/ }"
            return 0
        fi
        # Fallback to simple replacement if regex didn't match
        echo "${ts//T/ }" | cut -d. -f1
        return 0
    fi
    
    # 2. RFC3339 variant used by some syslog implementations (Z for UTC)
    ts=$(echo "$line" | grep -oE '[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}(\.[0-9]+)?Z' | head -1)
    if [[ -n "$ts" ]]; then
        # Extract just the date and time part
        if [[ "$ts" =~ ([0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}) ]]; then
            echo "${BASH_REMATCH[1]//T/ }"
            return 0
        fi
        echo "${ts//T/ }" | cut -d. -f1 | sed 's/Z$//'
        return 0
    fi
    
    # 3. Standard ISO 8601 format: YYYY-MM-DD HH:MM:SS or YYYY-MM-DDThh:mm:ss
    ts=$(echo "$line" | grep -oE '[0-9]{4}-[0-9]{2}-[0-9]{2}[T ]?[0-9]{2}:[0-9]{2}:[0-9]{2}' | head -1)
    if [[ -n "$ts" ]]; then
        # Normalize timestamp by replacing T with space
        echo "${ts//T/ }"
        return 0
    fi
    
    # 4. Syslog format: MMM DD HH:MM:SS [Year]
    ts=$(echo "$line" | grep -oE '(Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)\s+[0-9]{1,2}\s+[0-9]{2}:[0-9]{2}:[0-9]{2}(\s+[0-9]{4})?' | head -1)
    if [[ -n "$ts" ]]; then
        # If year is not included, add current year
        if ! [[ "$ts" =~ [0-9]{4}$ ]]; then
            ts="$ts $(date +%Y)"
        fi
        echo "$ts"
        return 0
    fi
    
    # 5. MM/DD/YYYY HH:MM:SS format
    ts=$(echo "$line" | grep -oE '[0-9]{2}/[0-9]{2}/[0-9]{4}\s+[0-9]{2}:[0-9]{2}:[0-9]{2}' | head -1)
    if [[ -n "$ts" ]]; then
        echo "$ts"
        return 0
    fi
    
    # 6. Syslog timestamp with PID: MMM DD HH:MM:SS hostname process[pid]:
    ts=$(echo "$line" | grep -oE '(Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)\s+[0-9]{1,2}\s+[0-9]{2}:[0-9]{2}:[0-9]{2}' | head -1)
    if [[ -n "$ts" ]]; then
        # Add current year
        echo "$ts $(date +%Y)"
        return 0
    fi
    
    # 7. Unix timestamp (all digits)
    ts=$(echo "$line" | grep -oE '\b[0-9]{10,13}\b' | head -1)
    if [[ -n "$ts" ]]; then
        # Convert unix timestamp to human-readable format
        if [[ "${#ts}" -eq 13 ]]; then
            # Milliseconds timestamp, convert to seconds
            ts=$((ts / 1000))
        fi
        date -d "@$ts" "+%Y-%m-%d %H:%M:%S" 2>/dev/null
        return 0
    fi
    
    return 1
}

# Convert timestamp to epoch seconds
timestamp_to_epoch() {
    local timestamp="$1"
    local epoch=0
    
    # If empty, return error
    if [[ -z "$timestamp" ]]; then
        return 1
    fi
    
    # If it's already an epoch timestamp
    if [[ "$timestamp" =~ ^[0-9]+$ ]]; then
        # If it's milliseconds (13 digits), convert to seconds
        if [[ "${#timestamp}" -eq 13 ]]; then
            echo $((timestamp / 1000))
            return 0
        # If it's seconds (10 digits), use as is
        elif [[ "${#timestamp}" -eq 10 ]]; then
            echo "$timestamp"
            return 0
        fi
    fi
    
    # Handle ISO 8601 format with timezone and possibly milliseconds
    if [[ "$timestamp" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}(\.[0-9]+)?([+-][0-9]{2}:[0-9]{2}|Z)$ ]]; then
        # Use date with the ISO format including timezone
        if epoch=$(date -d "$timestamp" +%s 2>/dev/null); then
            echo "$epoch"
            return 0
        fi
    fi
    
    # Handle RFC3339 timestamps with Z suffix (UTC)
    if [[ "$timestamp" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}(\.[0-9]+)?Z$ ]]; then
        # Remove Z and milliseconds, replace T with space for date command
        local cleaned_ts
        cleaned_ts=$(echo "$timestamp" | sed -E 's/\.[0-9]+Z?$//' | sed 's/T/ /')
        if epoch=$(date -d "$cleaned_ts UTC" +%s 2>/dev/null); then
            echo "$epoch"
            return 0
        fi
    fi
    
    # Try a simple direct conversion
    if epoch=$(date -d "$timestamp" +%s 2>/dev/null); then
        echo "$epoch"
        return 0
    fi
    
    # Special handling for syslog format (Jan 23 14:59:32 2023)
    # Modify if month is at the beginning (syslog format)
    if [[ "$timestamp" =~ ^[A-Za-z]{3}\ +[0-9]{1,2}\ +[0-9]{1,2}:[0-9]{2}:[0-9]{2}(\ +[0-9]{4})?$ ]]; then
        # Add current year if year is missing
        if ! [[ "$timestamp" =~ [0-9]{4} ]]; then
            current_year=$(date +%Y)
            timestamp="$timestamp $current_year"
        fi
        
        if epoch=$(date -d "$timestamp" +%s 2>/dev/null); then
            echo "$epoch"
            return 0
        fi
    fi
    
    # If we reach here, all conversion attempts failed
    return 1
}

# Jump to a specific timestamp
jump_to_timestamp() {
    local log_file="$LOG_FILE"  # Use the global LOG_FILE variable
    
    # Clear screen
    clear_screen
    echo -e "${BLUE}=== Jump to Timestamp ===${NC}\n"
    echo "This will show logs on or after the specified timestamp."
    echo "Formats: YYYY-MM-DD or YYYY-MM-DD HH:MM:SS"
    echo

    # Get timestamp directly
    echo "Enter timestamp to jump to:"
    echo -n "> "
    stty echo
    read -r timestamp
    stty -echo

    # If empty, return without jumping
    if [[ -z "$timestamp" ]]; then
        show_error "No timestamp specified, keeping current view."
        return 0
    fi

    # Show processing message
    clear_screen
    echo "Searching for entries with timestamp >= $timestamp..."
    echo

    # Create a new temporary file for the filtered logs
    local temp_file
    if ! temp_file=$(mktemp); then
        show_error "Failed to create temporary file"
        return 1
    fi
    
    # If date-only format, adjust to beginning of day
    if [[ "$timestamp" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]]; then
        timestamp="${timestamp} 00:00:00"
    fi
    
    log_debug "Target timestamp: $timestamp"
    
    # Convert timestamp to epoch for comparison
    local target_epoch
    if ! target_epoch=$(timestamp_to_epoch "$timestamp"); then
        show_error "Invalid timestamp format: $timestamp"
        rm -f "$temp_file"
        return 1
    fi
    
    log_debug "Target epoch: $target_epoch"
    
    # Process the file line by line for timestamp comparison
    local filtered_count=0
    
    while IFS= read -r line; do
        # Extract timestamp using our helper function
        local ts
        if ! ts=$(extract_timestamp "$line"); then
            # If no timestamp found, include the line
            echo "$line" >> "$temp_file"
            ((filtered_count++))
            continue
        fi
        
        # Convert timestamp to epoch for comparison
        local line_epoch
        if ! line_epoch=$(timestamp_to_epoch "$ts"); then
            # If conversion fails, include the line
            echo "$line" >> "$temp_file"
            ((filtered_count++))
            continue
        fi
        
        # Check if the timestamp is >= target
        if [[ "$line_epoch" -ge "$target_epoch" ]]; then
            echo "$line" >> "$temp_file"
            ((filtered_count++))
        fi
    done < "$log_file"

    # Load the filtered logs into FILTERED_LOGS
    local temp_filtered=()
    mapfile -t temp_filtered < "$temp_file"

    # Clean up temporary file
    rm -f "$temp_file"

    # Update the filtered logs
    if [[ ${#temp_filtered[@]} -gt 0 ]]; then
        FILTERED_LOGS=("${temp_filtered[@]}")
        current_page=1
        
        # Add timestamp jump to active filters
        local filter_description="From time: $timestamp"
        
        # Check if we already have a timestamp filter
        local time_filter_index=-1
        for i in "${!ACTIVE_FILTERS[@]}"; do
            if [[ "${ACTIVE_FILTERS[i]}" == "From time:"* ]]; then
                time_filter_index=$i
                break
            fi
        done
        
        if [[ $time_filter_index -ge 0 ]]; then
            # Replace existing time filter
            ACTIVE_FILTERS[time_filter_index]="$filter_description"
        else
            # Add new time filter
            ACTIVE_FILTERS+=("$filter_description")
        fi
        
        # Recalculate total pages
        local total_pages
        total_pages=$(( (${#FILTERED_LOGS[@]} + entries_per_page - 1) / entries_per_page ))
        if [[ $total_pages -lt 1 ]]; then
            total_pages=1
        fi
        
        show_success "Found ${#FILTERED_LOGS[@]} entries with timestamp >= $timestamp"
    else
        show_error "No entries found with timestamp >= $timestamp"
    fi
}

# Filter logs by time range
filter_by_time_range() {
    local log_file="$LOG_FILE"  # Use the global LOG_FILE variable
    
    clear_screen
    echo -e "${BLUE}=== Filter by Time Range ===${NC}\n"
    echo "Filter logs between two timestamps."
    echo "Formats: YYYY-MM-DD or YYYY-MM-DD HH:MM:SS"
    echo "Leave input empty to use earliest/latest timestamps."
    echo

    # Get start timestamp
    echo "Enter start timestamp (or leave empty for earliest):"
    echo -n "> "
    stty echo
    read -r from_timestamp
    stty -echo

    # Get end timestamp
    echo "Enter end timestamp (or leave empty for latest):"
    echo -n "> "
    stty echo
    read -r to_timestamp
    stty -echo

    # Store timestamps globally so they can be accessed for metadata
    LOCAL_FROM_TIME="$from_timestamp"
    LOCAL_TO_TIME="$to_timestamp"

    # Show processing message
    clear_screen
    echo "Filtering logs within time range..."
    echo

    # Create a temporary file for the filtered logs
    local temp_file
    if ! temp_file=$(mktemp); then
        show_error "Failed to create temporary file"
        return 1
    fi

    # If no timestamps provided, just copy all logs
    if [[ -z "$from_timestamp" && -z "$to_timestamp" ]]; then
        # Use the original logs
        cat "$log_file" > "$temp_file"
        FILTERED_LOGS=("${ALL_LOGS[@]}")
        show_success "No time range specified. Showing all entries."
        return 0
    fi

    # Simple filtering approach using grep and date command for comparison
    local filtered_count=0
    
    # If date-only format, adjust to beginning/end of day
    if [[ -n "$from_timestamp" && "$from_timestamp" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]]; then
        from_timestamp="${from_timestamp} 00:00:00"
    fi
    
    if [[ -n "$to_timestamp" && "$to_timestamp" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]]; then
        to_timestamp="${to_timestamp} 23:59:59"
    fi
    
    log_debug "From time: $from_timestamp, To time: $to_timestamp"
    
    # Convert timestamps to epoch for comparison
    local from_epoch=0  # Default to start of time
    local to_epoch=9999999999  # Default to end of time
    
    if [[ -n "$from_timestamp" ]]; then
        # Try to convert the from_timestamp to epoch
        if ! from_epoch=$(timestamp_to_epoch "$from_timestamp"); then
            show_error "Invalid start time format: $from_timestamp"
            rm -f "$temp_file"
            return 1
        fi
    fi
    
    if [[ -n "$to_timestamp" ]]; then
        # Try to convert the to_timestamp to epoch
        if ! to_epoch=$(timestamp_to_epoch "$to_timestamp"); then
            show_error "Invalid end time format: $to_timestamp"
            rm -f "$temp_file"
            return 1
        fi
    fi
    
    log_debug "From epoch: $from_epoch, To epoch: $to_epoch"
    
    # Use a simpler timestamp extraction and line-by-line processing
    while IFS= read -r line; do
        # Extract timestamp using our helper function
        local ts
        if ! ts=$(extract_timestamp "$line"); then
            # If no timestamp found, include the line
            echo "$line" >> "$temp_file"
            ((filtered_count++))
            continue
        fi
        
        # Convert timestamp to epoch for comparison
        local line_epoch
        if ! line_epoch=$(timestamp_to_epoch "$ts"); then
            # If conversion fails, include the line
            echo "$line" >> "$temp_file"
            ((filtered_count++))
            continue
        fi
        
        # Check if the timestamp is within range
        if [[ "$line_epoch" -ge "$from_epoch" && "$line_epoch" -le "$to_epoch" ]]; then
            echo "$line" >> "$temp_file"
            ((filtered_count++))
        fi
    done < "$log_file"
    
    # Load the filtered logs
    local temp_filtered=()
    mapfile -t temp_filtered < "$temp_file"
    
    # Clean up temporary file
    rm -f "$temp_file"
    
    # Update the filtered logs
    if [[ ${#temp_filtered[@]} -gt 0 ]]; then
        FILTERED_LOGS=("${temp_filtered[@]}")
        current_page=1
        
        # Format displayed time range for active filters
        local display_from="${from_timestamp:-earliest}"
        local display_to="${to_timestamp:-latest}"
        local filter_description="Time range: $display_from to $display_to"
        
        # Check if we already have a time range filter
        local time_filter_index=-1
        for i in "${!ACTIVE_FILTERS[@]}"; do
            if [[ "${ACTIVE_FILTERS[i]}" == "Time range:"* ]]; then
                time_filter_index=$i
                break
            fi
        done
        
        if [[ $time_filter_index -ge 0 ]]; then
            # Replace existing time filter
            ACTIVE_FILTERS[time_filter_index]="$filter_description"
        else
            # Add new time filter
            ACTIVE_FILTERS+=("$filter_description")
        fi
        
        # Recalculate total pages
        local total_pages
        total_pages=$(( (${#FILTERED_LOGS[@]} + entries_per_page - 1) / entries_per_page ))
        if [[ $total_pages -lt 1 ]]; then
            total_pages=1
        fi
        
        show_success "Filtered ${#FILTERED_LOGS[@]} entries from $display_from to $display_to"
    else
        show_error "No entries found in the specified time range"
    fi
}

# Export current view to CSV
export_to_csv() {
    # Clear screen
    clear_screen
    echo -e "${BLUE}=== Export to CSV ===${NC}\n"
    
    # Determine if filters are active and display them
    local filters_active=false
    local filter_description=""
    
    if [[ "${#FILTERED_LOGS[@]}" -ne "${#ALL_LOGS[@]}" ]]; then
        filters_active=true
        
        # Build filter description
        if [[ "$ERRORS_ONLY" == "true" ]]; then
            filter_description+="- Showing errors only\n"
        fi
        
        # Check if there's a time range filter
        # This is an approximation - we don't store the exact filter parameters
        if [[ -n "$current_filter" ]]; then
            filter_description+="- Text filter: $current_filter\n"
        fi
        
        # Show filter summary
        echo -e "${YELLOW}Current filters:${NC}"
        if [[ -n "$filter_description" ]]; then
            echo -e "$filter_description"
        else
            echo -e "- Custom filters applied\n"
        fi
        echo -e "Filtered view: ${#FILTERED_LOGS[@]} of ${#ALL_LOGS[@]} total entries\n"
    else
        echo "No filters currently applied. All log entries will be exported."
        echo
    fi
    
    # Ask if user wants to export filtered view or entire file
    local export_choice="filtered"
    if [[ "$filters_active" == "true" ]]; then
        echo "Export options:"
        echo "  1) Export filtered view only (${#FILTERED_LOGS[@]} entries)"
        echo "  2) Export entire log file (${#ALL_LOGS[@]} entries)"
        echo
        echo -n "Enter choice [1]: "
        stty echo
        read -r choice
        stty -echo
        
        if [[ "$choice" == "2" ]]; then
            export_choice="full"
        fi
        echo
    fi
    
    # Get filename
    echo "Enter output filename (default: loglyze_export.csv):"
    echo -n "> "
    stty echo
    read -r filename
    stty -echo
    
    # Use default if empty
    if [[ -z "$filename" ]]; then
        filename="loglyze_export.csv"
    fi
    
    # Make sure the filename is valid - remove any unsafe characters
    local safe_filename
    safe_filename="${filename//[^a-zA-Z0-9_.-]/}"
    
    # Create metadata filename
    local metadata_filename="${safe_filename%.*}_metadata.txt"
    
    # Get working directory path
    local pwd_output
    pwd_output=$(pwd)
    
    log_debug "Attempting to export to file: $safe_filename"
    log_debug "Metadata will be saved to: $metadata_filename"
    
    # Try to create the file to ensure we can write to it
    if ! touch "$safe_filename" 2>/dev/null; then
        show_error "Cannot write to $safe_filename. Please check permissions and try again."
        return 1
    fi
    
    # Try to create metadata file
    if ! touch "$metadata_filename" 2>/dev/null; then
        show_error "Cannot write to $metadata_filename. Please check permissions and try again."
        return 1
    fi
    
    # Show processing message
    clear_screen
    echo "Exporting to $safe_filename..."
    echo "Creating metadata file $metadata_filename..."
    echo

    # Write CSV header
    echo "timestamp,severity,message" > "$safe_filename"
    
    # Write metadata content
    {
        echo "LogLyze Export Metadata"
        echo "========================"
        echo
        echo "Export date: $(date '+%Y-%m-%d %H:%M:%S')"
        echo "Source file: $LOG_FILE"
        echo "Export type: ${export_choice}"
        echo "Total entries: ${#ALL_LOGS[@]}"
        echo "Filtered entries: ${#FILTERED_LOGS[@]}"
        echo
        echo "Applied Filters:"
        echo "---------------"
        
        if [[ "$filters_active" == "true" ]]; then
            if [[ "$ERRORS_ONLY" == "true" ]]; then
                echo "- Showing errors only"
            fi
            
            if [[ -n "$current_filter" ]]; then
                echo "- Text filter: $current_filter"
            fi
            
            # Add timestamp filters if available
            if [[ -n "$LOCAL_FROM_TIME" ]]; then
                echo "- From time: $LOCAL_FROM_TIME"
            fi
            
            if [[ -n "$LOCAL_TO_TIME" ]]; then
                echo "- To time: $LOCAL_TO_TIME"
            fi
            
            # Also include command-line time filters if set
            if [[ -n "$FROM_TIME" && -z "$LOCAL_FROM_TIME" ]]; then
                echo "- From time (command-line): $FROM_TIME"
            fi
            
            if [[ -n "$TO_TIME" && -z "$LOCAL_TO_TIME" ]]; then
                echo "- To time (command-line): $TO_TIME"
            fi
        else
            echo "- No filters applied"
        fi
    } > "$metadata_filename"

    # Create a temporary file for the AWK script
    local temp_script
    if ! temp_script=$(mktemp); then
        show_error "Failed to create temporary file for CSV export"
        return 1
    fi

    # Create AWK script for timestamp extraction with corrected syntax
    cat > "$temp_script" << 'AWK_SCRIPT'
BEGIN {
    # No special field separator needed - we're processing whole lines
}

{
    # Store original line
    line = $0

    # Skip comment and empty lines
    if (line ~ /^[[:space:]]*#/ || line ~ /^[[:space:]]*$/) {
        next
    }

    # Extract timestamp based on various formats
    timestamp = ""
    
    # ISO 8601 with T separator and optional timezone - split into simpler patterns
    if (match(line, /[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}/)) {
        timestamp = substr(line, RSTART, RLENGTH)
        # Convert T to space
        gsub("T", " ", timestamp)
    } 
    # ISO 8601 with space separator
    else if (match(line, /[0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}:[0-9]{2}/)) {
        timestamp = substr(line, RSTART, RLENGTH)
    }
    # Syslog format (will not include year)
    else if (match(line, /[A-Z][a-z][a-z] [ 0-9][0-9] [0-9][0-9]:[0-9][0-9]:[0-9][0-9]/)) {
        timestamp = substr(line, RSTART, RLENGTH)
    }
    # MM/DD/YYYY format
    else if (match(line, /[0-9][0-9]\/[0-9][0-9]\/[0-9]{4} [0-9][0-9]:[0-9][0-9]:[0-9][0-9]/)) {
        timestamp = substr(line, RSTART, RLENGTH)
    }

    # Extract severity more precisely using comprehensive patterns
    severity = "UNKNOWN"
    
    # Check for standard severity levels with word boundaries
    if (tolower(line) ~ /\b(error|err|crit|critical|fatal|fail|exception|emerg|alert)\b/) {
        severity = "ERROR"
    } else if (tolower(line) ~ /\b(warn|warning)\b/) {
        severity = "WARNING"
    } else if (tolower(line) ~ /\b(info|information|notice)\b/) {
        severity = "INFO"
    } else if (tolower(line) ~ /\b(debug|trace|fine)\b/) {
        severity = "DEBUG"
    } 
    # If no explicit level, look for contextual clues
    else {
        # Words that suggest errors
        if (tolower(line) ~ /\b(failed|failure|cannot|not found|denied|invalid|timeout|crash|exception|corrupt|broken|incorrect)\b/) {
            severity = "ERROR"
        } 
        # Words that suggest warnings
        else if (tolower(line) ~ /\b(high|slow|approaching|latency|limitation|degradation|conflict|caution|attention|deprecated)\b/) {
            severity = "WARNING"
        }
        # Words that suggest info events
        else if (tolower(line) ~ /\b(started|completed|finished|success|created|connected|authenticated|established|loaded|running)\b/) {
            severity = "INFO"
        }
    }

    # Extract message - first store original line
    message = line

    # Extract message more intelligently
    if (timestamp != "") {
        # Remove timestamp from message
        sub(timestamp, "", message)
        
        # Try to find and extract just the message part
        if (match(message, /\b(ERROR|ERR|WARNING|WARN|INFO|DEBUG|NOTICE|TRACE|FATAL|CRITICAL|CRIT|EMERG|ALERT)[: ][ ]*(.*)/i)) {
            message = substr(message, RSTART + RLENGTH)
        } else if (match(message, /[a-zA-Z0-9._-]+:[0-9]+:[ ]*(.*)/)) {
            # Pattern like "filename:line: message"
            message = substr(message, RSTART + RLENGTH)
        } else if (match(message, /[a-zA-Z0-9._-]+\[[0-9]+\]:[ ]*(.*)/)) {
            # Pattern like "process[pid]: message"
            message = substr(message, RSTART + RLENGTH)
        }
    }
    
    # Remove leading spaces and special characters
    gsub(/^[ \t:]+/, "", message)
    # Remove trailing whitespace
    gsub(/[[:space:]]+$/, "", message)

    # Only output if we have content
    if (message != "" && message !~ /^[[:space:]]*#/) {
        # Escape quotes in all fields
        gsub(/"/, "\"\"", timestamp)
        gsub(/"/, "\"\"", severity)
        gsub(/"/, "\"\"", message)
        printf("\"%s\",\"%s\",\"%s\"\n", timestamp, severity, message)
    }
}
AWK_SCRIPT

    # Create a temporary file for the logs
    local temp_logs
    temp_logs=$(mktemp)
    
    # Write logs to temporary file
    if [[ "$export_choice" == "full" ]]; then
        log_debug "Exporting full log file (${#ALL_LOGS[@]} entries)"
        printf '%s\n' "${ALL_LOGS[@]}" > "$temp_logs"
        exported_count=${#ALL_LOGS[@]}
    else
        log_debug "Exporting filtered view (${#FILTERED_LOGS[@]} entries)"
        printf '%s\n' "${FILTERED_LOGS[@]}" > "$temp_logs"
        exported_count=${#FILTERED_LOGS[@]}
    fi

    # Process logs with AWK and append to CSV
    if ! awk -f "$temp_script" "$temp_logs" >> "$safe_filename" 2>/dev/null; then
        show_error "Failed to process logs for CSV export"
        rm -f "$temp_script" "$temp_logs"
        return 1
    fi

    # Clean up temporary files
    rm -f "$temp_script" "$temp_logs"
    
    # Verify the file was created and has content
    if [[ -f "$safe_filename" && -s "$safe_filename" ]]; then
        local full_path
        if ! full_path=$(realpath "$safe_filename"); then
            full_path="$pwd_output/$safe_filename"
        fi
        
        show_success "Successfully exported $exported_count entries to $safe_filename"
        # Show the actual path for clarity
        echo "File saved to: $full_path"
    else
        show_error "Failed to export to $safe_filename"
    fi
}

# Toggle errors only mode
toggle_errors_only() {
    # Check if already in errors only mode
    if [[ "$ERRORS_ONLY" == "true" ]]; then
        # Turn off errors only
        ERRORS_ONLY="false"
        
        # Remove from active filters list
        local new_active_filters=()
        for filter in "${ACTIVE_FILTERS[@]}"; do
            if [[ "$filter" != "Errors only" ]]; then
                new_active_filters+=("$filter")
            fi
        done
        ACTIVE_FILTERS=("${new_active_filters[@]}")
        
        # If this was the only filter, reload original file
        if [[ ${#ACTIVE_FILTERS[@]} -eq 0 ]]; then
            FILTERED_LOGS=("${ALL_LOGS[@]}")
            show_success "Showing all log entries."
        else
            # Otherwise, we need to reapply other filters
            # This would need a more complex implementation to remember filter ordering
            # For now, we'll just keep the current filtered logs minus the error filter
            show_success "Removed errors-only filter, maintaining other active filters."
        fi
    else
        # Turn on errors only
        ERRORS_ONLY="true"
        
        # Create a temporary array for filtered entries
        local temp_filtered=()
        
        # Show processing message with progress
        clear_screen
        echo "Filtering error entries..."
        echo
        
        # Track progress
        local total
        total=${#ALL_LOGS[@]}
        local processed=0
        local progress_bar_width=40
        
        # Create a temporary file for the filter script
        local temp_script
        if ! temp_script=$(mktemp); then
            show_error "Failed to create temporary script for error filtering"
            return 1
        fi
        
        # Create awk script for better error detection
        cat > "$temp_script" << 'EOF'
        # Case-insensitive error pattern matching
        tolower($0) ~ /(error|critical|fatal|exception|fail)/ {
            print
            exit 0  # Match found
        }
        {
            exit 1  # No match found
        }
EOF
        
        # Always start with all logs when filtering
        # Apply filter - case insensitive
        for line in "${ALL_LOGS[@]}"; do
            if echo "$line" | awk -f "$temp_script"; then
                temp_filtered+=("$line")
            fi
            
            # Update progress every 100 items
            ((processed++))
            if (( processed % 100 == 0 )) || (( processed == total )); then
                # Calculate percentage
                local percent
                percent=$((processed * 100 / total))
                local bar_filled
                bar_filled=$((processed * progress_bar_width / total))
                
                # Draw progress bar
                echo -ne "\rProgress: ["
                for ((i=0; i<bar_filled; i++)); do 
                    echo -n "#"
                done
                for ((i=bar_filled; i<progress_bar_width; i++)); do 
                    echo -n " "
                done
                echo -ne "] $percent% ($processed/$total)"
            fi
        done
        
        # Clean up
        rm -f "$temp_script"
        
        echo # New line after progress bar
        
        # Update filtered logs
        if [[ ${#temp_filtered[@]} -gt 0 ]]; then
            FILTERED_LOGS=("${temp_filtered[@]}")
            
            # Add to active filters if not already present
            local has_error_filter=false
            for filter in "${ACTIVE_FILTERS[@]}"; do
                if [[ "$filter" == "Errors only" ]]; then
                    has_error_filter=true
                    break
                fi
            done
            
            if [[ "$has_error_filter" == "false" ]]; then
                ACTIVE_FILTERS+=("Errors only")
            fi
            
            show_success "Filtered to ${#FILTERED_LOGS[@]} error entries."
        else
            show_error "No error entries found."
        fi
    fi
    
    # Reset page
    current_page=1
    # Recalculate total pages
    local total_pages
    total_pages=$(( (${#FILTERED_LOGS[@]} + entries_per_page - 1) / entries_per_page ))
    if [[ $total_pages -lt 1 ]]; then
        total_pages=1
    fi
}

# Clear all filters
clear_all_filters() {
    log_debug "Clear filters triggered"
    
    # Reload original file
    FILTERED_LOGS=("${ALL_LOGS[@]}")
    
    # Reset variables
    ERRORS_ONLY="false"
    ACTIVE_FILTERS=()
    current_filter=""
    
    # Reset page
    current_page=1
    
    # Recalculate total pages
    local total_pages
    total_pages=$(( (${#FILTERED_LOGS[@]} + entries_per_page - 1) / entries_per_page ))
    if [[ $total_pages -lt 1 ]]; then
        total_pages=1
    fi
    
    show_success "All filters cleared."
    display_logs "$current_page" "$total_pages"
}

# Main interactive mode function
run_interactive_mode() {
    local log_file=${1:-}
    
    # If log_file was passed, set LOG_FILE
    if [[ -n "$log_file" ]]; then
        log_debug "Using provided log file: $log_file"
        LOG_FILE="$log_file"
    fi
    
    log_debug "Running interactive mode for file: $LOG_FILE"
    
    # Set up proper cleanup on exit
    trap cleanup_interactive_mode EXIT INT TERM HUP
    
    # Initialize interactive mode
    init_interactive_mode
    
    # Check if file exists
    if [[ ! -f "$LOG_FILE" ]]; then
        log_error "File not found: $LOG_FILE"
        show_error "Error: Log file '$LOG_FILE' not found."
        cleanup_interactive_mode
        exit 1
    fi
    
    log_debug "Loading log entries from $LOG_FILE"
    
    # Clear any previously loaded data
    unset ALL_LOGS
    unset FILTERED_LOGS
    declare -ga ALL_LOGS=()
    declare -ga FILTERED_LOGS=()
    
    # Load log entries directly into FILTERED_LOGS - this is crucial for command-line filtering
    mapfile -t FILTERED_LOGS < "$LOG_FILE"
    
    # Store a copy in ALL_LOGS for reset capability 
    # If original LOG_FILE is specified in the environment (i.e., different from the provided log_file),
    # load that for ALL_LOGS. Otherwise, use the same file for both.
    if [[ -n "$log_file" && "$log_file" != "${LOG_FILE_ORIGINAL:-$LOG_FILE}" && -f "${LOG_FILE_ORIGINAL:-$LOG_FILE}" ]]; then
        # If we were passed a filtered file, but have access to the original file,
        # use the original for ALL_LOGS to enable proper filter resetting
        log_debug "Loading original log file for filter reset capability"
        mapfile -t ALL_LOGS < "${LOG_FILE_ORIGINAL:-$LOG_FILE}"
    else
        # Just use the same data for both
        ALL_LOGS=("${FILTERED_LOGS[@]}")
    fi
    
    log_debug "Loaded ${#FILTERED_LOGS[@]} filtered entries"
    log_debug "Loaded ${#ALL_LOGS[@]} total entries"
    
    # Initialize ERRORS_ONLY flag based on environment variable or default to "false"
    ERRORS_ONLY="${ERRORS_ONLY:-false}"
    
    # Calculate total pages
    local total_pages
    total_pages=$(( (${#FILTERED_LOGS[@]} + entries_per_page - 1) / entries_per_page ))
    if [[ $total_pages -lt 1 ]]; then
        total_pages=1
    fi
    
    log_debug "Total pages: $total_pages with $entries_per_page entries per page"
    
    # Display initial page
    display_logs "$current_page" "$total_pages"
    
    log_debug "Starting input loop - press 'q' to quit"
    
    # Store original terminal settings for consistent restoration
    local original_terminal_settings
    original_terminal_settings=$(stty -g) || {
        log_error "Failed to get terminal settings"
        show_error "Failed to initialize terminal settings"
        cleanup_interactive_mode
        exit 1
    }
    
    # Handle user input
    while true; do
        # Set non-canonical mode (don't wait for newline)
        stty -icanon -echo || log_debug "Warning: Could not set terminal to non-canonical mode"
        
        # Read a single character without waiting
        local key
        IFS= read -r -s -n1 key || {
            # Read error, try again
            log_debug "Error reading key input, trying again"
            sleep 0.5
            continue
        }
        
        log_debug "Key pressed: '$key' (ASCII: $(printf "%d" "'$key" 2>/dev/null || echo "unknown"))"
        
        # Handle special keys (arrow keys, etc.) that start with escape
        if [[ "$key" == $'\e' ]]; then
            # Read more characters with a small timeout
            local rest
            rest=""
            read -r -s -n2 -t 0.01 rest || true
            key+="$rest"
            log_debug "Escape sequence detected: '$key'"
        fi

        # Handle explicit key cases
        case "$key" in
            # Navigation keys
            $'\e[A'|'k'|'K') # Up arrow or k/K
                log_debug "Up navigation triggered"
                if [[ $current_page -gt 1 ]]; then
                    ((current_page--))
                    display_logs "$current_page" "$total_pages"
                fi
                ;;
            $'\e[B'|'j'|'J') # Down arrow or j/J
                log_debug "Down navigation triggered"
                if [[ $current_page -lt $total_pages ]]; then
                    ((current_page++))
                    display_logs "$current_page" "$total_pages"
                fi
                ;;
            $'\e[5~') # Page Up
                log_debug "Page Up triggered"
                if [[ $current_page -gt 5 ]]; then
                    current_page=$((current_page - 5))
                else
                    current_page=1
                fi
                display_logs "$current_page" "$total_pages"
                ;;
            $'\e[6~') # Page Down
                log_debug "Page Down triggered"
                if [[ $((current_page + 5)) -lt $total_pages ]]; then
                    current_page=$((current_page + 5))
                else
                    current_page=$total_pages
                fi
                display_logs "$current_page" "$total_pages"
                ;;
                
            # Help
            'h'|'H'|$'\e[D') # h/H or Left arrow
                log_debug "Help triggered"
                # Display help
                clear_screen
                
                tput setaf 4 # Blue
                echo "=== LogLyze Interactive Mode Help ==="
                tput sgr0 # Reset
                
                tput setaf 3 # Yellow
                echo "Navigation:"
                tput sgr0 # Reset
                
                echo "  Up/Down arrows or j/k: Navigate between pages"
                echo "  Page Up/Down: Jump 5 pages at a time"
                echo "  g: Go to a specific page"
                echo "  t: Jump to a specific timestamp"
                echo
                
                tput setaf 3 # Yellow
                echo "Filtering:"
                tput sgr0 # Reset
                
                echo "  f: Filter log entries by text (case-insensitive)"
                echo "  r: Filter by time range"
                echo "  e: Toggle showing only errors"
                echo "  c: Clear all filters"
                echo
                
                tput setaf 3 # Yellow
                echo "Actions:"
                tput sgr0 # Reset
                
                echo "  s: Generate and display log summary"
                echo "  x: Export current view to CSV"
                echo "  q: Quit interactive mode"
                echo
                
                echo "Press any key to continue..."
                read -rsn1
                display_logs "$current_page" "$total_pages"
                ;;
                
            # Page and filtering operations
            'g'|'G') # Go to page
                log_debug "Go to page triggered"
                
                # Clear screen and show input prompt
                clear_screen
                echo -e "${BLUE}=== Go to Page ===${NC}\n"
                echo "Current page: $current_page of $total_pages"
                echo
                
                # Get page number directly
                echo "Enter page number (1-$total_pages):"
                echo -n "> "
                stty echo
                read -r page_number
                stty -echo
                
                log_debug "User entered page number: $page_number"
                
                # Validate input
                if [[ -z "$page_number" ]]; then
                    show_error "No page number entered. Staying on current page."
                elif ! [[ "$page_number" =~ ^[0-9]+$ ]]; then
                    show_error "Invalid input. Please enter a number between 1 and $total_pages."
                elif (( page_number < 1 || page_number > total_pages )); then
                    show_error "Page number out of range. Please enter a number between 1 and $total_pages."
                else
                    current_page=$page_number
                    show_success "Navigating to page $current_page"
                fi
                
                # Redraw interface
                display_logs "$current_page" "$total_pages"
                ;;
                
            'f'|'F') # Filter by text
                log_debug "Filter by text triggered"
                # Restore normal terminal settings temporarily for input
                stty "$original_terminal_settings" || log_debug "Warning: Could not restore terminal settings"
                # Process input
                filter_by_text
                # Reset terminal to non-canonical mode
                stty -icanon -echo || log_debug "Warning: Could not set terminal to non-canonical mode"
                # Redraw interface
                display_logs "$current_page" "$total_pages"
                ;;
                
            'r'|'R') # Filter by time range
                log_debug "Time range filter triggered"
                # Restore normal terminal settings temporarily for input
                stty "$original_terminal_settings" || log_debug "Warning: Could not restore terminal settings"
                # Process input
                filter_by_time_range
                # Reset terminal to non-canonical mode
                stty -icanon -echo || log_debug "Warning: Could not set terminal to non-canonical mode"
                # Recalculate total pages after filtering
                total_pages=$(( (${#FILTERED_LOGS[@]} + entries_per_page - 1) / entries_per_page ))
                [[ $total_pages -lt 1 ]] && total_pages=1
                # Redraw interface
                display_logs "$current_page" "$total_pages"
                ;;
                
            'e'|'E') # Toggle errors only
                log_debug "Toggle errors only triggered"
                toggle_errors_only
                display_logs "$current_page" "$total_pages"
                ;;
                
            'c'|'C') # Clear all filters
                log_debug "Clear filters triggered"
                clear_all_filters
                ;;
                
            # Other actions
            't'|'T') # Jump to timestamp
                log_debug "Jump to timestamp triggered"
                # Restore normal terminal settings temporarily for input
                stty "$original_terminal_settings" || log_debug "Warning: Could not restore terminal settings"
                # Process input
                jump_to_timestamp
                # Reset terminal to non-canonical mode
                stty -icanon -echo || log_debug "Warning: Could not set terminal to non-canonical mode"
                # Recalculate total pages after jump
                total_pages=$(( (${#FILTERED_LOGS[@]} + entries_per_page - 1) / entries_per_page ))
                [[ $total_pages -lt 1 ]] && total_pages=1
                # Redraw interface
                display_logs "$current_page" "$total_pages"
                ;;
                
            's'|'S') # Generate summary
                log_debug "Generate summary triggered"
                # Clear screen
                clear_screen
                
                # Generate and display summary
                if [[ -n $(command -v generate_summary) ]]; then
                    generate_summary "$LOG_FILE" "stdout" 10  # Show top 10 errors
                else
                    show_error "Summary generation not available in interactive mode."
                fi
                
                echo ""
                echo "Press any key to continue..."
                read -rsn1
                display_logs "$current_page" "$total_pages"
                ;;
                
            'x'|'X') # Export to CSV
                log_debug "Export to CSV triggered"
                # Restore normal terminal settings temporarily for input
                stty "$original_terminal_settings" || log_debug "Warning: Could not restore terminal settings"
                # Process input
                export_to_csv
                # Reset terminal to non-canonical mode
                stty -icanon -echo || log_debug "Warning: Could not set terminal to non-canonical mode"
                # Redraw interface
                display_logs "$current_page" "$total_pages"
                ;;
                
            # Exit
            'q'|'Q') # Quit
                log_debug "Quit triggered"
                # Restore terminal settings
                cleanup_interactive_mode
                
                # Reset the trap since we're exiting normally
                trap - EXIT INT TERM HUP
                
                return 0
                ;;
                
            # Catch empty input (happens with some keys)
            '') 
                # Ignore empty inputs
                ;;
                
            # Fallback for unrecognized keys
            *) 
                log_debug "Unrecognized key: '$key'"
                ;;
        esac
    done
}

# Export the functions needed by the main script
# Note: We need to define these functions as POSIX functions (without the -f flag)
# to ensure they are properly exported in all environments
export run_interactive_mode
export init_interactive_mode
export cleanup_interactive_mode
export display_logs
export load_log_file
export current_search
export current_filter