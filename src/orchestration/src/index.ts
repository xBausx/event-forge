// src/orchestration/src/index.ts

import { EventSchemas, Inngest } from "inngest";
import {
  fanOutAndGenerate,
  generatePoster,
  aggregateAndReport,
} from "./workflows/main.js";

// =================================================================
// Event Payloads - The "Data Contracts" of our System
// =================================================================

type GoogleSheetUpdated = {
  data: {
    resourceId: string;
    revisionId: string;
    file_id: string;
  };
};

type PosterGenerationRequested = {
  data: {
    row_data: Record<string, any>;
    spreadsheet_id: string;
    run_id: string; // correlation id for this run
  };
};

type PosterGenerationResult = {
  data: {
    status: "SUCCESS" | "FAILURE";
    sku: string;
    error?: string;
    output_key?: string;
    run_id: string; // correlate back to the run
  };
};

type ReportingRequested = {
  data: {
    run_id: string;
    total_jobs: number;
    invalid_rows_count: number;
    spreadsheet_id: string;
  };
};

// =================================================================
// Inngest Client Initialization
// =================================================================
const schemas = new EventSchemas().fromRecord<{
  "google/drive.sheet.updated": GoogleSheetUpdated;
  "poster/generate.request": PosterGenerationRequested;
  "poster/generate.result": PosterGenerationResult;
  "poster/reporting.requested": ReportingRequested;
}>();

export const inngest = new Inngest({
  id: "event-forge-orchestrator",
  schemas,
  env: process.env.APP_ENV,
});

// =================================================================
// Export Functions
// =================================================================
export const functions = [
  fanOutAndGenerate,
  generatePoster,
  aggregateAndReport,
];
