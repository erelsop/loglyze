#!/usr/bin/env bash
#
# Uninstall script for LogLyze

set -e

# Check if script is run as root
if [[ $EUID -ne 0 ]]; then
   echo "This script must be run as root (sudo)"
   exit 1
fi

# Installation directories to clean up
INSTALL_DIR="/usr/local/bin"
CONFIG_DIR="/etc/loglyze"
DOC_DIR="/usr/local/share/doc/loglyze"

# Security: Validate paths to ensure they don't contain potentially dangerous patterns
validate_path() {
    local path="$1"
    if [[ "$path" =~ [[:space:]] || "$path" =~ \.\. ]]; then
        echo "Error: Invalid path detected: $path"
        exit 1
    fi
    return 0
}

validate_path "$INSTALL_DIR"
validate_path "$CONFIG_DIR"
validate_path "$DOC_DIR"

# Security: Check for file/directory existence without following symlinks
secure_file_exists() {
    [[ -f "$1" && ! -L "$1" ]]
}

secure_dir_exists() {
    [[ -d "$1" && ! -L "$1" ]]
}

# Security: Safe removal function
secure_remove() {
    local path="$1"
    validate_path "$path"
    
    if [[ -f "$path" && ! -L "$path" ]]; then
        rm -f "$path"
    elif [[ -d "$path" && ! -L "$path" ]]; then
        rm -rf "$path"
    else
        echo "Warning: Not removing $path (may be a symlink)"
    fi
}

# Check if LogLyze is installed
if [[ ! -f "$INSTALL_DIR/loglyze" && ! -d "$CONFIG_DIR" && ! -d "$DOC_DIR" ]]; then
    echo "LogLyze does not appear to be installed on this system."
    echo "Nothing to uninstall."
    exit 0
fi

echo "This will uninstall LogLyze from your system."
echo "The following components will be removed:"

# List only components that exist
secure_file_exists "$INSTALL_DIR/loglyze" && echo "  - $INSTALL_DIR/loglyze (executable)"
secure_dir_exists "$CONFIG_DIR" && echo "  - $CONFIG_DIR (configuration files)"
secure_dir_exists "$DOC_DIR" && echo "  - $DOC_DIR (documentation)"
echo

# Ask for confirmation
read -p "Are you sure you want to continue? [y/N] " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Uninstall canceled."
    exit 0
fi

# Remove the executable
if secure_file_exists "$INSTALL_DIR/loglyze"; then
    echo "Removing executable from $INSTALL_DIR..."
    secure_remove "$INSTALL_DIR/loglyze"
else
    echo "Executable not found in $INSTALL_DIR. Skipping."
fi

# Remove configuration directory
if secure_dir_exists "$CONFIG_DIR"; then
    echo "Removing configuration files from $CONFIG_DIR..."
    secure_remove "$CONFIG_DIR"
else
    echo "Configuration directory not found. Skipping."
fi

# Remove documentation
if secure_dir_exists "$DOC_DIR"; then
    echo "Removing documentation from $DOC_DIR..."
    secure_remove "$DOC_DIR"
else
    echo "Documentation directory not found. Skipping."
fi

echo
echo "LogLyze has been successfully uninstalled from your system."
echo "Your log files and any analysis results have not been affected." 