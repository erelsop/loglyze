/**
 * Simple usage example for the LogLyze Node.js module
 */
import { LogLyze } from '../lib';
import { LogLyzeOptions, LogLyzeResult } from '../lib/types';

// Sample log data for demonstration
const sampleLogData = `
2023-09-01 12:00:00 INFO Server started on port 3000
2023-09-01 12:01:15 INFO User login: user123
2023-09-01 12:02:30 WARNING Slow database query took 2.5s
2023-09-01 12:03:45 ERROR Failed to connect to payment gateway: timeout
2023-09-01 12:04:50 INFO User logout: user123
2023-09-01 12:05:10 ERROR Cannot process order #12345: invalid payment
2023-09-01 12:06:20 INFO New user registered: user456
2023-09-01 12:07:30 WARNING Memory usage above 80%
2023-09-01 12:08:40 ERROR Failed to connect to payment gateway: timeout
2023-09-01 12:09:50 INFO System health check completed
`;

async function main() {
  try {
    // Initialize LogLyze with default options
    const options: LogLyzeOptions = {
      // Show log content in addition to summary
      showLogs: true,
      // Limit to 10 entries
      limit: 10
    };
    
    const loglyze = new LogLyze(options);
    
    console.log('Analyzing log data...');
    
    // Analyze the sample log data
    const result: LogLyzeResult = await loglyze.analyzeString(sampleLogData);
    
    // Access structured data from the analysis
    console.log('\nStructured data from analysis:');
    console.log('---------------------------------');
    console.log(`Total lines: ${result.summary.totalLines}`);
    console.log(`Error count: ${result.summary.errorCount}`);
    console.log(`Warning count: ${result.summary.warningCount}`);
    console.log(`Info count: ${result.summary.infoCount}`);
    
    console.log('\nTop errors:');
    result.summary.topErrors.forEach(error => {
      console.log(`- ${error.occurrences} occurrences: ${error.message}`);
    });
    
    // Example of using the API for custom filtering
    console.log('\nNow analyzing with error-only filter...');
    const errorsResult = await loglyze.analyzeString(sampleLogData, {
      errorsOnly: true,
      showLogs: true
    });
    
    console.log('\nError entries:');
    console.log(`Found ${errorsResult.summary.errorCount} errors`);
    
    // Example of changing options and reanalyzing
    console.log('\nAnalyzing with CSV output...');
    loglyze.setOptions({
      csvOnly: true
    });
    
    const csvResult = await loglyze.analyzeString(sampleLogData);
    
    if (csvResult.csv && csvResult.csv.length > 0) {
      console.log('CSV data was generated successfully with fields:');
      console.log(Object.keys(csvResult.csv[0]).join(', '));
      console.log(`Total CSV records: ${csvResult.csv.length}`);
    } else {
      console.log('CSV data generation failed or returned no results');
    }
    
  } catch (error) {
    console.error(`Error: ${error instanceof Error ? error.message : String(error)}`);
  }
}

// Run the example
main(); 