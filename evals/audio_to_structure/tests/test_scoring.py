from motionlog_eval.catalog import SCENARIOS
from motionlog_eval.fixtures import VOICES
from motionlog_eval.models import Fixture, StructuredLog
from motionlog_eval.scoring import score


def fixture_for(scenario_id: str) -> Fixture:
    scenario = next(item for item in SCENARIOS if item.id == scenario_id)
    return Fixture(
        id=f"{scenario.id}-direct-{VOICES[0]}",
        scenario_id=scenario.id,
        category=scenario.category,
        variant="direct",
        voice=VOICES[0],
        utterance=scenario.utterances["direct"],
        exercise=scenario.exercise,
        expected=scenario.expected,
        expect_notes=scenario.expect_notes,
        required_note_facts=scenario.required_note_facts,
        forbidden_note_facts=scenario.forbidden_note_facts,
        ambiguous_fields=scenario.ambiguous_fields,
    )


def test_exact_structured_result_passes():
    fixture = fixture_for("straight-01")
    result = score(fixture, fixture.expected)
    assert result.exact_form_match
    assert result.critical_violations == []
    assert result.slot_counts.true_positive == 3


def test_band_color_and_band_phrase_are_equivalent():
    fixture = fixture_for("straight-01")
    actual = fixture.expected.model_copy(update={"band_resistance": "red"})
    result = score(fixture, actual)
    assert result.exact_form_match


def test_pain_in_notes_is_critical_leakage():
    fixture = fixture_for("pain-02")
    actual = fixture.expected.model_copy(update={"notes": ["Pain was five after the exercise"]})
    result = score(fixture, actual)
    assert result.structured_field_leakage
    assert not result.exact_form_match
    assert any("pain_after" in item for item in result.critical_violations)


def test_ambiguous_value_must_remain_blank():
    fixture = fixture_for("ambiguity-01")
    actual = StructuredLog(reps_per_set=10)
    result = score(fixture, actual)
    assert result.ambiguity_blank == 2
    assert result.ambiguity_total == 3
    assert any("reps_per_set" in item for item in result.critical_violations)


def test_required_note_fact_allows_known_paraphrase():
    fixture = fixture_for("pain-06")
    actual = fixture.expected.model_copy(update={"notes": ["Clicking in shoulder on the last set"]})
    result = score(fixture, actual)
    assert result.required_note_facts_correct == 1
    assert result.required_note_facts_total == 1
    assert result.exact_form_match


def test_wrong_numeric_value_counts_as_precision_and_recall_error():
    fixture = fixture_for("straight-02")
    actual = fixture.expected.model_copy(update={"weight_value": 10.0})
    result = score(fixture, actual)
    assert result.slot_counts.false_positive == 1
    assert result.slot_counts.false_negative == 1
    assert not result.exact_form_match
