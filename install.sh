#!/usr/bin/env bash
#
# Install script for loglyze

set -e

# Check if script is run as root
if [[ $EUID -ne 0 ]]; then
   echo "This script must be run as root (sudo)"
   exit 1
fi

# Installation directory
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

# Security: Check for file existence without following symlinks
secure_file_exists() {
    [[ -f "$1" && ! -L "$1" ]]
}

# Security: Secure file copy with permission setting
install_file() {
    local src="$1" dest="$2" mode="$3"
    if [[ ! -f "$src" ]]; then
        echo "Error: Source file does not exist: $src"
        exit 1
    fi
    cp "$src" "$dest"
    chmod "$mode" "$dest"
}

# Security: Secure directory creation with permission setting
secure_mkdir() {
    local dir="$1" mode="$2"
    mkdir -p "$dir"
    chmod "$mode" "$dir"
}

# Check if LogLyze is already installed
if secure_file_exists "$INSTALL_DIR/loglyze"; then
    echo "LogLyze appears to be already installed at $INSTALL_DIR/loglyze"
    read -p "Do you want to reinstall? [y/N] " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Installation canceled."
        exit 0
    fi
    echo "Proceeding with reinstallation..."
fi

echo "Installing LogLyze..."

# Create directories with secure permissions
secure_mkdir "$INSTALL_DIR" 0755
secure_mkdir "$CONFIG_DIR" 0755
secure_mkdir "$DOC_DIR" 0755

# Install the main executable with secure permissions
install_file "bin/loglyze" "$INSTALL_DIR/loglyze" 0755

# Install documentation with secure permissions
install_file "README.md" "$DOC_DIR/README.md" 0644
if [[ -d "docs" ]]; then
    cp -r docs/* "$DOC_DIR/"
    # Set permissions on all documentation files
    find "$DOC_DIR" -type f -exec chmod 0644 {} \;
    find "$DOC_DIR" -type d -exec chmod 0755 {} \;
fi

# Create empty config files with secure permissions
if [[ ! -f "$CONFIG_DIR/loglyze.conf" ]]; then
    cat > "$CONFIG_DIR/loglyze.conf" << EOF
# loglyze configuration file

# Set default verbosity (true/false)
VERBOSE=false

# Set default color mode (true/false)
COLOR=true
EOF
    chmod 0644 "$CONFIG_DIR/loglyze.conf"
fi

if [[ ! -f "$CONFIG_DIR/formats.conf" ]]; then
    cat > "$CONFIG_DIR/formats.conf" << EOF
# Custom log formats for loglyze
# You can define your own log formats here
# Format: LOG_FORMATS["name"]="field1 field2 field3"
# Pattern: LOG_FORMATS["name_pattern"]="regex pattern"

# Example custom format:
# LOG_FORMATS["app_log"]="timestamp level message"
# LOG_FORMATS["app_log_pattern"]='^([0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}:[0-9]{2}) ([A-Z]+) (.*)$'
EOF
    chmod 0644 "$CONFIG_DIR/formats.conf"
fi

echo "Installation complete!"
echo "LogLyze installed to $INSTALL_DIR/loglyze"
echo "Configuration files are in $CONFIG_DIR"
echo "Documentation is in $DOC_DIR"
echo ""
echo "You can now use loglyze by typing:"
echo "  loglyze /path/to/logfile"
echo ""
echo "For help, type:"
echo "  loglyze -h" 