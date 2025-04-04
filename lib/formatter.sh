#!/usr/bin/env bash
#
# Formatter module for loglyze
# Handles formatting output in different formats (text, CSV, etc.)

# Security: Validate paths and sanitize inputs
validate_file_path() {
    local path="$1"
    if [[ -z "$path" ]]; then
        return 0
    fi
    
    # Check for directory traversal
    if echo "$path" | grep -q '\.\.'; then
        echo "Error: Path traversal attempt detected" >&2
        return 1
    fi
    
    # Check for dangerous characters
    if echo "$path" | grep -q '[;|&<>$\\]'; then
        echo "Error: Dangerous characters in path" >&2
        return 1
    fi
    
    return 0
}

# Security: Sanitize string for safe output
sanitize_string() {
    local input="$1"
    # Remove control characters but preserve quotes
    # We want to keep the quotes visible in the output but escape them for safety
    echo "$input" | tr -d '\000-\010\013\014\016-\037' | sed 's/"/\\"/g'
}

# Security: Sanitize for CSV inclusion
sanitize_csv_field() {
    local input="$1"
    # Escape double quotes with double quotes (CSV standard)
    echo "${input//\"/\"\"}"
}

# Format log entries as text with highlighting
format_as_text() {
    local input=$1
    
    log_debug "Formatting output as text"
    
    # Process input line by line
    while IFS= read -r line; do
        # Skip pure comment lines
        if [[ "$line" =~ ^[[:space:]]*# ]]; then
            echo "$line"
            continue
        fi
        
        # Sanitize the line first, but preserve quotes for display
        line=$(sanitize_string "$line")
        
        # Highlight based on severity
        if grep -qi "error" <<< "$line"; then
            echo -e "${RED}$line${NC}"
        elif grep -qi "warn" <<< "$line"; then
            echo -e "${YELLOW}$line${NC}"
        elif grep -qi "info" <<< "$line"; then
            echo -e "${GREEN}$line${NC}"
        elif grep -qi "debug" <<< "$line"; then
            echo -e "${CYAN}$line${NC}"
        else
            echo "$line"
        fi
    done <<< "$input"
}

# Format log entries as CSV
format_as_csv() {
    local input=$1
    
    log_debug "Formatting output as CSV"
    
    # Output CSV header
    echo "timestamp,severity,message"
    
    # Process input line by line
    while IFS= read -r line; do
        # Skip pure comment lines and empty lines
        if [[ "$line" =~ ^[[:space:]]*# ]] || [[ -z "${line// }" ]]; then
            continue
        fi
        
        # Extract timestamp, severity, and message based on the current format
        local timestamp=""
        local severity=""
        local message=""
        
        # Get timestamp pattern based on current format
        local timestamp_pattern="${CURRENT_FORMAT["timestamp_pattern"]}"
        if [[ -z "$timestamp_pattern" ]]; then
            # Try to find a pattern in the TIMESTAMP_PATTERNS array
            for pattern in "${TIMESTAMP_PATTERNS[@]}"; do
                if grep -qE "$pattern" <<< "$line"; then
                    timestamp_pattern="$pattern"
                    break
                fi
            done
        fi
        
        # Extract timestamp if pattern exists
        if [[ -n "$timestamp_pattern" ]]; then
            timestamp=$(grep -oE "$timestamp_pattern" <<< "$line" | head -1)
            # Remove the timestamp from the message
            line=${line/"$timestamp"/}
        fi
        
        # Get severity pattern based on current format
        local severity_pattern="${CURRENT_FORMAT["severity_pattern"]}"
        if [[ -z "$severity_pattern" ]]; then
            # Try to find a pattern in the SEVERITY_PATTERNS array
            for pattern in "${SEVERITY_PATTERNS[@]}"; do
                if grep -qiE "$pattern" <<< "$line"; then
                    severity_pattern="$pattern"
                    break
                fi
            done
        fi
        
        # Extract severity if pattern exists
        if [[ -n "$severity_pattern" ]]; then
            severity=$(grep -oiE "$severity_pattern" <<< "$line" | head -1)
            # Remove the severity from the message
            line=${line/"$severity"/}
        fi
        
        # If severity is still empty, check common keywords
        if [[ -z "$severity" ]]; then
            if grep -qi "error" <<< "$line"; then
                severity="ERROR"
            elif grep -qi "warn" <<< "$line"; then
                severity="WARNING"
            elif grep -qi "info" <<< "$line"; then
                severity="INFO"
            elif grep -qi "debug" <<< "$line"; then
                severity="DEBUG"
            elif grep -qi "notice" <<< "$line"; then
                severity="NOTICE"
            elif grep -qi "started\|completed\|finished\|success" <<< "$line"; then
                severity="INFO"
            elif grep -qi "failed\|cannot\|not found\|error" <<< "$line"; then
                severity="ERROR"
            else
                severity="UNKNOWN"
            fi
        fi
        
        # Clean up the message
        message=$(echo "$line" | sed -e 's/^[[:space:]]*//;s/[[:space:]]*$//' | tr -d '\r')
        
        # Improve message extraction - try to extract actual message content
        # Look for patterns like ":" or "-" that often separate metadata from message
        if [[ "$message" == *":"* ]]; then
            message=$(echo "$message" | sed -E 's/.*:[[:space:]]*//')
        elif [[ "$message" == *" - "* ]]; then
            message=$(echo "$message" | sed -E 's/.*- //')
        fi
        
        # Sanitize all fields for CSV
        timestamp=$(sanitize_csv_field "$timestamp")
        severity=$(sanitize_csv_field "$severity")
        message=$(sanitize_csv_field "$message")
        
        # Output CSV row only if we have actual content (not comments)
        if [[ -n "$message" && ! "$message" =~ ^# ]]; then
            echo "\"${timestamp}\",\"${severity}\",\"${message}\""
        fi
    done <<< "$input"
}

# Format summary as JSON
format_summary_as_json() {
    local log_file=$1
    local total_lines=$2
    local error_count=$3
    local warning_count=$4
    local info_count=$5
    local first_timestamp=$6
    local last_timestamp=$7
    
    # Validate path
    validate_file_path "$log_file" || return 1
    
    log_debug "Formatting summary as JSON"
    
    # Sanitize inputs for JSON output
    log_file=$(sanitize_string "$log_file")
    first_timestamp=$(sanitize_string "$first_timestamp")
    last_timestamp=$(sanitize_string "$last_timestamp")
    
    cat << EOF
{
  "file": "${log_file}",
  "stats": {
    "total_lines": ${total_lines},
    "error_count": ${error_count},
    "warning_count": ${warning_count},
    "info_count": ${info_count}
  },
  "time_range": {
    "first": "${first_timestamp}",
    "last": "${last_timestamp}"
  }
}
EOF
}

# Format errors as a chart
format_errors_as_chart() {
    local log_file=$1
    local threshold=${2:-1}
    
    # Validate path
    validate_file_path "$log_file" || return 1
    
    log_debug "Formatting errors as chart with threshold $threshold"
    
    # Ensure threshold is a positive number
    if ! [[ "$threshold" =~ ^[0-9]+$ ]]; then
        echo "Error: Invalid threshold value" >&2
        return 1
    fi
    
    # Find unique errors and their counts
    local errors
    errors=$(find_unique_errors "$log_file" "$threshold")
    
    # Generate a simple ASCII chart
    echo "=== Error Frequency Chart ==="
    echo "$errors" | while read -r count message; do
        # Sanitize message for display
        message=$(sanitize_string "$message")
        
        # Calculate chart width (max 50 characters)
        local width=$(( count * 50 / $(echo "$errors" | head -1 | awk '{print $1}') ))
        printf "%-5s %-50s %s\n" "$count" "${message:0:50}" "$(printf '%*s' "$width" " " | tr ' ' '#')"
    done
}

# Format time metrics as chart
format_time_metrics_as_chart() {
    local metrics=$1
    local max_count=$2
    
    log_debug "Formatting time metrics as chart"
    
    echo "=== Time Distribution Chart ==="
    echo "$metrics" | while read -r count timestamp; do
        # Sanitize timestamp for display
        timestamp=$(sanitize_string "$timestamp")
        
        # Calculate chart width (max 50 characters)
        local width=$(( count * 50 / max_count ))
        printf "%-20s %-5s %s\n" "$timestamp" "$count" "$(printf '%*s' "$width" " " | tr ' ' '#')"
    done
}

# Generate a full report combining multiple outputs
generate_full_report() {
    local log_file=$1
    local output_format=${2:-"text"}
    
    # Validate path
    validate_file_path "$log_file" || return 1
    
    log_debug "Generating full report in $output_format format"
    
    case "$output_format" in
        "csv")
            # CSV header for full report
            echo "report_type,key,value"
            
            # Basic statistics
            local total_lines
            local error_count
            local warning_count
            local info_count
            
            total_lines=$(wc -l < "$log_file")
            error_count=$(grep -ci "error" "$log_file" || echo 0)
            warning_count=$(grep -ci "warn" "$log_file" || echo 0)
            info_count=$(grep -ci "info" "$log_file" || echo 0)
            
            # Output statistics
            echo "statistics,total_lines,${total_lines}"
            echo "statistics,error_count,${error_count}"
            echo "statistics,warning_count,${warning_count}"
            echo "statistics,info_count,${info_count}"
            
            # Time range
            local time_range
            time_range=$(extract_date_range "$log_file")
            local first_timestamp
            local last_timestamp
            first_timestamp=$(echo "$time_range" | grep "First:" | cut -d' ' -f2-)
            last_timestamp=$(echo "$time_range" | grep "Last:" | cut -d' ' -f2-)
            
            # Sanitize timestamps for CSV
            first_timestamp=$(sanitize_csv_field "$first_timestamp")
            last_timestamp=$(sanitize_csv_field "$last_timestamp")
            
            echo "time_range,first,\"${first_timestamp}\""
            echo "time_range,last,\"${last_timestamp}\""
            
            # Top errors
            grep -i "error" "$log_file" | sort | uniq -c | sort -nr | head -10 | while read -r count message; do
                # Sanitize message for CSV
                message=$(sanitize_csv_field "$message")
                echo "top_errors,${count},\"${message}\""
            done
            ;;
        "json")
            # Basic statistics
            local total_lines
            local error_count
            local warning_count
            local info_count
            
            total_lines=$(wc -l < "$log_file")
            error_count=$(grep -ci "error" "$log_file" || echo 0)
            warning_count=$(grep -ci "warn" "$log_file" || echo 0)
            info_count=$(grep -ci "info" "$log_file" || echo 0)
            
            # Time range
            local time_range
            time_range=$(extract_date_range "$log_file")
            local first_timestamp
            local last_timestamp
            first_timestamp=$(echo "$time_range" | grep "First:" | cut -d' ' -f2-)
            last_timestamp=$(echo "$time_range" | grep "Last:" | cut -d' ' -f2-)
            
            # Sanitize for JSON
            log_file=$(sanitize_string "$log_file")
            first_timestamp=$(sanitize_string "$first_timestamp")
            last_timestamp=$(sanitize_string "$last_timestamp")
            
            # Top errors
            local top_errors="["
            local first=true
            while read -r count message; do
                if ! $first; then
                    top_errors+=","
                else
                    first=false
                fi
                # Sanitize message for JSON
                message=$(sanitize_string "$message")
                top_errors+="{\"count\":${count},\"message\":\"${message}\"}"
            done < <(grep -i "error" "$log_file" | sort | uniq -c | sort -nr | head -10)
            top_errors+="]"
            
            # Output JSON
            cat << EOF
{
  "file": "${log_file}",
  "statistics": {
    "total_lines": ${total_lines},
    "error_count": ${error_count},
    "warning_count": ${warning_count},
    "info_count": ${info_count}
  },
  "time_range": {
    "first": "${first_timestamp}",
    "last": "${last_timestamp}"
  },
  "top_errors": ${top_errors}
}
EOF
            ;;
        *)
            # Default to text format
            # Generate summary
            generate_summary "$log_file"
            
            # Generate error frequency chart
            format_errors_as_chart "$log_file" 5
            
            # Calculate and format time metrics
            calculate_time_metrics "$log_file" "hour"
            ;;
    esac
} 