#!/bin/bash
#
# Run all tests for LogLyze
# Including Node.js, shell, and interactive tests

set -e  # Exit on error

# Define colors for reporting
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[0;33m'
BLUE='\033[0;36m'
NC='\033[0m' # No Color

# Get the script directory
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

# Create directory for test outputs
mkdir -p "$SCRIPT_DIR/output"

# Log file for comprehensive test output
LOG_FILE="$SCRIPT_DIR/output/run_all_tests.output.log"
# Remove existing log file (if any)
rm -f "$LOG_FILE"

# Print header
echo -e "${BLUE}======================================================${NC}"
echo -e "${BLUE}               Running LogLyze Tests                   ${NC}"
echo -e "${BLUE}======================================================${NC}"
echo

# Log function to write to both console and log file
log() {
    local level="$1"
    local message="$2"
    local timestamp
    timestamp=$(date "+%Y-%m-%d %H:%M:%S")
    
    # Choose color based on level
    local color=""
    case "$level" in
        "INFO") color="${BLUE}" ;;
        "PASS") color="${GREEN}" ;;
        "FAIL") color="${RED}" ;;
        "WARN") color="${YELLOW}" ;;
        *) color="${NC}" ;;
    esac
    
    # Print to console with color
    echo -e "${color}[$timestamp] [$level] $message${NC}"
    
    # Log to file without color codes
    echo "[$timestamp] [$level] $message" >> "$LOG_FILE"
}

# Helper function to run a test group
run_test_group() {
    local name="$1"
    local command="$2"
    
    log "INFO" "Running $name tests..."
    log "INFO" "Command: $command"
    echo
    
    # Create a temp file for test output
    local temp_output
    temp_output=$(mktemp)
    
    # Run the command and capture its output
    log "INFO" "====== Starting $name tests ======"
    if eval "$command" > "$temp_output" 2>&1; then
        # Success
        log "PASS" "$name tests PASSED"
        
        # Log the output to our log file
        log "INFO" "Output from $name tests:"
        cat "$temp_output" >> "$LOG_FILE"
        echo "====== End of $name tests output ======" >> "$LOG_FILE"
        
        # Clean up temp file
        rm "$temp_output"
        return 0
    else
        # Failure
        local exit_code=$?
        log "FAIL" "$name tests FAILED with exit code $exit_code"
        
        # Log the output to our log file
        log "INFO" "Output from $name tests (FAILED):"
        cat "$temp_output" >> "$LOG_FILE"
        echo "====== End of $name tests output ======" >> "$LOG_FILE"
        
        # Clean up temp file
        rm "$temp_output"
        return 1
    fi
}

# Check for expect command for interactive tests
if ! command -v expect &> /dev/null; then
    log "WARN" "'expect' command not found. Interactive tests will be skipped."
    log "INFO" "Install expect with: sudo apt-get install expect (Ubuntu/Debian)"
    echo
    SKIP_INTERACTIVE=1
else
    SKIP_INTERACTIVE=0
fi

# Track test results
NODE_TESTS_RESULT=0
SHELL_TESTS_RESULT=0
INTERACTIVE_TESTS_RESULT=0
FORMAT_TESTS_RESULT=0

# 0. Log available log formats
log "INFO" "Checking available log format samples..."
SAMPLES_DIR="$SCRIPT_DIR/../samples"
AVAILABLE_FORMATS=""
for file in "$SAMPLES_DIR"/*.log; do
  # Skip files with "sample" in the name
  if [[ "$(basename "$file")" != *"sample"* ]] && [[ -f "$file" ]]; then
    # Extract format name (remove .log extension)
    format=$(basename "$file" .log)
    AVAILABLE_FORMATS="$AVAILABLE_FORMATS $format"
    log "INFO" "Found log format sample: $format"
  fi
done
log "INFO" "Total available formats: $(echo "$AVAILABLE_FORMATS" | wc -w)"
echo

# 1. Run Node.js Jest tests
log "INFO" "[1/4] Running Node.js Tests"
if ! run_test_group "Node.js" "cd \"$SCRIPT_DIR/..\" && npm test"; then
    NODE_TESTS_RESULT=1
fi
echo

# 2. Run format-specific tests
log "INFO" "[2/4] Running Format-Specific Tests"
if ! run_test_group "Format-Specific" "cd \"$SCRIPT_DIR/..\" && npx jest tests/loglyze-format-sample.test.ts --no-cache"; then
    FORMAT_TESTS_RESULT=1
fi
echo

# 3. Run shell tests
log "INFO" "[3/4] Running Shell Tests"
if ! run_test_group "Shell" "$SCRIPT_DIR/shell_test.sh"; then
    SHELL_TESTS_RESULT=1
fi
echo

# 4. Run interactive tests if expect is available
log "INFO" "[4/4] Running Interactive Tests"
if [[ $SKIP_INTERACTIVE -eq 1 ]]; then
    log "WARN" "Skipping interactive tests (expect command not available)"
    echo
else
    if ! run_test_group "Interactive" "$SCRIPT_DIR/interactive_test.exp"; then
        INTERACTIVE_TESTS_RESULT=1
    fi
    echo
fi

# Print summary
echo -e "${BLUE}======================================================${NC}"
echo -e "${BLUE}               Test Results Summary                    ${NC}"
echo -e "${BLUE}======================================================${NC}"
echo

if [[ $NODE_TESTS_RESULT -eq 0 ]]; then
    log "PASS" "Node.js Tests:     PASSED"
else
    log "FAIL" "Node.js Tests:     FAILED"
fi

if [[ $FORMAT_TESTS_RESULT -eq 0 ]]; then
    log "PASS" "Format-Specific Tests: PASSED"
else
    log "FAIL" "Format-Specific Tests: FAILED"
fi

if [[ $SHELL_TESTS_RESULT -eq 0 ]]; then
    log "PASS" "Shell Tests:       PASSED"
else
    log "FAIL" "Shell Tests:       FAILED"
fi

if [[ $SKIP_INTERACTIVE -eq 1 ]]; then
    log "WARN" "Interactive Tests: SKIPPED"
elif [[ $INTERACTIVE_TESTS_RESULT -eq 0 ]]; then
    log "PASS" "Interactive Tests: PASSED"
else
    log "FAIL" "Interactive Tests: FAILED"
fi

echo

# Overall result
OVERALL_RESULT=$((NODE_TESTS_RESULT + FORMAT_TESTS_RESULT + SHELL_TESTS_RESULT + INTERACTIVE_TESTS_RESULT))

# Validate the log file
log "INFO" "Validating test log file..."
LOG_FILE_VALIDATION=0

# Check if the log file exists and is not empty
if [[ ! -s "$LOG_FILE" ]]; then
    log "FAIL" "Log file is empty or doesn't exist!"
    LOG_FILE_VALIDATION=1
fi

# Check for specific expected content in the log file
if ! grep -q "Starting Node.js tests" "$LOG_FILE"; then
    log "FAIL" "Missing Node.js test section in log file"
    LOG_FILE_VALIDATION=1
fi

if ! grep -q "Starting Format-Specific tests" "$LOG_FILE"; then
    log "FAIL" "Missing Format-Specific test section in log file"
    LOG_FILE_VALIDATION=1
fi

if ! grep -q "Starting Shell tests" "$LOG_FILE"; then
    log "FAIL" "Missing Shell test section in log file"
    LOG_FILE_VALIDATION=1
fi

# Check for unexpected error patterns (modify according to your needs)
if grep -q "UNEXPECTED ERROR" "$LOG_FILE"; then
    log "FAIL" "Found unexpected error pattern in log file"
    LOG_FILE_VALIDATION=1
fi

# Log file size
LOG_FILE_SIZE=$(wc -c < "$LOG_FILE")
log "INFO" "Log file size: $LOG_FILE_SIZE bytes"

if [[ $LOG_FILE_VALIDATION -eq 0 ]]; then
    log "PASS" "Log file validation PASSED"
else
    log "FAIL" "Log file validation FAILED"
    OVERALL_RESULT=$((OVERALL_RESULT + 1))
fi

log "INFO" "Comprehensive test log written to: $LOG_FILE"

if [[ $OVERALL_RESULT -eq 0 ]]; then
    log "PASS" "All tests passed successfully!"
    exit 0
else
    log "FAIL" "Some tests failed. See above for details."
    exit 1
fi 