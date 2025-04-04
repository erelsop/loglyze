# LogLyze

**DISCLAIMER:** This tool is new and under active development and should not be used in production. If you would like to contribute then please reach out!

A powerful command-line tool for analyzing log files with support for multiple log formats, flexible parsing, and interactive exploration.

## Features

- **Summary overview**: Get immediate statistics about your logs including total entries, errors/warnings count, and time range.
- **Flexible parsing**: Automatically detect and parse various log formats or define custom formats.
- **Frequency analysis**: Quickly identify the most frequent errors in your logs.
- **Time-based filtering**: Analyze logs within specific time windows.
- **Interactive mode**: Navigate through large log files with ease, including page-based navigation.
- **Multiple output formats**: Generate output as text with syntax highlighting or export to CSV.
- **Filter-aware CSV export**: Export only filtered logs or the entire file, with filter metadata included.
- **Anomaly detection**: Set thresholds for detecting unusual patterns in your logs.
- **Node.js Integration**: Use LogLyze directly in your Node.js applications.
- **TypeScript Support**: First-class TypeScript support with separate type declarations.

## System Requirements

### Operating System Compatibility

- **Linux**: Fully supported and tested on Ubuntu. Should work on most Linux distributions.
- **macOS**: Should work with minimal issues as macOS includes Bash and most Unix utilities, but has not been extensively tested.
- **Windows**: Not natively supported. Requires Windows Subsystem for Linux (WSL), Git Bash, Cygwin, or a similar Unix-like environment.

### Dependencies

LogLyze requires:
- Bash shell (version 4.0 or higher recommended)
- Common Unix utilities: grep, awk, sed, sort, uniq
- Optional: jq (for better JSON log parsing)
- For Node.js usage: Node.js v12.0.0 or higher

## Installation

### Quick Installation (System-wide)

For a full system-wide installation that adds LogLyze to your PATH and sets up appropriate configuration files:

1. Clone this repository:
   ```bash
   git clone https://github.com/erelsop/loglyze.git
   cd loglyze
   ```

2. Run the installation script as root:
   ```bash
   sudo ./install.sh
   ```

This will:
- Install the executable to `/usr/local/bin/loglyze` (which is in PATH)
- Create configuration files in `/etc/loglyze`
- Copy the README file to `/usr/local/share/doc/loglyze`

After installation, you can run LogLyze from anywhere by typing `loglyze`.

### Node.js Installation

To use LogLyze in your Node.js applications:

```bash
npm install loglyze
```

This will:
- Install the LogLyze Node.js wrapper
- Include the LogLyze bash script to ensure it works without any additional dependencies
- Provide TypeScript type definitions for better developer experience

### Uninstallation

If you installed LogLyze using the system-wide installation method and wish to remove it:

1. Navigate to the LogLyze repository directory (or download it again if you no longer have it)
   ```bash
   cd loglyze
   ```

2. Run the uninstallation script as root:
   ```bash
   sudo ./uninstall.sh
   ```

This will safely remove:
- The LogLyze executable from `/usr/local/bin`
- All configuration files from `/etc/loglyze`
- Documentation from `/usr/local/share/doc/loglyze`

The script will ask for confirmation before removing any files.

## Usage

### Basic Command Line Usage

Analyze a log file with default settings:

```bash
loglyze /path/to/logfile
```

### Node.js Usage

#### Basic Usage

```javascript
const { LogLyze } = require('loglyze');

// Initialize with default options
const loglyze = new LogLyze();

// Analyze a log file
loglyze.analyze('/path/to/logfile.log')
  .then(result => {
    console.log('Analysis complete!');
    console.log(`Total lines: ${result.summary.totalLines}`);
    console.log(`Error count: ${result.summary.errorCount}`);
    
    // Access top errors
    result.summary.topErrors.forEach(error => {
      console.log(`${error.occurrences} occurrences: ${error.message}`);
    });
  })
  .catch(err => {
    console.error('Analysis failed:', err.message);
  });
```

#### Analyzing Log Data from a String

```javascript
const { LogLyze } = require('loglyze');

// Initialize with custom options
const loglyze = new LogLyze({
  showLogs: true,
  errorsOnly: true
});

// Sample log data
const logData = `
2023-09-01 12:00:00 INFO Server started
2023-09-01 12:01:15 ERROR Database connection failed
2023-09-01 12:02:30 WARNING Slow query detected
`;

// Analyze string data
loglyze.analyzeString(logData)
  .then(result => {
    // Process structured data
    console.log(`Found ${result.summary.errorCount} errors`);
  });
```

#### TypeScript Usage

```typescript
// Import the LogLyze class and types
import { LogLyze } from 'loglyze';
import { LogLyzeOptions, LogLyzeResult } from 'loglyze';

// Configure options
const options: LogLyzeOptions = {
  showLogs: true,
  limit: 100
};

// Initialize LogLyze
const loglyze = new LogLyze(options);

// Analyze logs
async function analyzeMyLogs() {
  try {
    const result: LogLyzeResult = await loglyze.analyze('/path/to/logfile.log');
    console.log(result.summary);
  } catch (error) {
    console.error('Analysis failed:', error);
  }
}

analyzeMyLogs();
```

### Command-Line Options

```
Usage: loglyze [options] /path/to/logfile

Options:
    -h, --help              Display this help message
    -v, --verbose           Enable verbose output for debugging
    --show-logs             Display log content (by default only summary is shown)
    -i, --interactive       Display logs in an interactive paged view
    -c, --csv               Export results as CSV (after summary)
    --csv-only              Export results as CSV only (no summary, ideal for redirection)
    -f, --from "TIMESTAMP"  Filter logs from this timestamp (format: YYYY-MM-DD HH:MM:SS)
    -t, --to "TIMESTAMP"    Filter logs to this timestamp (format: YYYY-MM-DD HH:MM:SS)
    -e, --errors-only       Show only error entries
    -l, --limit NUMBER      Limit output to NUMBER entries (defaults to 20 when showing logs)
    -s, --sample            Sample log entries instead of showing all
    --top-errors NUMBER     Show top NUMBER frequent errors in summary (default: 5)
```

### Examples

1. Show summary with default 5 top errors:
   ```bash
   loglyze error.log
   ```

2. Show summary with top 10 most frequent errors:
   ```bash
   loglyze --top-errors 10 error.log
   ```

3. Show errors with log content:
   ```bash
   loglyze -e --show-logs error.log
   ```

4. Filter logs by a specific time window:
   ```bash
   loglyze -f "2025-10-15 10:00:00" -t "2025-10-15 12:00:00" --show-logs app.log
   ```

5. Export analysis results to CSV with summary information:
   ```bash
   loglyze -c error.log > analysis.csv
   ```

6. Export pure CSV data without summary (ideal for data processing):
   ```bash
   loglyze --csv-only error.log > clean_data.csv
   ```

7. Process logs in a Node.js application:
   ```javascript
   const { LogLyze } = require('loglyze');
   
   // Filter logs from a specific time
   const loglyze = new LogLyze({
     from: '2023-09-01 12:00:00',
     errorsOnly: true
   });
   
   // Analyze and process results
   loglyze.analyze('error.log')
     .then(result => {
       // Do something with the structured data
       console.log(result.summary);
     });
   ```

## Node.js API Reference

### Type Definitions

LogLyze provides a comprehensive set of TypeScript type definitions in a separate module for better organization:

```typescript
// Import all types
import { LogLyzeOptions, LogLyzeResult, LogEntry, TopError } from 'loglyze';

// Or import the specific types you need
import { LogLyzeOptions } from 'loglyze';
```

### Class: LogLyze

The main class that provides access to the log analysis functionality.

#### Constructor

```typescript
new LogLyze(options?: LogLyzeOptions);
```

**Options Interface:**

```typescript
interface LogLyzeOptions {
  verbose?: boolean;
  showLogs?: boolean;
  interactive?: boolean;
  csv?: boolean;
  csvOnly?: boolean;
  errorsOnly?: boolean;
  limit?: number | null;
  sample?: boolean;
  topErrors?: number;
  from?: string | null;
  to?: string | null;
}
```

#### Methods

##### analyze(logFile: string, options?: LogLyzeOptions): Promise<LogLyzeResult>

Analyzes a log file and returns a promise that resolves to the analysis results.

- `logFile`: Path to the log file to analyze
- `options`: Override default options for this analysis only

##### analyzeString(logData: string, options?: LogLyzeOptions): Promise<LogLyzeResult>

Analyzes log data from a string and returns a promise that resolves to the analysis results.

- `logData`: Log data as a string
- `options`: Override default options for this analysis only

##### getOptions(): LogLyzeOptions

Returns the current options.

##### setOptions(options: LogLyzeOptions): void

Updates the options.

#### Return Value Structure

The `analyze` and `analyzeString` methods return a promise that resolves to an object with the following structure:

```typescript
interface LogLyzeResult {
  summary: {
    file: string | null;
    totalLines: number;
    errorCount: number;
    warningCount: number;
    infoCount: number;
    timeRange: {
      start: string | null;
      end: string | null;
    };
    topErrors: Array<{
      occurrences: number;
      message: string;
    }>;
  };
  logs: Array<{
    raw: string;
    severity: string;
    timestamp?: string;
    message?: string;
  }>;
  csv?: Array<{
    timestamp: string;
    severity: string;
    message: string;
    [key: string]: string;
  }>;
  rawOutput: string;
  rawError: string;
}
```

## Interactive Mode

LogLyze provides a fully functional interactive mode that allows you to navigate, filter, and explore your log files with ease.

To enter interactive mode, use the `-i` flag:

```bash
loglyze -i server.log
```

### Interactive Mode Commands

- **Navigation:**
  - **Arrow keys (Up/Down)**: Navigate up and down through log entries
  - **g**: Go to a specific page number
  
- **Filtering:**
  - **f**: Filter on a pattern in logs
  - **e**: Show only ERROR entries
  - **c**: Show all entries (clear filters)
  - **r**: Filter by time range
  
- **Time Navigation:**
  - **t**: Jump to specific timestamp
  
- **Actions:**
  - **s**: Show summary statistics
  - **x**: Export current view to CSV
  - **h**: Show help screen with all commands
  - **q**: Quit interactive mode

The interactive mode provides color-coded log entries based on severity level for better readability:
- **ERROR** entries are displayed in red
- **WARNING** entries are displayed in yellow
- **INFO** entries are displayed in green
- **DEBUG** entries are displayed in cyan

This makes it easier to quickly identify important log entries and patterns within your logs.

### CSV Export in Interactive Mode

The interactive mode allows you to export log entries to CSV format with awareness of your current filters:

1. While in interactive mode, press **x** to initiate CSV export
2. If filters are active, you'll see a summary of current filters and their effects
3. Choose between:
   - Exporting only the filtered logs (default)
   - Exporting the entire log file
4. Enter a filename for the export (default: loglyze_export.csv)

The exported CSV file will include:
- Headers: timestamp, severity, message
- Comments with filter information (when exporting filtered logs)
- All visible data from your current filtered view (or the full log if selected)

This makes it easy to further analyze your filtered data in spreadsheets or other tools.

## Customization

### Log Formats

LogLyze automatically detects common log formats, but you can define custom formats in `config/formats.conf`:

```bash
# Example custom format for a Rails application log
LOG_FORMATS["rails_log"]="timestamp severity request_id message"
LOG_FORMATS["rails_log_pattern"]='^([0-9TZ:.-]+) +([A-Z]+) +([a-z0-9-]+) +(.*)$'
```

The following predefined formats are included:
- Spring Boot logs
- Node.js logs with Winston
- Django logs
- Apache Common Log Format
- Apache Combined Log Format
- Nginx Access Log
- Common JSON Logs
- Simple Log Format (timestamp severity message)

### Configuration

Edit `config/loglyze.conf` to customize default behavior:

```bash
# Example: Increase default entries per page in interactive mode
ENTRIES_PER_PAGE=30

# Example: Enable verbose logging
VERBOSE=true

# Example: Set custom severity levels to detect
SEVERITY_LEVELS=("ERROR" "WARN" "WARNING" "INFO" "DEBUG" "TRACE" "FATAL")

# Example: Change default error threshold for anomaly detection
ERROR_THRESHOLD=50

# Example: Change default interval for time-based metrics
DEFAULT_TIME_INTERVAL="hour"
```

## Extending LogLyze

LogLyze is designed with modularity in mind, making it easy to add new features:

1. To add a new log format detector, add patterns to the `parser.sh` module.
2. To create a new output format, add a formatter to the `formatter.sh` module.
3. To add new interactive commands, modify the `interactive_mode.sh` module.

## Project Structure

```
loglyze/
├── bin/
│   └── loglyze               # Main executable (Bash script)
├── src/
│   ├── lib/
│   │   ├── index.ts          # Main TypeScript API implementation
│   │   └── types.ts          # TypeScript type definitions
│   ├── bin/
│   │   ├── loglyze           # Bundled Bash script
│   │   └── cli.ts            # Node.js CLI entry point
│   └── examples/
│       └── simple-usage.ts   # Example usage in TypeScript
├── lib/
│   ├── colors.sh             # Terminal color definitions 
│   ├── core.sh               # Core functionality and utilities
│   ├── formatter.sh          # Output formatting (text, CSV, etc.)
│   ├── interactive_mode.sh   # Interactive mode functionality
│   ├── logger.sh             # Logging utilities
│   ├── parser.sh             # Log format detection and parsing
│   └── time_utils.sh         # Timestamp parsing and filtering
├── config/
│   ├── loglyze.conf          # Main configuration
│   └── formats.conf          # Custom log format definitions
├── build/                    # Compiled TypeScript output
├── tests/                    # Test files
│   └── loglyze.test.ts       # Main test suite
├── tsconfig.json             # TypeScript configuration
├── package.json              # Node.js package definition
├── install.sh                # System-wide installation script
└── uninstall.sh              # System-wide uninstallation script
```

## Architecture and Design

LogLyze follows a well-organized architecture that separates concerns and promotes maintainability:

### Shell Script Core

The core functionality is implemented in Bash for maximum compatibility with Unix-like systems:

- `bin/loglyze`: The main entry point script
- `lib/*.sh`: Modular shell scripts that implement specific features

### Node.js Integration

The TypeScript/JavaScript integration layer follows modern practices:

- **Separation of Types**: All TypeScript interfaces are defined in a dedicated `types.ts` file
- **Clean API Surface**: The main `index.ts` file provides a clean, well-documented API
- **CLI Interface**: The `cli.ts` file provides command-line functionality

This architecture allows for easy maintenance and extension of both the shell script core and the Node.js integration layer.

## Security

LogLyze is designed with security in mind. Several measures have been implemented to prevent common vulnerabilities:

- Secure input validation to prevent command injection
- Path traversal prevention
- Secure temporary file handling
- File permission controls
- Output sanitization for various formats