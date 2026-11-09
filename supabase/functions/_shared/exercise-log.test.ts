import { assertEquals, assertThrows } from "jsr:@std/assert";
import { parseRequest, validateExtraction } from "./exercise-log.ts";

Deno.test("ambiguous structured values remain null", () => {
  const extraction = validateExtraction({
    sets_completed: null,
    reps_per_set: null,
    duration_seconds: null,
    band_resistance: null,
    weight_value: null,
    weight_unit: null,
    pain_after: null,
    each_side: null,
    notes: [],
  });
  assertEquals(extraction.pain_after, null);
  assertEquals(extraction.notes, []);
});

Deno.test("validated output cleans and deduplicates note bullets", () => {
  const extraction = validateExtraction({
    sets_completed: 3,
    reps_per_set: 10,
    duration_seconds: null,
    band_resistance: null,
    weight_value: 8,
    weight_unit: "lb",
    pain_after: 5,
    each_side: true,
    notes: ["• Shoulder felt tight", "shoulder felt tight"],
  });
  assertEquals(extraction.notes, ["Shoulder felt tight"]);
});

Deno.test("request context accepts nullable prescription fields", () => {
  const request = parseRequest({
    version: 1,
    transcript: "My pain was at a five out of ten.",
    exercise: {
      name: "Thoracic twist",
      tracking_mode: "reps",
      prescription: {
        sets: 3,
        reps: 10,
        duration_seconds: null,
        band_resistance: null,
        weight_value: null,
        weight_unit: null,
        notes: "Complete on each side.",
      },
    },
  });
  assertEquals(request.exercise.name, "Thoracic twist");
  assertEquals(request.exercise.prescription.duration_seconds, null);
});

Deno.test("pain outside the UI range is rejected", () => {
  assertThrows(() => validateExtraction({
    sets_completed: null,
    reps_per_set: null,
    duration_seconds: null,
    band_resistance: null,
    weight_value: null,
    weight_unit: null,
    pain_after: 12,
    each_side: null,
    notes: [],
  }));
});
