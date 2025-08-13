// src/orchestration/src/workflows/main.ts

import { inngest } from "../index.js";
import { LambdaClient, InvokeCommand } from "@aws-sdk/client-lambda";
import { GetSecretValueCommand, SecretsManagerClient } from "@aws-sdk/client-secrets-manager";
import axios from "axios";
import { NonRetriableError } from "inngest";

/**
 * Purpose:
 *   Orchestration functions for the Event-Driven Design Automation pipeline.
 */

const REGION = process.env.AWS_REGION ?? "us-east-1";
const ENV = process.env.APP_ENV ?? "dev";
const ADOBE_CONCURRENCY_LIMIT = parseInt(process.env.ADOBE_CONCURRENCY_LIMIT || "200", 10);

const lambdaClient = new LambdaClient({ region: REGION });
const secretsManagerClient = new SecretsManagerClient({ region: REGION });
const textEncoder = new TextEncoder();
const textDecoder = new TextDecoder();

/**
 * Invoke a Lambda by convention name: event-forge-<fn>-<ENV>.
 */
async function invokeLambda(
    fnName: string,
    payload: unknown
    ): Promise<{ statusCode: number; body: any }> {
    const FunctionName = `event-forge-${fnName}-${ENV}`;
    const command = new InvokeCommand({
        FunctionName,
        Payload: textEncoder.encode(JSON.stringify(payload)),
    });
    const response = await lambdaClient.send(command);
    const raw = response.Payload ? textDecoder.decode(response.Payload) : "";
    const parsed = raw ? JSON.parse(raw) : {};
    const statusCode: number =
        typeof parsed?.statusCode === "number" ? parsed.statusCode : response.StatusCode ?? 200;
    const body = typeof parsed?.body === "string" ? JSON.parse(parsed.body) : parsed?.body ?? parsed;
    return { statusCode, body };
}

/**
 * Fan-out: read sheet, emit generate requests, then trigger reporting.
 */
export const fanOutAndGenerate = inngest.createFunction(
    {
        id: "fan-out-and-generate",
        name: "Fan Out and Generate Posters",
        concurrency: { limit: 5 },
        idempotency: "event.data.revisionId",
    },
    { event: "google/drive.sheet.updated" },
    async (ctx) => {
        const { event, step } = ctx as any;

        const run_id = (event.data as any)?.revisionId || (event as any).id;

        const readResult = await step.run("1-read-google-sheet", async () => {
        const { statusCode, body } = await invokeLambda("read-sheet", event);
        if (statusCode !== 200) {
            throw new Error(`Read sheet Lambda failed: status=${statusCode} body=${JSON.stringify(body)}`);
        }
        return body as {
            valid_rows: Record<string, any>[];
            invalid_rows_count: number;
            spreadsheet_id: string;
        };
        });

        const { valid_rows, invalid_rows_count, spreadsheet_id } = readResult;

        if (!Array.isArray(valid_rows) || valid_rows.length === 0) {
        return { message: "No valid rows found." };
        }

        await step.sendEvent(
        "2-fan-out-requests",
        valid_rows.map((row) => ({
            name: "poster/generate.request" as const,
            data: { row_data: row, spreadsheet_id, run_id },
        }))
        );

        await step.sendEvent("trigger-reporting-step", {
        name: "poster/reporting.requested",
        data: { spreadsheet_id, total_jobs: valid_rows.length, invalid_rows_count, run_id },
        });

        return { message: `Fanned out ${valid_rows.length} jobs.` };
    }
);

/**
 * Handle one poster generation: submit to Adobe, poll, and emit result.
 */
export const generatePoster = inngest.createFunction(
    {
        id: "generate-single-poster",
        name: "Generate Single Poster",
        concurrency: { limit: ADOBE_CONCURRENCY_LIMIT },
    },
    { event: "poster/generate.request" },
    async (ctx) => {
        const { event, step } = ctx as any;
        const { row_data, run_id } = event.data as {
        row_data: Record<string, any>;
        spreadsheet_id: string;
        run_id: string;
        };

        const submissionResult = await step.run("3-submit-to-adobe", async () => {
        const { statusCode, body } = await invokeLambda("generate-poster", event);
        if (statusCode !== 200) {
            throw new NonRetriableError(
            `Generate poster Lambda failed: status=${statusCode} body=${JSON.stringify(body)}`
            );
        }
        return body as { job_status_url: string; output_key?: string };
        });

        const adobeCreds = await step.run("get-adobe-creds-for-polling", async () => {
        const secretName = `event-forge/adobe-api-key-${ENV}`;
        const secret = await secretsManagerClient.send(new GetSecretValueCommand({ SecretId: secretName }));
        return JSON.parse(secret.SecretString || "{}") as { client_id: string; client_secret: string };
        });

        const accessToken = await step.run("get-adobe-token", async () => {
        const form = new URLSearchParams({
            grant_type: "client_credentials",
            client_id: adobeCreds.client_id,
            client_secret: adobeCreds.client_secret,
            scope: "openid,AdobeID,indesign_services",
        });
        const res = await axios.post("https://ims-na1.adobelogin.com/ims/token/v3", form);
        return res.data.access_token as string;
        });

        const pollingHeaders = {
        Authorization: `Bearer ${accessToken}`,
        "x-api-key": adobeCreds.client_id,
        } as const;

        let jobDetails: any = {};
        let adobeJobStatus = "running";

        while (adobeJobStatus === "running" || adobeJobStatus === "unstarted") {
        await step.sleep("4-wait-for-adobe", "10s");
        jobDetails = await step.run("5-poll-adobe-status", async () => {
            const res = await axios.get(submissionResult.job_status_url, { headers: pollingHeaders });
            return res.data;
        });
        adobeJobStatus = jobDetails.status;
        }

        const resultEventName = "poster/generate.result" as const;
        const sku = (row_data as any)?.sku ?? "";

        if (adobeJobStatus === "succeeded") {
        await step.sendEvent("6-send-success-result", {
            name: resultEventName,
            data: { run_id, sku, status: "SUCCESS", output_key: submissionResult.output_key },
        });
        } else {
        await step.sendEvent("6-send-failure-result", {
            name: resultEventName,
            data: { run_id, sku, status: "FAILURE", error: jobDetails?.errors?.[0]?.title ?? "Unknown Adobe failure" },
        });
        throw new Error(`Adobe job failed for SKU ${sku}`);
        }
    }
);

/**
 * Aggregate all results for the run, then send a final report via Lambda.
 */
export const aggregateAndReport = inngest.createFunction(
    {
        id: "aggregate-and-report",
        name: "Aggregate and Send Report",
    },
    { event: "poster/reporting.requested" },
    async (ctx) => {
        const { event, step } = ctx as any;
        const { run_id, total_jobs, invalid_rows_count, spreadsheet_id } = event.data as {
        run_id: string;
        total_jobs: number;
        invalid_rows_count: number;
        spreadsheet_id: string;
        };

        const results: any[] = [];
        const seen = new Set<string>();

        for (let i = 0; i < total_jobs; i++) {
        const evt: any = await step.waitForEvent("wait-for-one-result", {
            event: "poster/generate.result",
            timeout: "1h",
            if: `event.data.run_id == '${run_id}'`,
        });
        if (!evt) break;

        const key = `${evt?.data?.run_id ?? ""}:${evt?.data?.sku ?? ""}`;
        if (!seen.has(key)) {
            seen.add(key);
            results.push(evt);
        }
        }

        const successful_jobs = results.map((e) => e?.data).filter((d) => d?.status === "SUCCESS");
        const failed_jobs = results.map((e) => e?.data).filter((d) => d?.status === "FAILURE");

        await step.run("7-send-final-report", async () => {
        const reportPayload = {
            data: {
            results: {
                spreadsheet_id,
                successful_jobs,
                failed_jobs,
                invalid_rows_count,
            },
            },
        };
        await invokeLambda("send-report", reportPayload);
        });

        return { message: "Report sent." };
    }
);
