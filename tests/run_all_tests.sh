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

# Print header
echo -e "${BLUE}======================================================${NC}"
echo -e "${BLUE}               Running LogLyze Tests                   ${NC}"
echo -e "${BLUE}======================================================${NC}"
echo

# Helper function to run a test group
run_test_group() {
    local name="$1"
    local command="$2"
    
    echo -e "${YELLOW}Running $name tests...${NC}"
    echo -e "Command: $command"
    echo
    
    if eval "$command"; then
        echo -e "${GREEN}✓ $name tests PASSED${NC}"
        return 0
    else
        echo -e "${RED}✗ $name tests FAILED${NC}"
        return 1
    fi
}

# Check for expect command for interactive tests
if ! command -v expect &> /dev/null; then
    echo -e "${YELLOW}Warning: 'expect' command not found. Interactive tests will be skipped.${NC}"
    echo -e "Install expect with: sudo apt-get install expect (Ubuntu/Debian)"
    echo
    SKIP_INTERACTIVE=1
else
    SKIP_INTERACTIVE=0
fi

# Track test results
NODE_TESTS_RESULT=0
SHELL_TESTS_RESULT=0
INTERACTIVE_TESTS_RESULT=0

# 1. Run Node.js Jest tests
echo -e "${BLUE}[1/3] Node.js Tests${NC}"
if ! run_test_group "Node.js" "npm test"; then
    NODE_TESTS_RESULT=1
fi
echo

# 2. Run shell tests
echo -e "${BLUE}[2/3] Shell Tests${NC}"
if ! run_test_group "Shell" "$SCRIPT_DIR/shell_test.sh"; then
    SHELL_TESTS_RESULT=1
fi
echo

# 3. Run interactive tests if expect is available
echo -e "${BLUE}[3/3] Interactive Tests${NC}"
if [[ $SKIP_INTERACTIVE -eq 1 ]]; then
    echo -e "${YELLOW}Skipping interactive tests (expect command not available)${NC}"
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
    echo -e "Node.js Tests:     ${GREEN}PASSED${NC}"
else
    echo -e "Node.js Tests:     ${RED}FAILED${NC}"
fi

if [[ $SHELL_TESTS_RESULT -eq 0 ]]; then
    echo -e "Shell Tests:       ${GREEN}PASSED${NC}"
else
    echo -e "Shell Tests:       ${RED}FAILED${NC}"
fi

if [[ $SKIP_INTERACTIVE -eq 1 ]]; then
    echo -e "Interactive Tests: ${YELLOW}SKIPPED${NC}"
elif [[ $INTERACTIVE_TESTS_RESULT -eq 0 ]]; then
    echo -e "Interactive Tests: ${GREEN}PASSED${NC}"
else
    echo -e "Interactive Tests: ${RED}FAILED${NC}"
fi

echo

# Overall result
OVERALL_RESULT=$((NODE_TESTS_RESULT + SHELL_TESTS_RESULT + INTERACTIVE_TESTS_RESULT))

if [[ $OVERALL_RESULT -eq 0 ]]; then
    echo -e "${GREEN}All tests passed successfully!${NC}"
    exit 0
else
    echo -e "${RED}Some tests failed. See above for details.${NC}"
    exit 1
fi 