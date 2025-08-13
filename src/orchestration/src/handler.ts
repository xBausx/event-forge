// src/orchestration/src/handler.ts

import { serve } from "inngest/lambda";
import { inngest, functions } from "./index.js";

/**
 * Lambda entrypoint for Inngest.
 * - Inngest verifies requests using INNGEST_SIGNING_KEY (set via env).
 * - We expose a single HTTP endpoint via Lambda Function URL.
 * Docs: serve handler & signing key env. 
 */
export const handler = serve({
    client: inngest,
    functions,
    // signingKey: process.env.INNGEST_SIGNING_KEY, // not required if env var is set
    // Optional hardening if needed:
    // servePath: "/",             // Function URL root
    // streaming: "allow",
});
