import { buildUserPrompt, SYSTEM_PROMPT } from "./prompt.ts";
import type { ExistingLibraryEntry, SourceLineInput } from "./prompt.ts";
import { mealImportSchema } from "./schema.ts";
import { ImportValidationError, validateProposal } from "./validate.ts";

const OPENAI_RESPONSES_URL = "https://api.openai.com/v1/responses";
const MAX_SOURCE_TEXT_LENGTH = 40_000;
const MAX_SOURCE_LINES = 1_000;
const MAX_LIBRARY_ENTRIES = 2_000;
const REQUEST_TIMEOUT_MS = 30_000;

type ImportRequest = {
  source_text: string;
  source_lines: SourceLineInput[];
  existing_library: ExistingLibraryEntry[];
};

const corsHeaders = {
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Access-Control-Allow-Origin": Deno.env.get("IMPORT_ALLOWED_ORIGIN") ?? "*",
  "Content-Type": "application/json",
};

function jsonResponse(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: corsHeaders,
  });
}

function errorResponse(code: string, message: string, status: number): Response {
  return jsonResponse({ error: { code, message } }, status);
}

function validateRequest(value: unknown): ImportRequest {
  if (value === null || typeof value !== "object" || Array.isArray(value)) {
    throw new ImportValidationError("Request body must be an object");
  }
  const body = value as Record<string, unknown>;
  if (typeof body.source_text !== "string" || body.source_text.trim().length === 0) {
    throw new ImportValidationError("source_text must be a non-empty string");
  }
  if (body.source_text.length > MAX_SOURCE_TEXT_LENGTH) {
    throw new ImportValidationError("source_text is too large");
  }
  if (!Array.isArray(body.source_lines) || body.source_lines.length > MAX_SOURCE_LINES) {
    throw new ImportValidationError("source_lines must be an array within the size limit");
  }
  if (!Array.isArray(body.existing_library) || body.existing_library.length > MAX_LIBRARY_ENTRIES) {
    throw new ImportValidationError("existing_library must be an array within the size limit");
  }

  const sourceLines: SourceLineInput[] = [];
  const sourceIds = new Set<string>();
  for (const [index, item] of body.source_lines.entries()) {
    if (item === null || typeof item !== "object" || Array.isArray(item)) {
      throw new ImportValidationError(`source_lines[${index}] must be an object`);
    }
    const line = item as Record<string, unknown>;
    if (typeof line.id !== "string" || line.id.trim().length === 0 || typeof line.text !== "string") {
      throw new ImportValidationError(`source_lines[${index}] must contain id and text`);
    }
    if (sourceIds.has(line.id)) throw new ImportValidationError("source line IDs must be unique");
    sourceIds.add(line.id);
    sourceLines.push({ id: line.id, text: line.text });
  }
  const existingLibrary: ExistingLibraryEntry[] = [];
  for (const [index, item] of body.existing_library.entries()) {
    if (item === null || typeof item !== "object" || Array.isArray(item)) {
      throw new ImportValidationError(`existing_library[${index}] must be an object`);
    }
    const entry = item as Record<string, unknown>;
    if (
      typeof entry.id !== "string" ||
      typeof entry.family_id !== "string" ||
      typeof entry.family_name !== "string" ||
      typeof entry.variant_name !== "string" ||
      !Array.isArray(entry.aliases) ||
      !entry.aliases.every((alias) => typeof alias === "string")
    ) {
      throw new ImportValidationError(`existing_library[${index}] has an invalid shape`);
    }
    existingLibrary.push({
      id: entry.id,
      family_id: entry.family_id,
      family_name: entry.family_name,
      variant_name: entry.variant_name,
      aliases: entry.aliases as string[],
    });
  }
  return { source_text: body.source_text, source_lines: sourceLines, existing_library: existingLibrary };
}

function extractOutputText(response: Record<string, unknown>): string | null {
  if (typeof response.output_text === "string") return response.output_text;
  const output = response.output;
  if (!Array.isArray(output)) return null;
  const texts: string[] = [];
  for (const item of output) {
    if (item === null || typeof item !== "object") continue;
    const content = (item as Record<string, unknown>).content;
    if (!Array.isArray(content)) continue;
    for (const part of content) {
      if (part === null || typeof part !== "object") continue;
      const block = part as Record<string, unknown>;
      if (block.type === "refusal") {
        throw new Error("MODEL_REFUSAL");
      }
      if (block.type === "output_text" && typeof block.text === "string") {
        texts.push(block.text);
      }
    }
  }
  return texts.length === 0 ? null : texts.join("");
}

async function callOpenAI(request: ImportRequest): Promise<unknown> {
  const apiKey = Deno.env.get("OPENAI_API_KEY");
  if (!apiKey) throw new Error("MISSING_OPENAI_API_KEY");
  const model = Deno.env.get("OPENAI_MODEL") ?? "gpt-4o-mini";
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), REQUEST_TIMEOUT_MS);
  try {
    const response = await fetch(OPENAI_RESPONSES_URL, {
      method: "POST",
      signal: controller.signal,
      headers: {
        Authorization: `Bearer ${apiKey}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        model,
        store: false,
        max_output_tokens: 4_000,
        input: [
          { role: "system", content: SYSTEM_PROMPT },
          {
            role: "user",
            content: buildUserPrompt(request),
          },
        ],
        text: {
          format: {
            type: "json_schema",
            name: "preppick_meal_import",
            strict: true,
            schema: mealImportSchema,
          },
        },
      }),
    });
    const responseBody = await response.json() as Record<string, unknown>;
    if (!response.ok) {
      console.error("OpenAI Responses API request failed", response.status);
      throw new Error("OPENAI_REQUEST_FAILED");
    }
    if (responseBody.status === "incomplete") throw new Error("MODEL_INCOMPLETE");
    const outputText = extractOutputText(responseBody);
    if (outputText === null) throw new Error("MODEL_EMPTY_OUTPUT");
    try {
      return JSON.parse(outputText);
    } catch {
      throw new Error("MODEL_MALFORMED_JSON");
    }
  } finally {
    clearTimeout(timeout);
  }
}

Deno.serve(async (request) => {
  if (request.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (request.method !== "POST") return errorResponse("method_not_allowed", "Use POST.", 405);

  try {
    const body = validateRequest(await request.json());
    const rawProposal = await callOpenAI(body);
    const proposal = validateProposal(
      rawProposal,
      body.source_lines.map((line) => line.id),
    );
    return jsonResponse(proposal);
  } catch (error) {
    if (error instanceof ImportValidationError) {
      return errorResponse("invalid_request", error.message, 400);
    }
    const message = error instanceof Error ? error.message : "UNKNOWN_ERROR";
    if (message === "MISSING_OPENAI_API_KEY") {
      return errorResponse("service_not_configured", "Import service is not configured.", 503);
    }
    if (message === "MODEL_REFUSAL") {
      return errorResponse("model_refusal", "The import could not be interpreted.", 422);
    }
    if (message === "MODEL_INCOMPLETE" || message === "MODEL_EMPTY_OUTPUT") {
      return errorResponse("incomplete_response", "The import response was incomplete. Try again.", 502);
    }
    if (message === "MODEL_MALFORMED_JSON") {
      return errorResponse("malformed_response", "The import response was invalid. Try again.", 502);
    }
    if (message === "OPENAI_REQUEST_FAILED") {
      return errorResponse("upstream_error", "The import service could not be reached.", 502);
    }
    if (error instanceof DOMException && error.name === "AbortError") {
      return errorResponse("timeout", "The import service timed out. Try again.", 504);
    }
    console.error("Meal import function failed", error);
    return errorResponse("internal_error", "The import could not be completed.", 500);
  }
});
