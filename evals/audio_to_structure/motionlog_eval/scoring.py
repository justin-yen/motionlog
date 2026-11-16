from __future__ import annotations

import re

from .models import FieldCounts, Fixture, RunScore, StructuredLog


SLOT_FIELDS = (
    "sets_completed",
    "reps_per_set",
    "duration_seconds",
    "band_resistance",
    "weight_value",
    "weight_unit",
    "pain_after",
    "each_side",
)
NUMERIC_FIELDS = ("sets_completed", "reps_per_set", "duration_seconds", "weight_value", "pain_after")

NUMBER_WORDS = {
    0: "zero",
    1: "one",
    2: "two",
    3: "three",
    4: "four",
    5: "five",
    6: "six",
    7: "seven",
    8: "eight",
    9: "nine",
    10: "ten",
    12: "twelve",
    15: "fifteen",
    20: "twenty",
    25: "twenty five",
    30: "thirty",
    45: "forty five",
    60: "sixty",
    90: "ninety",
    120: "one hundred twenty",
}


def score(fixture: Fixture, actual: StructuredLog) -> RunScore:
    result = RunScore()
    expected = fixture.expected
    counts = FieldCounts()

    for field in SLOT_FIELDS:
        expected_value = _normalized(field, getattr(expected, field))
        actual_value = _normalized(field, getattr(actual, field))
        if expected_value is None:
            result.expected_null_total += 1
            if actual_value is not None:
                counts.false_positive += 1
                result.false_fills += 1
                result.field_differences.append(f"{field}: expected null, got {actual_value!r}")
                if field in NUMERIC_FIELDS and isinstance(actual_value, (int, float)) and actual_value > 0:
                    result.critical_violations.append(f"Unsupported numeric value in {field}")
        elif actual_value is None:
            counts.false_negative += 1
            result.field_differences.append(f"{field}: expected {expected_value!r}, got null")
        elif expected_value == actual_value:
            counts.true_positive += 1
        else:
            counts.false_positive += 1
            counts.false_negative += 1
            result.field_differences.append(f"{field}: expected {expected_value!r}, got {actual_value!r}")

        if field in NUMERIC_FIELDS and expected_value is not None:
            result.numeric_total += 1
            if expected_value == actual_value:
                result.numeric_correct += 1
        if field == "pain_after" and expected_value is not None:
            result.pain_total += 1
            if expected_value == actual_value:
                result.pain_correct += 1

    result.slot_counts = counts
    for field in fixture.ambiguous_fields:
        result.ambiguity_total += 1
        if getattr(actual, field) is None:
            result.ambiguity_blank += 1
        else:
            result.critical_violations.append(f"Ambiguous field {field} was populated")

    actual_has_notes = bool(actual.notes)
    if actual_has_notes == fixture.expect_notes:
        result.note_presence_correct = 1
    else:
        result.field_differences.append(
            f"notes presence: expected {fixture.expect_notes}, got {actual_has_notes}"
        )

    notes_text = "\n".join(actual.notes).lower()
    for note_fact in fixture.required_note_facts:
        result.required_note_facts_total += 1
        if _matches_any(notes_text, note_fact.patterns):
            result.required_note_facts_correct += 1
        else:
            result.field_differences.append(f"notes missing required fact: {note_fact.id}")

    for note_fact in fixture.forbidden_note_facts:
        result.forbidden_note_facts_total += 1
        if _matches_any(notes_text, note_fact.patterns):
            result.forbidden_note_facts_found += 1
            result.field_differences.append(f"notes contain forbidden fact: {note_fact.id}")

    leakage = _structured_leakage(expected, notes_text)
    if leakage:
        result.structured_field_leakage = True
        result.critical_violations.extend(f"Structured field leaked into notes: {item}" for item in leakage)

    prescription = fixture.exercise.prescription
    for actual_field, prescription_field in (("sets_completed", "sets"), ("reps_per_set", "reps")):
        if getattr(expected, actual_field) is None:
            actual_value = getattr(actual, actual_field)
            prescribed_value = prescription.get(prescription_field)
            if actual_value is not None and actual_value == prescribed_value:
                result.critical_violations.append(f"Possible prescription copy into {actual_field}")

    note_checks_pass = (
        result.note_presence_correct == 1
        and result.required_note_facts_correct == result.required_note_facts_total
        and result.forbidden_note_facts_found == 0
        and not result.structured_field_leakage
    )
    result.exact_form_match = not result.field_differences and note_checks_pass
    return result


def normalized_output(value: StructuredLog) -> tuple:
    return tuple(_normalized(field, getattr(value, field)) for field in SLOT_FIELDS) + (
        tuple(sorted(_normalize_text(note) for note in value.notes)),
    )


def _normalized(field: str, value: object) -> object:
    if value is None:
        return None
    if field == "band_resistance":
        text = _normalize_text(str(value))
        text = re.sub(r"\b(?:resistance|band)\b", "", text)
        return re.sub(r"\s+", " ", text).strip()
    if field == "weight_unit":
        text = _normalize_text(str(value))
        return {"pound": "lb", "pounds": "lb", "lbs": "lb", "kilogram": "kg", "kilograms": "kg"}.get(text, text)
    if field == "weight_value":
        return float(value)
    return value


def _normalize_text(value: str) -> str:
    return re.sub(r"\s+", " ", value.strip().lower())


def _matches_any(text: str, patterns: list[str]) -> bool:
    return any(re.search(pattern, text, flags=re.IGNORECASE) for pattern in patterns)


def _number_pattern(value: int | float) -> str:
    alternatives = [re.escape(f"{value:g}")]
    if isinstance(value, int) or float(value).is_integer():
        word = NUMBER_WORDS.get(int(value))
        if word:
            alternatives.append(re.escape(word))
    return "(?:" + "|".join(alternatives) + ")"


def _structured_leakage(expected: StructuredLog, notes: str) -> list[str]:
    if not notes:
        return []
    patterns: dict[str, str] = {}
    if expected.sets_completed is not None:
        patterns["sets_completed"] = rf"{_number_pattern(expected.sets_completed)}\s+(?:sets?|rounds?)"
    if expected.reps_per_set is not None:
        patterns["reps_per_set"] = rf"{_number_pattern(expected.reps_per_set)}\s+(?:reps?|repetitions?)"
    if expected.duration_seconds is not None:
        patterns["duration_seconds"] = rf"{_number_pattern(expected.duration_seconds)}\s+seconds?"
    if expected.band_resistance:
        patterns["band_resistance"] = re.escape(_normalize_text(expected.band_resistance))
    if expected.weight_value is not None:
        unit = r"(?:lb|lbs|pounds?|kg|kilograms?)"
        patterns["weight"] = rf"{_number_pattern(expected.weight_value)}\s*{unit}"
    if expected.pain_after is not None:
        number = _number_pattern(expected.pain_after)
        patterns["pain_after"] = rf"(?:pain[^\n]{{0,24}}{number}|{number}[^\n]{{0,24}}pain)"
    if expected.each_side:
        patterns["each_side"] = r"(?:each side|both sides)"
    return [field for field, pattern in patterns.items() if re.search(pattern, notes, flags=re.IGNORECASE)]
