from motionlog_eval.fixtures import fixtures_for_tier
from motionlog_eval.models import RunResult
from motionlog_eval.reporting import aggregate, evaluate_gates, write_reports
from motionlog_eval.scoring import score


def test_reports_are_self_contained(tmp_path):
    fixture = fixtures_for_tier("smoke")[0]
    run_score = score(fixture, fixture.expected)
    result = RunResult(
        fixture=fixture,
        status="passed",
        transcript=fixture.utterance,
        actual=fixture.expected,
        score=run_score,
        transcription_completed=True,
        parser_response_received=True,
        schema_valid=True,
    )
    metrics = aggregate([result], "smoke")
    assert metrics["forbidden_note_fact_rate"] == 0
    gates = evaluate_gates(metrics, "smoke")
    write_reports(tmp_path, "smoke", [result], metrics, gates, {"git_sha": "test"})

    assert (tmp_path / "results.json").exists()
    assert (tmp_path / "summary.md").exists()
    assert (tmp_path / "junit.xml").exists()
    html = (tmp_path / "report.html").read_text()
    assert "<!doctype html>" in html
    assert "MotionLog audio-to-structure eval" in html
    assert "http" not in html


def test_markdown_failure_report_shows_expected_and_actual_values(tmp_path):
    fixture = fixtures_for_tier("smoke")[0]
    actual = fixture.expected.model_copy(update={"sets_completed": 2})
    result = RunResult(
        fixture=fixture,
        status="failed",
        transcript=fixture.utterance,
        actual=actual,
        score=score(fixture, actual),
        transcription_completed=True,
        parser_response_received=True,
        schema_valid=True,
    )
    metrics = aggregate([result], "smoke")
    write_reports(tmp_path, "smoke", [result], metrics, evaluate_gates(metrics, "smoke"), {"git_sha": "test"})

    markdown = (tmp_path / "summary.md").read_text()
    assert "#### Test case" in markdown
    assert f"| Category | `{fixture.category}` |" in markdown
    assert f"| Exercise | {fixture.exercise.name} |" in markdown
    assert f"| Intended utterance | {fixture.utterance} |" in markdown
    assert f"| Whisper transcript | {fixture.utterance} |" in markdown
    assert "#### Structured output" in markdown
    assert "| Field | Expected | Actual |" in markdown
    assert "| `sets_completed` | `3` | `2` |" in markdown
