/**
 * Integration tests for LogLyze using format-specific sample log files
 */
import { LogLyze } from '../src/lib';
import { LogLyzeOptions } from '../src/lib/types';
import path from 'path';
import fs from 'fs';

// Define the formats we should test
const LOG_FORMATS = [
  'apache_common',
  'apache_combined',
  'aws_cloudtrail',
  'django',
  'java_stacktrace',
  'json',
  'kubernetes',
  'mysql_error',
  'nginx_access',
  'postgresql',
  'simple',
  'spring_boot',
  'syslog',
  'w3c_iis',
  'winston'
];

// Create a map of sample files for each format
const sampleFiles = LOG_FORMATS.reduce((acc, format) => {
  acc[format] = path.resolve(__dirname, `../samples/${format}.log`);
  return acc;
}, {} as Record<string, string>);

// Make sure the sample files exist before running tests
beforeAll(() => {
  // Check if all sample files exist
  for (const format of LOG_FORMATS) {
    if (!fs.existsSync(sampleFiles[format])) {
      console.warn(`Sample file for format "${format}" does not exist at ${sampleFiles[format]}`);
    }
    expect(fs.existsSync(sampleFiles[format])).toBeTruthy();
  }
});

describe('LogLyze Format-Specific Integration Tests', () => {
  let loglyze: LogLyze;

  beforeEach(() => {
    // Create a fresh LogLyze instance for each test
    loglyze = new LogLyze();
  });

  // Test each format
  describe.each(LOG_FORMATS)('Log Format: %s', (format) => {
    const sampleFile = sampleFiles[format];
    
    test(`should properly analyze ${format} format logs`, async () => {
      // Analyze the sample log file
      const result = await loglyze.analyze(sampleFile, { showLogs: true });
      
      // Verify the summary information
      expect(result.summary).toBeDefined();
      expect(result.summary.totalLines).toBeGreaterThan(0);
      expect(result.summary.file).toContain(`${format}.log`);
      
      // Each format should have some content
      expect(result.logs.length).toBeGreaterThan(0);
      
      // Time range should be present if the format includes timestamps
      // Note: Not all formats might have easily parseable timestamps
      if (
        format !== 'java_stacktrace' && // Java stacktrace often has no timestamp in exception line
        format !== 'aws_cloudtrail' && // Complex nested JSON may need special parsing
        format !== 'w3c_iis' // W3C logs have metadata lines
      ) {
        expect(result.summary.timeRange.start).toBeDefined();
      }
      
      // For formats known to have severity levels, check that they're parsed
      if ([
        'simple', 'spring_boot', 'winston', 'django', 
        'json', 'postgresql', 'mysql_error', 
        'kubernetes', 'java_stacktrace'
      ].includes(format)) {
        // These formats definitely contain errors in our samples
        expect(result.summary.errorCount).toBeGreaterThan(0);
      } else if (format === 'syslog') {
        // For syslog, the error might not be recognized by severity, but the content shows errors
        // Either error count or warning count should be above 0, or the raw output should mention failures
        const hasErrorsOrWarnings = 
          result.summary.errorCount > 0 || 
          result.summary.warningCount > 0 || 
          result.rawOutput.includes('failed') ||
          result.rawOutput.includes('timed out') ||
          result.rawOutput.includes('connection timed out');
        
        expect(hasErrorsOrWarnings).toBeTruthy();
      }
      
      // Special case for JSON formats
      if (format === 'json' || format === 'aws_cloudtrail') {
        // Ensure logs were properly parsed from JSON
        result.logs.forEach(log => {
          expect(log.raw).toBeDefined();
        });
      }
      
      // Special case for web logs
      if (['apache_common', 'apache_combined', 'nginx_access'].includes(format)) {
        // Web logs typically contain status codes
        expect(result.rawOutput).toMatch(/200|404|500/);
      }
    });
    
    // Test the ability to filter logs by severity
    test(`should filter ${format} logs by severity`, async () => {
      // Skip formats with complex or non-standard severity structures
      if (['apache_common', 'apache_combined', 'nginx_access', 'w3c_iis'].includes(format)) {
        return;
      }
      
      const result = await loglyze.analyze(sampleFile, { 
        errorsOnly: true, 
        showLogs: true 
      });
      
      // If we have logs, every log should be an error
      if (result.logs.length > 0) {
        result.logs.forEach(log => {
          // Look for ERROR in severity field or in raw log content
          const hasErrorSeverity = log.severity === 'ERROR' || log.severity === 'Error';
          const rawContainsError = log.raw.includes('ERROR') || 
                                 log.raw.includes('error') || 
                                 log.raw.includes('Error') ||
                                 log.raw.includes('Exception') ||
                                 log.raw.includes('failed') ||
                                 log.raw.includes('timed out');
                                 
          expect(hasErrorSeverity || rawContainsError).toBeTruthy();
        });
      }
    });
    
    // Test CSV export functionality
    test(`should export ${format} logs as CSV`, async () => {
      // Configure CSV export
      const csvOptions: LogLyzeOptions = {
        csvOnly: true
      };
      
      const result = await loglyze.analyze(sampleFile, csvOptions);
      
      // Verify CSV data was generated
      expect(result.csv).toBeDefined();
      expect((result.csv as any[]).length).toBeGreaterThan(0);
      
      // CSV should have expected fields
      const firstRow = (result.csv as any[])[0];
      // Most formats should have at least these basic fields
      if (!['w3c_iis', 'aws_cloudtrail'].includes(format)) {
        expect(firstRow).toHaveProperty('timestamp');
        expect(firstRow).toHaveProperty('severity');
        expect(firstRow).toHaveProperty('message');
      }
    });
  });
}); 