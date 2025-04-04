#!/bin/bash
#
# Comprehensive test script for loglyze shell functionality
# Tests core functionality without using the Node.js wrapper

# Don't exit on error to allow testing to continue
set +e

# Define colors for reporting
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[0;33m'
NC='\033[0m' # No Color

# Get the script directory
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PROJECT_ROOT="$( cd "$SCRIPT_DIR/.." && pwd )"

# Path to log files for testing
SAMPLE_LOG="$PROJECT_ROOT/samples/simple.log"
SAMPLE_LOG_2="$PROJECT_ROOT/samples/spring_boot.log"

# Path to the main loglyze script
LOGLYZE_BIN="$PROJECT_ROOT/bin/loglyze"

# Keep track of tests
TESTS_PASSED=0
TESTS_FAILED=0
TESTS_SKIPPED=0

# Test output directory
TEST_OUTPUT_DIR="$PROJECT_ROOT/tests/output"
mkdir -p "$TEST_OUTPUT_DIR"

# Test file for output
TEST_OUTPUT_FILE="$TEST_OUTPUT_DIR/test_output.log"
rm -f "$TEST_OUTPUT_FILE"

# Helper function to run a test with timeout
run_test() {
    local test_name="$1"
    local test_cmd="$2"
    local expected_success="${3:-true}"
    local timeout_seconds=10
    
    echo -e "${YELLOW}Running test: $test_name${NC}"
    echo "Command: $test_cmd"
    echo
    
    # Run the command with timeout
    timeout "$timeout_seconds" bash -c "$test_cmd" > "$TEST_OUTPUT_FILE" 2>&1
    result=$?
    
    # Check if the command timed out
    if [[ $result -eq 124 ]]; then
        echo -e "${RED}FAIL: $test_name - Command timed out after ${timeout_seconds} seconds${NC}"
        echo "Last lines of output:"
        tail -n 10 "$TEST_OUTPUT_FILE"
        ((TESTS_FAILED++))
        echo "--------------------------------------"
        echo
        return
    fi
    
    # Determine success based on exit code
    if [[ $result -eq 0 ]]; then
        success=true
    else
        success=false
    fi
    
    # Always show the output for debugging
    echo "Command output:"
    cat "$TEST_OUTPUT_FILE"
    echo
    
    # Check if the result matches expectations
    if [[ "$success" == "$expected_success" ]]; then
        echo -e "${GREEN}PASS: $test_name${NC}"
        ((TESTS_PASSED++))
    else
        echo -e "${RED}FAIL: $test_name${NC}"
        echo "Expected success: $expected_success, Got: $success"
        echo "Exit code: $result"
        ((TESTS_FAILED++))
    fi
    
    echo "--------------------------------------"
    echo
}

# Test with custom assertion and timeout
run_test_with_assertion() {
    local test_name="$1"
    local test_cmd="$2"
    local assertion_cmd="$3"
    local timeout_seconds=10
    
    echo -e "${YELLOW}Running test: $test_name${NC}"
    echo "Command: $test_cmd"
    echo "Assertion: $assertion_cmd"
    echo
    
    # Run the command with timeout
    timeout "$timeout_seconds" bash -c "$test_cmd" > "$TEST_OUTPUT_FILE" 2>&1
    result=$?
    
    # Check if the command timed out
    if [[ $result -eq 124 ]]; then
        echo -e "${RED}FAIL: $test_name - Command timed out after ${timeout_seconds} seconds${NC}"
        echo "Last lines of output:"
        tail -n 10 "$TEST_OUTPUT_FILE"
        ((TESTS_FAILED++))
        echo "--------------------------------------"
        echo
        return
    fi
    
    # Show command output regardless of success/failure
    echo "Command output:"
    cat "$TEST_OUTPUT_FILE"
    echo
    
    if [[ $result -eq 0 ]]; then
        # Only run the assertion if the command succeeded
        if eval "$assertion_cmd"; then
            echo -e "${GREEN}PASS: $test_name${NC}"
            ((TESTS_PASSED++))
        else
            echo -e "${RED}FAIL: $test_name - Assertion failed${NC}"
            ((TESTS_FAILED++))
        fi
    else
        echo -e "${RED}FAIL: $test_name - Command failed with exit code $result${NC}"
        ((TESTS_FAILED++))
    fi
    
    echo "--------------------------------------"
    echo
}

# Print header
echo "======================================================"
echo "     LogLyze Shell Tests - Starting Test Suite"
echo "======================================================"
echo

# Ensure the sample logs exist
if [[ ! -f "$SAMPLE_LOG" ]]; then
    echo -e "${RED}ERROR: Sample log file not found: $SAMPLE_LOG${NC}"
    exit 1
fi

if [[ ! -f "$SAMPLE_LOG_2" ]]; then
    echo -e "${RED}ERROR: Sample log file 2 not found: $SAMPLE_LOG_2${NC}"
    exit 1
fi

# Ensure the loglyze binary exists
if [[ ! -f "$LOGLYZE_BIN" ]]; then
    echo -e "${RED}ERROR: LogLyze binary not found: $LOGLYZE_BIN${NC}"
    exit 1
fi

echo "Using sample log: $SAMPLE_LOG"
echo "Using sample log 2: $SAMPLE_LOG_2"
echo "Using binary: $LOGLYZE_BIN"
echo

# Test 1: Basic help command
run_test "Help command" \
    "$LOGLYZE_BIN --help"

# Skip version command since it's not implemented
echo -e "${YELLOW}Skipping version command test (not implemented)${NC}"
((TESTS_SKIPPED++))

# Test 2: Basic log analysis
run_test "Basic log analysis" \
    "$LOGLYZE_BIN $SAMPLE_LOG"

# Test 3: Error-only filtering
run_test_with_assertion "Error-only filtering" \
    "$LOGLYZE_BIN -e $SAMPLE_LOG" \
    "grep -q 'ERROR\\|error\\|errors' '$TEST_OUTPUT_FILE'"

# Test 4: Time-based filtering (from)
run_test_with_assertion "Time-based filtering (from)" \
    "$LOGLYZE_BIN --show-logs -f '2023-10-15 12:00:00' $SAMPLE_LOG" \
    "grep -q '2023-10-15' '$TEST_OUTPUT_FILE'"

# Test 5: Time-based filtering (to)
run_test_with_assertion "Time-based filtering (to)" \
    "$LOGLYZE_BIN --show-logs -t '2023-10-15 12:00:00' $SAMPLE_LOG" \
    "grep -q '2023-10-15' '$TEST_OUTPUT_FILE'"

# Test 6: Time-based filtering (range)
run_test_with_assertion "Time-based filtering (range)" \
    "$LOGLYZE_BIN --show-logs -f '2023-10-15 08:00:00' -t '2023-10-15 08:30:00' $SAMPLE_LOG" \
    "grep -q '2023-10-15' '$TEST_OUTPUT_FILE'"

# Test 7: CSV export (use a manual approach since -o flag might not be implemented)
CSV_OUTPUT="$TEST_OUTPUT_DIR/test_export.csv"
rm -f "$CSV_OUTPUT"
run_test_with_assertion "CSV export" \
    "$LOGLYZE_BIN -c $SAMPLE_LOG > '$CSV_OUTPUT'" \
    "[ -s '$CSV_OUTPUT' ] && cat '$CSV_OUTPUT' | grep -q 'timestamp\\|severity\\|message'"

# Test 8: Multiple logs with different formats
run_test "Multiple logs analysis" \
    "$LOGLYZE_BIN $SAMPLE_LOG $PROJECT_ROOT/samples/json.log"

# Test 9: Error-only filtering on multiple logs
run_test_with_assertion "Error-only filtering on multiple logs" \
    "$LOGLYZE_BIN -e $SAMPLE_LOG $SAMPLE_LOG_2" \
    "grep -q 'ERROR\\|error\\|errors' '$TEST_OUTPUT_FILE'"

# Test 10: CSV export with error-only filtering (manual redirection)
ERROR_CSV_OUTPUT="$TEST_OUTPUT_DIR/error_export.csv"
rm -f "$ERROR_CSV_OUTPUT"
run_test_with_assertion "CSV export with error-only filtering" \
    "$LOGLYZE_BIN -e -c $SAMPLE_LOG > '$ERROR_CSV_OUTPUT'" \
    "[ -s '$ERROR_CSV_OUTPUT' ] && cat '$ERROR_CSV_OUTPUT' | grep -q 'ERROR'"

# Test 11: Summary generation
run_test_with_assertion "Summary generation" \
    "$LOGLYZE_BIN -s $SAMPLE_LOG" \
    "grep -q 'Summary\\|statistics\\|Analysis\\|Log entries' '$TEST_OUTPUT_FILE'"

# Test 12: Interactive mode (basic test - just make sure it starts)
# Skip this test since we have a dedicated expect script for it
echo -e "${YELLOW}Skipping interactive mode test (tested separately with expect script)${NC}"
((TESTS_SKIPPED++))

# Test 13: Show logs option
run_test_with_assertion "Show logs option" \
    "$LOGLYZE_BIN --show-logs $SAMPLE_LOG" \
    "grep -q '2023-10-15' '$TEST_OUTPUT_FILE'"

# Test 14: Test a complex format - AWS CloudTrail
run_test_with_assertion "AWS CloudTrail format" \
    "$LOGLYZE_BIN --show-logs $PROJECT_ROOT/samples/aws_cloudtrail.log" \
    "grep -q 'eventName\\|userIdentity\\|eventSource' '$TEST_OUTPUT_FILE'"

# Test 15: Test another complex format - Java Stacktrace
run_test_with_assertion "Java Stacktrace format" \
    "$LOGLYZE_BIN --show-logs $PROJECT_ROOT/samples/java_stacktrace.log" \
    "grep -q 'Exception\\|NullPointerException\\|SQLException' '$TEST_OUTPUT_FILE'"

echo
echo "======================================================"
echo "     LogLyze Shell Tests - Summary"
echo "======================================================"
echo
echo -e "${GREEN}Tests passed: $TESTS_PASSED${NC}"
echo -e "${RED}Tests failed: $TESTS_FAILED${NC}"
echo -e "${YELLOW}Tests skipped: $TESTS_SKIPPED${NC}"
echo
echo "Total tests: $((TESTS_PASSED + TESTS_FAILED + TESTS_SKIPPED))"
echo

# Return appropriate exit code
if [[ $TESTS_FAILED -eq 0 ]]; then
    echo -e "${GREEN}All tests passed successfully!${NC}"
    exit 0
else
    echo -e "${RED}Some tests failed!${NC}"
    exit 1
fi 