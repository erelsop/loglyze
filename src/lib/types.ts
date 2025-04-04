/**
 * Type definitions for LogLyze
 */

/**
 * Options for the LogLyze analyzer
 */
export interface LogLyzeOptions {
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

/**
 * Represents a single log entry
 */
export interface LogEntry {
  raw: string;
  severity: string;
  timestamp?: string;
  message?: string;
}

/**
 * Represents a frequently occurring error
 */
export interface TopError {
  occurrences: number;
  message: string;
}

/**
 * Represents a CSV record
 */
export interface CsvRecord {
  timestamp: string;
  severity: string;
  message: string;
  [key: string]: string;
}

/**
 * Summary information for log analysis
 */
export interface LogLyzeSummary {
  file: string | null;
  totalLines: number;
  errorCount: number;
  warningCount: number;
  infoCount: number;
  timeRange: {
    start: string | null;
    end: string | null;
  };
  topErrors: TopError[];
}

/**
 * Results of log analysis
 */
export interface LogLyzeResult {
  summary: LogLyzeSummary;
  logs: LogEntry[];
  csv?: CsvRecord[];
  csvParseError?: string;
  rawOutput: string;
  rawError: string;
} 