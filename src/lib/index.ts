/**
 * LogLyze - A powerful log analysis tool with Node.js integration
 */
import { spawn, spawnSync } from 'child_process';
import path from 'path';
import fs from 'fs';
import os from 'os';

// Import types from the types file
// Note: We don't use LogEntry and LogLyzeSummary directly, but they're part of the LogLyzeResult
import {
  LogLyzeOptions,
  TopError,
  CsvRecord,
  LogLyzeResult
} from './types';

// Re-export types for consumers of the library
export * from './types';

export class LogLyze {
  private loglyzeScriptPath: string | null;
  private defaultOptions: LogLyzeOptions;
  private options: LogLyzeOptions;

  constructor(options: LogLyzeOptions = {}) {
    // Find the loglyze script path
    this.loglyzeScriptPath = this._findLoglyzeScript();
    this.defaultOptions = {
      verbose: false,
      showLogs: false,
      interactive: false,
      csv: false,
      csvOnly: false,
      errorsOnly: false,
      limit: null,
      sample: false,
      topErrors: 5,
      from: null,
      to: null
    };
    
    // Merge default options with user provided options
    this.options = { ...this.defaultOptions, ...options };
    
    if (!this.loglyzeScriptPath) {
      throw new Error('LogLyze script not found. Make sure it is installed correctly.');
    }
    
    // Check if we're on a supported platform
    if (os.platform() === 'win32') {
      throw new Error('Windows is not supported by LogLyze. Use WSL, Git Bash, or Cygwin.');
    }
  }
  
  /**
   * Find the loglyze script path
   * @returns Path to the loglyze script
   * @private
   */
  private _findLoglyzeScript(): string | null {
    // Try to find loglyze in different locations
    const possiblePaths = [
      // First check bundled version
      path.resolve(__dirname, '..', '..', 'bin', 'loglyze'),
      // Then check system-wide installs
      '/usr/local/bin/loglyze',
      '/usr/bin/loglyze',
      // Add more possible locations if needed
    ];
    
    for (const scriptPath of possiblePaths) {
      if (fs.existsSync(scriptPath)) {
        return scriptPath;
      }
    }
    
    return null;
  }
  
  /**
   * Build command arguments based on options
   * @param logFile Path to the log file to analyze
   * @returns Array of command arguments
   * @private
   */
  private _buildArgs(logFile?: string): string[] {
    const args: string[] = [];
    
    if (this.options.verbose) args.push('-v');
    if (this.options.showLogs) args.push('--show-logs');
    if (this.options.interactive) args.push('-i');
    if (this.options.csv) args.push('-c');
    if (this.options.csvOnly) args.push('--csv-only');
    if (this.options.errorsOnly) args.push('-e');
    if (this.options.limit) {
      args.push('-l', this.options.limit.toString());
    }
    if (this.options.sample) args.push('-s');
    if (this.options.topErrors && this.options.topErrors !== 5) {
      args.push('--top-errors', this.options.topErrors.toString());
    }
    if (this.options.from) args.push('-f', this.options.from);
    if (this.options.to) args.push('-t', this.options.to);
    
    // Add the log file path
    if (logFile) args.push(logFile);
    
    return args;
  }
  
  /**
   * Analyze a log file
   * @param logFile Path to the log file to analyze
   * @param options Override default options for this analysis
   * @returns Analysis results
   */
  async analyze(logFile: string, options: LogLyzeOptions = {}): Promise<LogLyzeResult> {
    // Merge options for this analysis
    const analysisOptions = { ...this.options, ...options };
    this.options = analysisOptions;
    
    // Build arguments
    const args = this._buildArgs(logFile);
    
    // Handle interactive mode with direct shell execution
    if (this.options.interactive) {
      return new Promise<LogLyzeResult>((resolve, reject) => {
        if (!this.loglyzeScriptPath) {
          reject(new Error('LogLyze script not found. Make sure it is installed correctly.'));
          return;
        }
        
        try {
          // Execute directly with stdio: 'inherit' to properly handle the terminal
          const result = spawnSync(this.loglyzeScriptPath, args, {
            stdio: 'inherit',
            shell: false
          });
          
          // Create a minimal result object after interactive mode completes
          resolve({
            summary: {
              file: logFile,
              totalLines: 0,
              errorCount: 0,
              warningCount: 0,
              infoCount: 0,
              timeRange: { start: null, end: null },
              topErrors: []
            },
            logs: [],
            rawOutput: `Interactive mode exited with code ${result.status || 0}`,
            rawError: ''
          });
        } catch (error) {
          reject(new Error(`Failed to start interactive mode: ${error instanceof Error ? error.message : String(error)}`));
        }
      });
    }
    
    // Non-interactive mode uses regular child_process.spawn
    return new Promise<LogLyzeResult>((resolve, reject) => {
      if (!this.loglyzeScriptPath) {
        reject(new Error('LogLyze script not found. Make sure it is installed correctly.'));
        return;
      }
      
      let stdout = '';
      let stderr = '';
      
      const loglyze = spawn(this.loglyzeScriptPath, args);
      
      loglyze.stdout.on('data', (data: Buffer) => {
        stdout += data.toString();
      });
      
      loglyze.stderr.on('data', (data: Buffer) => {
        stderr += data.toString();
      });
      
      loglyze.on('close', (code: number) => {
        if (code !== 0) {
          reject(new Error(`LogLyze exited with code ${code}: ${stderr}`));
          return;
        }
        
        try {
          // Parse the output
          const result = this._parseOutput(stdout, stderr);
          resolve(result);
        } catch (error) {
          reject(error);
        }
      });
      
      loglyze.on('error', (error: Error) => {
        reject(new Error(`Failed to execute LogLyze: ${error.message}`));
      });
    });
  }
  
  /**
   * Analyze log data from a string
   * @param logData Log data as a string
   * @param options Override default options for this analysis
   * @returns Analysis results
   */
  async analyzeString(logData: string, options: LogLyzeOptions = {}): Promise<LogLyzeResult> {
    const tempFile = path.join(os.tmpdir(), `loglyze-${Date.now()}.log`);
    
    try {
      // Write log data to a temporary file
      fs.writeFileSync(tempFile, logData);
      
      // Analyze the temporary file
      const result = await this.analyze(tempFile, options);
      
      return result;
    } finally {
      // Clean up the temporary file
      try {
        fs.unlinkSync(tempFile);
      } catch (error) {
        console.warn(`Failed to clean up temporary file: ${error instanceof Error ? error.message : 'Unknown error'}`);
      }
    }
  }
  
  /**
   * Parse the output of the loglyze command
   * @param stdout Standard output
   * @param stderr Standard error
   * @returns Parsed results
   * @private
   */
  private _parseOutput(stdout: string, stderr: string): LogLyzeResult {
    // Initial result structure
    const result: LogLyzeResult = {
      summary: {
        file: null,
        totalLines: 0,
        errorCount: 0,
        warningCount: 0,
        infoCount: 0,
        timeRange: {
          start: null,
          end: null
        },
        topErrors: []
      },
      logs: [],
      rawOutput: stdout,
      rawError: stderr
    };
    
    // Parse summary section
    const summaryMatch = stdout.match(/=== Log Summary ===([\s\S]*?)(?:===|$)/);
    if (summaryMatch && summaryMatch[1]) {
      const summaryText = summaryMatch[1];
      
      // Extract file name
      const fileMatch = summaryText.match(/File: (.+)/);
      if (fileMatch) result.summary.file = fileMatch[1].trim();
      
      // Extract counts
      const totalLinesMatch = summaryText.match(/Total Lines: (\d+)/);
      if (totalLinesMatch) result.summary.totalLines = parseInt(totalLinesMatch[1], 10);
      
      const errorCountMatch = summaryText.match(/Error Count: (\d+)/);
      if (errorCountMatch) result.summary.errorCount = parseInt(errorCountMatch[1], 10);
      
      const warningCountMatch = summaryText.match(/Warning Count: (\d+)/);
      if (warningCountMatch) result.summary.warningCount = parseInt(warningCountMatch[1], 10);
      
      const infoCountMatch = summaryText.match(/Info Count: (\d+)/);
      if (infoCountMatch) result.summary.infoCount = parseInt(infoCountMatch[1], 10);
      
      // Extract time range
      const timeRangeMatch = summaryText.match(/Time Range: (.+) to (.+)/);
      if (timeRangeMatch) {
        result.summary.timeRange.start = timeRangeMatch[1].trim();
        result.summary.timeRange.end = timeRangeMatch[2].trim();
      }
    }
    
    // Parse top errors section
    const topErrorsMatch = stdout.match(/=== Top .+ Frequent Errors ===([\s\S]*?)(?:===|$)/);
    if (topErrorsMatch && topErrorsMatch[1]) {
      const topErrorsText = topErrorsMatch[1];
      const errorLines = topErrorsText.trim().split('\n');
      
      result.summary.topErrors = errorLines
        .filter(line => line.trim() && !line.includes("No errors found"))
        .map(line => {
          const match = line.match(/^\s*(\d+) occurrences: (.+)$/);
          if (match) {
            return {
              occurrences: parseInt(match[1], 10),
              message: match[2].trim()
            };
          }
          return null;
        })
        .filter((error): error is TopError => error !== null);
    }
    
    // Parse logs section
    const logsMatch = stdout.match(/=== Log Content ===([\s\S]*?)$/);
    if (logsMatch && logsMatch[1]) {
      const logsText = logsMatch[1];
      const logLines = logsText.trim().split('\n');
      
      // Process log entries - this is a simple approach that could be enhanced
      result.logs = logLines
        .filter(line => line.trim())
        .map(line => {
          // Try to determine severity based on keywords
          let severity = 'UNKNOWN';
          if (line.match(/ERROR|error|FAIL|fail|FATAL|fatal/i)) severity = 'ERROR';
          else if (line.match(/WARN|WARNING|warn|warning/i)) severity = 'WARNING';
          else if (line.match(/INFO|info/i)) severity = 'INFO';
          else if (line.match(/DEBUG|debug/i)) severity = 'DEBUG';
          
          // Try to extract timestamp using regex
          let timestamp: string | undefined;
          const timestampMatch = line.match(/([0-9]{4}-[0-9]{2}-[0-9]{2}[T ][0-9]{2}:[0-9]{2}:[0-9]{2})/);
          if (timestampMatch) {
            timestamp = timestampMatch[1];
          }
          
          return {
            raw: line,
            severity,
            timestamp
          };
        });
    }
    
    // Parse CSV output
    if (this.options.csvOnly) {
      try {
        // Split CSV data into lines
        const csvLines = stdout.trim().split('\n');
        
        if (csvLines.length > 0) {
          // Extract header and data rows
          const header = csvLines[0].split(',').map(h => h.replace(/"/g, '').trim());
          
          // Process each data row
          result.csv = csvLines.slice(1).map(line => {
            // Handle proper CSV parsing with quoted fields
            const fields = line.match(/(".*?"|[^",]+)(?=\s*,|\s*$)/g);
            
            if (!fields) return null;
            
            // Create an object with header keys and row values
            const row: Record<string, string> = {};
            header.forEach((key, index) => {
              const value = fields[index] ? fields[index].replace(/"/g, '') : '';
              row[key] = value;
            });
            
            return row as CsvRecord;
          }).filter((row): row is CsvRecord => row !== null);
        }
      } catch (error) {
        // If CSV parsing fails, just return the raw output
        result.csvParseError = error instanceof Error ? error.message : 'Unknown CSV parsing error';
      }
    }
    
    return result;
  }
  
  /**
   * Get available options
   * @returns Current options
   */
  getOptions(): LogLyzeOptions {
    return { ...this.options };
  }
  
  /**
   * Set options
   * @param options Options to set
   */
  setOptions(options: LogLyzeOptions): void {
    this.options = { ...this.options, ...options };
  }
}

export default LogLyze; 