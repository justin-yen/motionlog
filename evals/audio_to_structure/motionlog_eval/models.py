from __future__ import annotations

from typing import Literal

from pydantic import BaseModel, ConfigDict, Field, model_validator


Category = Literal[
    "straightforward",
    "conversational",
    "correction_ambiguity",
    "pain_symptoms",
    "timed",
    "irrelevant_adversarial",
]
Variant = Literal["direct", "natural", "difficult"]


class StructuredLog(BaseModel):
    model_config = ConfigDict(extra="forbid")

    sets_completed: int | None = Field(default=None, ge=1, le=100)
    reps_per_set: int | None = Field(default=None, ge=1, le=10_000)
    duration_seconds: int | None = Field(default=None, ge=1, le=86_400)
    band_resistance: str | None = Field(default=None, max_length=100)
    weight_value: float | None = Field(default=None, ge=0, le=10_000)
    weight_unit: Literal["lb", "kg"] | None = None
    pain_after: int | None = Field(default=None, ge=0, le=10)
    each_side: bool | None = None
    notes: list[str] = Field(default_factory=list, max_length=20)

    @model_validator(mode="after")
    def weight_unit_requires_value(self) -> "StructuredLog":
        if self.weight_value is None and self.weight_unit is not None:
            raise ValueError("weight_unit requires weight_value")
        return self


class ExerciseContext(BaseModel):
    name: str
    tracking_mode: Literal["reps", "duration"] | None
    prescription: dict[str, int | float | str | None] = Field(default_factory=dict)


class NoteFact(BaseModel):
    id: str
    patterns: list[str]


class Scenario(BaseModel):
    id: str
    category: Category
    exercise: ExerciseContext
    expected: StructuredLog
    utterances: dict[Variant, str]
    expect_notes: bool = False
    required_note_facts: list[NoteFact] = Field(default_factory=list)
    forbidden_note_facts: list[NoteFact] = Field(default_factory=list)
    ambiguous_fields: list[str] = Field(default_factory=list)

    @model_validator(mode="after")
    def has_every_variant(self) -> "Scenario":
        required = {"direct", "natural", "difficult"}
        if set(self.utterances) != required:
            raise ValueError(f"utterances must contain exactly {sorted(required)}")
        if self.expect_notes != bool(self.required_note_facts or self.expected.notes):
            raise ValueError("expect_notes must agree with expected note content")
        return self


class Fixture(BaseModel):
    id: str
    scenario_id: str
    category: Category
    variant: Variant
    voice: str
    utterance: str
    exercise: ExerciseContext
    expected: StructuredLog
    expect_notes: bool
    required_note_facts: list[NoteFact]
    forbidden_note_facts: list[NoteFact]
    ambiguous_fields: list[str]
    attempt: int = 1


class FieldCounts(BaseModel):
    true_positive: int = 0
    false_positive: int = 0
    false_negative: int = 0


class RunScore(BaseModel):
    slot_counts: FieldCounts = Field(default_factory=FieldCounts)
    numeric_correct: int = 0
    numeric_total: int = 0
    pain_correct: int = 0
    pain_total: int = 0
    expected_null_total: int = 0
    false_fills: int = 0
    ambiguity_total: int = 0
    ambiguity_blank: int = 0
    note_presence_correct: int = 0
    note_presence_total: int = 1
    required_note_facts_correct: int = 0
    required_note_facts_total: int = 0
    forbidden_note_facts_found: int = 0
    forbidden_note_facts_total: int = 0
    structured_field_leakage: bool = False
    exact_form_match: bool = False
    critical_violations: list[str] = Field(default_factory=list)
    field_differences: list[str] = Field(default_factory=list)


class RunResult(BaseModel):
    fixture: Fixture
    status: Literal["passed", "failed", "error"]
    transcript: str | None = None
    actual: StructuredLog | None = None
    score: RunScore | None = None
    error_stage: Literal["fixture", "audio", "transcription", "authentication", "parsing", "scoring"] | None = None
    error: str | None = None
    transcription_completed: bool = False
    parser_response_received: bool = False
    schema_valid: bool = False
    audio_checksum: str | None = None
    transcription_ms: int | None = None
    parsing_ms: int | None = None
    total_ms: int | None = None
