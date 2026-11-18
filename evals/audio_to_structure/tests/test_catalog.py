from collections import Counter

from motionlog_eval.catalog import SCENARIOS
from motionlog_eval.fixtures import fixtures_for_tier


def test_catalog_has_planned_distribution():
    assert len(SCENARIOS) == 60
    assert Counter(item.category for item in SCENARIOS) == {
        "straightforward": 20,
        "conversational": 10,
        "correction_ambiguity": 10,
        "pain_symptoms": 10,
        "timed": 5,
        "irrelevant_adversarial": 5,
    }
    assert all(len(item.utterances) == 3 for item in SCENARIOS)


def test_tier_fixture_counts_are_stable():
    assert len(fixtures_for_tier("smoke")) == 48
    assert len(fixtures_for_tier("full")) == 360
    assert len(fixtures_for_tier("stability")) == 90


def test_stability_repeats_identical_audio_inputs():
    fixtures = fixtures_for_tier("stability")
    first = fixtures[:3]
    assert len({item.id for item in first}) == 1
    assert len({item.utterance for item in first}) == 1
    assert [item.attempt for item in first] == [1, 2, 3]
