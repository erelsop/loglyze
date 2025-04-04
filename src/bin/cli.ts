#!/usr/bin/env node
/**
 * LogLyze CLI - Command line interface for the LogLyze tool
 */
import { Command } from 'commander';
import { LogLyze } from '../lib';
import { LogLyzeOptions } from '../lib/types';
import { readFileSync } from 'fs';

// Get package info
const packagePath = require.resolve('../../package.json');
const packageInfo = JSON.parse(readFileSync(packagePath, 'utf-8'));

// Set up the command line interface
const program = new Command();

program
  .name('loglyze')
  .description('A powerful log analysis tool')
  .version(packageInfo.version)
  .argument('[logFile]', 'Log file to analyze')
  .option('-v, --verbose', 'Enable verbose output')
  .option('--show-logs', 'Display log content')
  .option('-i, --interactive', 'Use interactive mode')
  .option('-c, --csv', 'Export results as CSV after summary')
  .option('--csv-only', 'Export results as CSV only (no summary)')
  .option('-e, --errors-only', 'Show only error entries')
  .option('-l, --limit <number>', 'Limit output to NUMBER entries')
  .option('-s, --sample', 'Sample log entries instead of showing all')
  .option('--top-errors <number>', 'Show top NUMBER frequent errors in summary', '5')
  .option('-f, --from <time>', 'Filter entries from this time (format: YYYY-MM-DD HH:MM:SS)')
  .option('-t, --to <time>', 'Filter entries to this time (format: YYYY-MM-DD HH:MM:SS)')
  .option('-o, --output <format>', 'Output format (json, pretty)', 'pretty')
  .action(async (logFile: string | undefined, options: Record<string, any>) => {
    try {
      // Initialize LogLyze with command line options
      const loglyzeOptions: LogLyzeOptions = {
        verbose: options.verbose,
        showLogs: options.showLogs,
        interactive: options.interactive,
        csv: options.csv,
        csvOnly: options.csvOnly,
        errorsOnly: options.errorsOnly,
        limit: options.limit ? parseInt(options.limit, 10) : null,
        sample: options.sample,
        topErrors: options.topErrors ? parseInt(options.topErrors, 10) : 5,
        from: options.from,
        to: options.to
      };
      
      const loglyze = new LogLyze(loglyzeOptions);
      
      // Check if we have log file or data from stdin
      const isTTY = process.stdin.isTTY;
      
      if (!logFile && isTTY) {
        console.error('Error: No log file specified and no data piped to stdin.');
        program.help();
        return;
      }
      
      let result;
      
      // Read from stdin if no log file is provided
      if (!logFile && !isTTY) {
        // Read from stdin
        const chunks: Buffer[] = [];
        
        for await (const chunk of process.stdin) {
          chunks.push(Buffer.from(chunk));
        }
        
        const data = Buffer.concat(chunks).toString('utf-8');
        
        // Analyze string data
        result = await loglyze.analyzeString(data);
      } else if (logFile) {
        // Analyze file
        result = await loglyze.analyze(logFile);
      } else {
        console.error('Error: No log file specified and no data piped to stdin.');
        process.exit(1);
        return;
      }
      
      // Output results based on format
      if (options.output === 'json') {
        console.log(JSON.stringify(result, null, 2));
      } else {
        // If CSV only mode was used, just output the raw result
        if (options.csvOnly) {
          process.stdout.write(result.rawOutput);
        } else {
          // Default to pretty output
          process.stdout.write(result.rawOutput);
        }
      }
    } catch (error) {
      console.error(`Error: ${error instanceof Error ? error.message : String(error)}`);
      process.exit(1);
    }
  });

// Parse command line arguments
program.parse(); 