from __future__ import annotations

from .catalog import SCENARIOS
from .models import Fixture, Scenario, Variant


VOICES = ("af_heart", "am_michael")

SMOKE_SCENARIOS = (
    "straight-01",
    "straight-02",
    "straight-03",
    "straight-08",
    "conversation-06",
    "conversation-07",
    "correction-01",
    "ambiguity-01",
    "pain-05",
    "pain-06",
    "timed-01",
    "irrelevant-03",
)

STABILITY_SCENARIOS = (
    "straight-03",
    "straight-08",
    "straight-15",
    "straight-19",
    "conversation-01",
    "conversation-04",
    "conversation-05",
    "conversation-06",
    "conversation-07",
    "conversation-08",
    "correction-01",
    "correction-02",
    "correction-03",
    "correction-04",
    "correction-05",
    "ambiguity-01",
    "ambiguity-02",
    "ambiguity-03",
    "ambiguity-04",
    "correction-10",
    "pain-04",
    "pain-05",
    "pain-06",
    "pain-07",
    "pain-08",
    "pain-10",
    "timed-04",
    "timed-05",
    "irrelevant-02",
    "irrelevant-03",
)


def _fixture(scenario: Scenario, variant: Variant, voice: str, attempt: int = 1) -> Fixture:
    suffix = f"-{variant}-{voice}"
    return Fixture(
        id=f"{scenario.id}{suffix}",
        scenario_id=scenario.id,
        category=scenario.category,
        variant=variant,
        voice=voice,
        utterance=scenario.utterances[variant],
        exercise=scenario.exercise,
        expected=scenario.expected,
        expect_notes=scenario.expect_notes,
        required_note_facts=scenario.required_note_facts,
        forbidden_note_facts=scenario.forbidden_note_facts,
        ambiguous_fields=scenario.ambiguous_fields,
        attempt=attempt,
    )


def fixtures_for_tier(tier: str) -> list[Fixture]:
    by_id = {item.id: item for item in SCENARIOS}
    if tier == "smoke":
        return [
            _fixture(by_id[scenario_id], variant, voice)
            for scenario_id in SMOKE_SCENARIOS
            for variant in ("direct", "natural")
            for voice in VOICES
        ]
    if tier == "full":
        return [
            _fixture(item, variant, voice)
            for item in SCENARIOS
            for variant in ("direct", "natural", "difficult")
            for voice in VOICES
        ]
    if tier == "stability":
        return [
            _fixture(by_id[scenario_id], "difficult", VOICES[0], attempt)
            for scenario_id in STABILITY_SCENARIOS
            for attempt in (1, 2, 3)
        ]
    raise ValueError(f"Unknown tier: {tier}")
