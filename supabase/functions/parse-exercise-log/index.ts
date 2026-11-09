import {
  EXTRACTION_INSTRUCTIONS,
  EXTRACTION_SCHEMA,
  parseRequest,
  validateExtraction,
} from "../_shared/exercise-log.ts";

const OPENAI_ENDPOINT = "https://api.openai.com/v1/responses";
const DEFAULT_MODEL = "gpt-4o-mini";

Deno.serve(async (request) => {
  if (request.method === "OPTIONS") return new Response(null, { status: 204 });
  if (request.method !== "POST") return jsonResponse(405, { error: "Method not allowed." });

  const apiKey = Deno.env.get("OPENAI_API_KEY");
  if (!apiKey) return jsonResponse(503, { error: "AI parsing is not configured." });

  try {
    const body = parseRequest(await request.json());
    // Prescription targets are accepted as request context for contract stability, but are
    // deliberately withheld from the model. This prevents a model from treating the assigned
    // routine as evidence that the patient completed those values.
    const modelInput = {
      transcript: body.transcript,
      exercise: {
        name: body.exercise.name,
        tracking_mode: body.exercise.tracking_mode,
      },
    };
    const openAIResponse = await fetch(OPENAI_ENDPOINT, {
      method: "POST",
      headers: {
        Authorization: `Bearer ${apiKey}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        model: Deno.env.get("OPENAI_MODEL") ?? DEFAULT_MODEL,
        store: false,
        instructions: EXTRACTION_INSTRUCTIONS,
        input: JSON.stringify(modelInput),
        text: {
          format: {
            type: "json_schema",
            name: "exercise_log_extraction",
            strict: true,
            schema: EXTRACTION_SCHEMA,
          },
        },
      }),
    });

    const responsePayload = await openAIResponse.json();
    if (!openAIResponse.ok) {
      const providerError = responsePayload?.error;
      console.error(
        "OpenAI request failed",
        openAIResponse.status,
        providerError?.type ?? "unknown",
        providerError?.code ?? "unknown",
        providerError?.param ?? "unknown",
      );
      return jsonResponse(502, { error: "Exercise details could not be parsed right now." });
    }

    const outputText = findOutputText(responsePayload);
    if (!outputText) {
      console.error("OpenAI response did not contain structured output");
      return jsonResponse(502, { error: "Exercise details could not be parsed right now." });
    }

    const extraction = validateExtraction(JSON.parse(outputText));
    return jsonResponse(200, { version: 1, extraction });
  } catch (error) {
    const message = error instanceof Error ? error.message : "Invalid request.";
    const isClientError = message.includes("Request") || message.includes("Transcript") ||
      message.includes("Exercise") || message.includes("Prescription") || message.includes("version");
    if (!isClientError) console.error("Exercise-log extraction failed", message);
    return jsonResponse(isClientError ? 400 : 502, {
      error: isClientError ? message : "Exercise details could not be parsed right now.",
    });
  }
});

function findOutputText(payload: any): string | null {
  if (typeof payload?.output_text === "string") return payload.output_text;
  if (!Array.isArray(payload?.output)) return null;
  for (const item of payload.output) {
    if (!Array.isArray(item?.content)) continue;
    for (const content of item.content) {
      if (content?.type === "output_text" && typeof content.text === "string") return content.text;
    }
  }
  return null;
}

function jsonResponse(status: number, payload: unknown): Response {
  return new Response(JSON.stringify(payload), {
    status,
    headers: {
      "Content-Type": "application/json",
      "Cache-Control": "no-store",
    },
  });
}
