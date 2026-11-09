export const EXTRACTION_SCHEMA = {
  type: "object",
  additionalProperties: false,
  properties: {
    sets_completed: nullableInteger("Sets the patient explicitly says they completed."),
    reps_per_set: nullableInteger("Repetitions per set the patient explicitly says they completed."),
    duration_seconds: nullableInteger("Total exercise duration in seconds."),
    band_resistance: nullableString("Band color or resistance explicitly used."),
    weight_value: nullableNumber("Numeric weight explicitly used."),
    weight_unit: {
      anyOf: [
        { type: "string", enum: ["lb", "kg"] },
        { type: "null" },
      ],
      description: "Unit for weight_value, or null when no unambiguous weight is present.",
    },
    pain_after: nullableInteger("Pain during or after the exercise on a 0 to 10 scale."),
    each_side: {
      anyOf: [{ type: "boolean" }, { type: "null" }],
      description: "True only when the patient explicitly says the work was performed on each or both sides.",
    },
    notes: {
      type: "array",
      items: { type: "string" },
      description: "Concise details that do not belong in another structured field.",
    },
  },
  required: [
    "sets_completed",
    "reps_per_set",
    "duration_seconds",
    "band_resistance",
    "weight_value",
    "weight_unit",
    "pain_after",
    "each_side",
    "notes",
  ],
} as const;

export const EXTRACTION_INSTRUCTIONS = `
You extract a patient's completed home physical-therapy exercise log from a speech transcript.

Rules:
- Extract only what the patient says they actually did. Prescription targets are context, never completed values.
- When a value has more than one plausible interpretation, return null instead of guessing.
- Convert spoken number words and durations to numbers. Convert minutes to seconds.
- pain_after is the patient's pain during or after exercise on a 0–10 scale.
- Phrases such as "after the exercise" or "during the exercise" modify a pain statement; they are not notes.
- Speech recognition may produce phrases such as "pain was out of five out of ten". Interpret that as pain_after 5 when the intended score is otherwise clear.
- Notes contain only meaningful details that cannot be represented in the structured fields, such as tightness, form changes, or why the patient stopped.
- Do not repeat sets, reps, duration, resistance, weight, pain, side qualifiers, or their contextual wording in notes.
- Remove filler words and write each note as one concise sentence fragment without bullets or punctuation prefixes.
- Return an empty notes array when no additional detail remains.
- Do not diagnose, recommend treatment, or infer facts that were not spoken.
`;

export interface ParseExerciseLogRequest {
  version: 1;
  transcript: string;
  exercise: {
    name: string;
    tracking_mode: "reps" | "duration" | null;
    prescription: {
      sets: number | null;
      reps: number | null;
      duration_seconds: number | null;
      band_resistance: string | null;
      weight_value: number | null;
      weight_unit: "lb" | "kg" | null;
      notes: string | null;
    };
  };
}

export interface StructuredExerciseLog {
  sets_completed: number | null;
  reps_per_set: number | null;
  duration_seconds: number | null;
  band_resistance: string | null;
  weight_value: number | null;
  weight_unit: "lb" | "kg" | null;
  pain_after: number | null;
  each_side: boolean | null;
  notes: string[];
}

export function parseRequest(value: unknown): ParseExerciseLogRequest {
  const root = requireObject(value, "Request body");
  if (root.version !== 1) throw new Error("Unsupported request version.");

  const transcript = requireTrimmedString(root.transcript, "Transcript", 20_000);
  const exerciseValue = requireObject(root.exercise, "Exercise");
  const prescriptionValue = requireObject(exerciseValue.prescription, "Prescription");

  return {
    version: 1,
    transcript,
    exercise: {
      name: requireTrimmedString(exerciseValue.name, "Exercise name", 300),
      tracking_mode: nullableEnum(exerciseValue.tracking_mode, ["reps", "duration"], "tracking_mode"),
      prescription: {
        sets: nullableIntegerValue(prescriptionValue.sets, "sets", 1, 100),
        reps: nullableIntegerValue(prescriptionValue.reps, "reps", 1, 10_000),
        duration_seconds: nullableIntegerValue(
          prescriptionValue.duration_seconds,
          "duration_seconds",
          1,
          86_400,
        ),
        band_resistance: nullableTrimmedString(prescriptionValue.band_resistance, "band_resistance", 100),
        weight_value: nullableNumberValue(prescriptionValue.weight_value, "weight_value", 0, 10_000),
        weight_unit: nullableEnum(prescriptionValue.weight_unit, ["lb", "kg"], "weight_unit"),
        notes: nullableTrimmedString(prescriptionValue.notes, "notes", 1_000),
      },
    },
  };
}

export function validateExtraction(value: unknown): StructuredExerciseLog {
  const extraction = requireObject(value, "Model output");
  if (!Array.isArray(extraction.notes)) throw new Error("Model output notes must be an array.");

  const seen = new Set<string>();
  const notes = extraction.notes
    .map((note, index) => requireTrimmedString(note, `notes[${index}]`, 500).replace(/^[\s•*\-–—]+/, ""))
    .filter((note) => note.length > 0)
    .filter((note) => {
      const key = note.toLocaleLowerCase();
      if (seen.has(key)) return false;
      seen.add(key);
      return true;
    })
    .slice(0, 20);

  const weightValue = nullableNumberValue(extraction.weight_value, "weight_value", 0, 10_000);
  let weightUnit = nullableEnum(extraction.weight_unit, ["lb", "kg"], "weight_unit");
  if (weightValue === null) weightUnit = null;

  return {
    sets_completed: nullableIntegerValue(extraction.sets_completed, "sets_completed", 1, 100),
    reps_per_set: nullableIntegerValue(extraction.reps_per_set, "reps_per_set", 1, 10_000),
    duration_seconds: nullableIntegerValue(extraction.duration_seconds, "duration_seconds", 1, 86_400),
    band_resistance: nullableTrimmedString(extraction.band_resistance, "band_resistance", 100),
    weight_value: weightValue,
    weight_unit: weightUnit,
    pain_after: nullableIntegerValue(extraction.pain_after, "pain_after", 0, 10),
    each_side: nullableBoolean(extraction.each_side, "each_side"),
    notes,
  };
}

function nullableInteger(description: string) {
  return { anyOf: [{ type: "integer" }, { type: "null" }], description } as const;
}

function nullableNumber(description: string) {
  return { anyOf: [{ type: "number" }, { type: "null" }], description } as const;
}

function nullableString(description: string) {
  return { anyOf: [{ type: "string" }, { type: "null" }], description } as const;
}

function requireObject(value: unknown, field: string): Record<string, unknown> {
  if (typeof value !== "object" || value === null || Array.isArray(value)) {
    throw new Error(`${field} must be an object.`);
  }
  return value as Record<string, unknown>;
}

function requireTrimmedString(value: unknown, field: string, maximumLength: number): string {
  if (typeof value !== "string") throw new Error(`${field} must be a string.`);
  const result = value.trim();
  if (!result || result.length > maximumLength) throw new Error(`${field} is invalid.`);
  return result;
}

function nullableTrimmedString(value: unknown, field: string, maximumLength: number): string | null {
  if (value === null) return null;
  return requireTrimmedString(value, field, maximumLength);
}

function nullableIntegerValue(
  value: unknown,
  field: string,
  minimum: number,
  maximum: number,
): number | null {
  if (value === null) return null;
  if (typeof value !== "number" || !Number.isInteger(value) || value < minimum || value > maximum) {
    throw new Error(`${field} is invalid.`);
  }
  return value;
}

function nullableNumberValue(
  value: unknown,
  field: string,
  minimum: number,
  maximum: number,
): number | null {
  if (value === null) return null;
  if (typeof value !== "number" || !Number.isFinite(value) || value < minimum || value > maximum) {
    throw new Error(`${field} is invalid.`);
  }
  return value;
}

function nullableBoolean(value: unknown, field: string): boolean | null {
  if (value === null) return null;
  if (typeof value !== "boolean") throw new Error(`${field} is invalid.`);
  return value;
}

function nullableEnum<const T extends string>(
  value: unknown,
  allowed: readonly T[],
  field: string,
): T | null {
  if (value === null) return null;
  if (typeof value !== "string" || !allowed.includes(value as T)) throw new Error(`${field} is invalid.`);
  return value as T;
}
