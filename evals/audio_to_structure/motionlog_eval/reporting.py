from __future__ import annotations

from collections import defaultdict
from datetime import datetime, timezone
from html import escape
import json
import os
from pathlib import Path
import subprocess
import xml.etree.ElementTree as ET

from .models import RunResult
from .scoring import NUMERIC_FIELDS, normalized_output


def aggregate(results: list[RunResult], tier: str) -> dict:
    scheduled = len(results)
    completed = [item for item in results if item.score is not None and item.actual is not None]
    parser_responses = [item for item in results if item.parser_response_received]
    schema_valid = [item for item in results if item.schema_valid]
    scores = [item.score for item in completed if item.score is not None]

    tp = sum(score.slot_counts.true_positive for score in scores)
    fp = sum(score.slot_counts.false_positive for score in scores)
    fn = sum(score.slot_counts.false_negative for score in scores)
    precision = _ratio(tp, tp + fp)
    recall = _ratio(tp, tp + fn)
    slot_f1 = _ratio(2 * precision * recall, precision + recall)

    metrics = {
        "scheduled_runs": scheduled,
        "completed_runs": len(completed),
        "pipeline_completion": _ratio(len(completed), scheduled),
        "schema_valid_rate": _ratio(len(schema_valid), len(parser_responses)),
        "critical_violations": sum(len(score.critical_violations) for score in scores),
        "slot_precision": precision,
        "slot_recall": recall,
        "slot_f1": slot_f1,
        "numeric_accuracy": _ratio(sum(score.numeric_correct for score in scores), sum(score.numeric_total for score in scores)),
        "pain_accuracy": _ratio(sum(score.pain_correct for score in scores), sum(score.pain_total for score in scores)),
        "false_fill_rate": _ratio(sum(score.false_fills for score in scores), sum(score.expected_null_total for score in scores)),
        "ambiguity_blank_rate": _ratio(sum(score.ambiguity_blank for score in scores), sum(score.ambiguity_total for score in scores)),
        "note_presence_accuracy": _ratio(sum(score.note_presence_correct for score in scores), sum(score.note_presence_total for score in scores)),
        "required_note_fact_retention": _ratio(sum(score.required_note_facts_correct for score in scores), sum(score.required_note_facts_total for score in scores)),
        "structured_field_leakage_cases": sum(1 for score in scores if score.structured_field_leakage),
        "forbidden_note_fact_rate": _error_ratio(sum(score.forbidden_note_facts_found for score in scores), sum(score.forbidden_note_facts_total for score in scores)),
        "exact_form_match": _ratio(sum(1 for score in scores if score.exact_form_match), scheduled),
    }

    metrics["numeric_by_field"] = _numeric_field_accuracy(completed)
    metrics["categories"] = _category_metrics(results)
    metrics["scenario_robustness_rate"] = _scenario_robustness(results) if tier == "full" else None
    stability = _stability_metrics(completed) if tier == "stability" else None
    metrics["repeated_output_consistency"] = stability[0] if stability else None
    metrics["critical_output_consistency"] = stability[1] if stability else None
    metrics["latency_ms"] = {
        "transcription_average": _average([item.transcription_ms for item in completed]),
        "parsing_average": _average([item.parsing_ms for item in completed]),
        "total_average": _average([item.total_ms for item in completed]),
    }
    return metrics


def evaluate_gates(metrics: dict, tier: str) -> list[dict]:
    gates: list[tuple[str, bool, str]] = []

    def add(name: str, condition: bool, observed: str) -> None:
        gates.append((name, condition, observed))

    if tier == "smoke":
        add("Scheduled run count = 48", metrics["scheduled_runs"] == 48, str(metrics["scheduled_runs"]))
        add("Pipeline completion = 100%", metrics["pipeline_completion"] == 1, _pct(metrics["pipeline_completion"]))
        add("Schema-valid responses = 100%", metrics["schema_valid_rate"] == 1, _pct(metrics["schema_valid_rate"]))
        add("Critical constraint violations = 0", metrics["critical_violations"] == 0, str(metrics["critical_violations"]))
        add("Slot F1 ≥ 95%", metrics["slot_f1"] >= .95, _pct(metrics["slot_f1"]))
        add("Numeric field accuracy = 100%", metrics["numeric_accuracy"] == 1, _pct(metrics["numeric_accuracy"]))
        add("Pain accuracy = 100%", metrics["pain_accuracy"] == 1, _pct(metrics["pain_accuracy"]))
        add("False-fill rate = 0%", metrics["false_fill_rate"] == 0, _pct(metrics["false_fill_rate"]))
        add("Ambiguity blank rate = 100%", metrics["ambiguity_blank_rate"] == 1, _pct(metrics["ambiguity_blank_rate"]))
        add("Note presence accuracy = 100%", metrics["note_presence_accuracy"] == 1, _pct(metrics["note_presence_accuracy"]))
        add("Required note-fact retention ≥ 90%", metrics["required_note_fact_retention"] >= .90, _pct(metrics["required_note_fact_retention"]))
        add("Structured-field leakage = 0", metrics["structured_field_leakage_cases"] == 0, str(metrics["structured_field_leakage_cases"]))
        add("Forbidden note facts = 0%", metrics["forbidden_note_fact_rate"] == 0, _pct(metrics["forbidden_note_fact_rate"]))
        add("Exact form match ≥ 90%", metrics["exact_form_match"] >= .90, _pct(metrics["exact_form_match"]))
    elif tier == "full":
        add("Scheduled run count = 360", metrics["scheduled_runs"] == 360, str(metrics["scheduled_runs"]))
        add("Pipeline completion ≥ 99%", metrics["pipeline_completion"] >= .99, _pct(metrics["pipeline_completion"]))
        add("Schema-valid responses ≥ 99.5%", metrics["schema_valid_rate"] >= .995, _pct(metrics["schema_valid_rate"]))
        add("Critical constraint violations = 0", metrics["critical_violations"] == 0, str(metrics["critical_violations"]))
        add("Slot F1 ≥ 92%", metrics["slot_f1"] >= .92, _pct(metrics["slot_f1"]))
        add("Every category slot F1 ≥ 85%", all(value["slot_f1"] >= .85 for value in metrics["categories"].values()), _minimum_category(metrics, "slot_f1"))
        add("Numeric accuracy ≥ 95%", metrics["numeric_accuracy"] >= .95, _pct(metrics["numeric_accuracy"]))
        add("Every numeric field accuracy ≥ 90%", all(value >= .90 for value in metrics["numeric_by_field"].values()), _minimum_mapping(metrics["numeric_by_field"]))
        add("Pain accuracy ≥ 95%", metrics["pain_accuracy"] >= .95, _pct(metrics["pain_accuracy"]))
        add("False-fill rate ≤ 1%", metrics["false_fill_rate"] <= .01, _pct(metrics["false_fill_rate"]))
        add("Ambiguity blank rate ≥ 98%", metrics["ambiguity_blank_rate"] >= .98, _pct(metrics["ambiguity_blank_rate"]))
        add("Note presence accuracy ≥ 95%", metrics["note_presence_accuracy"] >= .95, _pct(metrics["note_presence_accuracy"]))
        add("Required note-fact retention ≥ 90%", metrics["required_note_fact_retention"] >= .90, _pct(metrics["required_note_fact_retention"]))
        add("Structured-field leakage = 0", metrics["structured_field_leakage_cases"] == 0, str(metrics["structured_field_leakage_cases"]))
        add("Forbidden note-fact rate ≤ 1%", metrics["forbidden_note_fact_rate"] <= .01, _pct(metrics["forbidden_note_fact_rate"]))
        add("Exact form match ≥ 85%", metrics["exact_form_match"] >= .85, _pct(metrics["exact_form_match"]))
        add("Every category exact match ≥ 75%", all(value["exact_form_match"] >= .75 for value in metrics["categories"].values()), _minimum_category(metrics, "exact_form_match"))
        add("Scenario robustness ≥ 90%", metrics["scenario_robustness_rate"] >= .90, _pct(metrics["scenario_robustness_rate"]))
    elif tier == "stability":
        add("Scheduled run count = 90", metrics["scheduled_runs"] == 90, str(metrics["scheduled_runs"]))
        add("Pipeline completion = 100%", metrics["pipeline_completion"] == 1, _pct(metrics["pipeline_completion"]))
        add("Schema-valid responses = 100%", metrics["schema_valid_rate"] == 1, _pct(metrics["schema_valid_rate"]))
        add("Critical constraint violations = 0", metrics["critical_violations"] == 0, str(metrics["critical_violations"]))
        add("Slot F1 ≥ 95%", metrics["slot_f1"] >= .95, _pct(metrics["slot_f1"]))
        add("Numeric accuracy ≥ 98%", metrics["numeric_accuracy"] >= .98, _pct(metrics["numeric_accuracy"]))
        add("Pain accuracy = 100%", metrics["pain_accuracy"] == 1, _pct(metrics["pain_accuracy"]))
        add("False-fill rate = 0%", metrics["false_fill_rate"] == 0, _pct(metrics["false_fill_rate"]))
        add("Ambiguity blank rate = 100%", metrics["ambiguity_blank_rate"] == 1, _pct(metrics["ambiguity_blank_rate"]))
        add("Note presence accuracy = 100%", metrics["note_presence_accuracy"] == 1, _pct(metrics["note_presence_accuracy"]))
        add("Required note-fact retention ≥ 95%", metrics["required_note_fact_retention"] >= .95, _pct(metrics["required_note_fact_retention"]))
        add("Structured-field leakage = 0", metrics["structured_field_leakage_cases"] == 0, str(metrics["structured_field_leakage_cases"]))
        add("Forbidden note facts = 0%", metrics["forbidden_note_fact_rate"] == 0, _pct(metrics["forbidden_note_fact_rate"]))
        add("Exact form match ≥ 90%", metrics["exact_form_match"] >= .90, _pct(metrics["exact_form_match"]))
        add("Repeated output consistency ≥ 96.7%", metrics["repeated_output_consistency"] >= .967, _pct(metrics["repeated_output_consistency"]))
        add("Critical output consistency = 100%", metrics["critical_output_consistency"] == 1, _pct(metrics["critical_output_consistency"]))
    else:
        raise ValueError(f"Unknown tier: {tier}")
    return [{"name": name, "passed": passed, "observed": observed} for name, passed, observed in gates]


def write_reports(output: Path, tier: str, results: list[RunResult], metrics: dict, gates: list[dict], metadata: dict) -> None:
    output.mkdir(parents=True, exist_ok=True)
    passed = all(item["passed"] for item in gates)
    payload = {
        "tier": tier,
        "passed": passed,
        "generated_at": datetime.now(timezone.utc).isoformat(),
        "metadata": metadata,
        "metrics": metrics,
        "gates": gates,
        "results": [item.model_dump(mode="json") for item in results],
    }
    (output / "results.json").write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n")
    markdown = _markdown_report(payload)
    (output / "summary.md").write_text(markdown)
    (output / "report.html").write_text(_html_report(payload))
    _write_junit(output / "junit.xml", tier, results, gates)
    print(markdown)
    summary_path = os.getenv("GITHUB_STEP_SUMMARY")
    if summary_path:
        with Path(summary_path).open("a") as handle:
            handle.write(markdown)


def git_sha() -> str:
    try:
        return subprocess.check_output(["git", "rev-parse", "HEAD"], text=True).strip()
    except (subprocess.CalledProcessError, FileNotFoundError):
        return "unknown"


def _ratio(numerator: float, denominator: float) -> float:
    return numerator / denominator if denominator else 1.0


def _error_ratio(numerator: float, denominator: float) -> float:
    return numerator / denominator if denominator else 0.0


def _average(values: list[int | None]) -> int | None:
    present = [item for item in values if item is not None]
    return round(sum(present) / len(present)) if present else None


def _pct(value: float | None) -> str:
    return "n/a" if value is None else f"{value * 100:.1f}%"


def _numeric_field_accuracy(results: list[RunResult]) -> dict[str, float]:
    output: dict[str, float] = {}
    for field in NUMERIC_FIELDS:
        opportunities = [item for item in results if getattr(item.fixture.expected, field) is not None]
        correct = sum(getattr(item.fixture.expected, field) == getattr(item.actual, field) for item in opportunities if item.actual)
        output[field] = _ratio(correct, len(opportunities))
    return output


def _category_metrics(results: list[RunResult]) -> dict[str, dict[str, float]]:
    grouped: dict[str, list[RunResult]] = defaultdict(list)
    for item in results:
        grouped[item.fixture.category].append(item)
    output = {}
    for category, items in sorted(grouped.items()):
        scores = [item.score for item in items if item.score]
        tp = sum(score.slot_counts.true_positive for score in scores)
        fp = sum(score.slot_counts.false_positive for score in scores)
        fn = sum(score.slot_counts.false_negative for score in scores)
        precision = _ratio(tp, tp + fp)
        recall = _ratio(tp, tp + fn)
        output[category] = {
            "slot_f1": _ratio(2 * precision * recall, precision + recall),
            "exact_form_match": _ratio(sum(score.exact_form_match for score in scores), len(items)),
        }
    return output


def _scenario_robustness(results: list[RunResult]) -> float:
    grouped: dict[str, list[RunResult]] = defaultdict(list)
    for item in results:
        grouped[item.fixture.scenario_id].append(item)
    robust = 0
    for items in grouped.values():
        exact = sum(bool(item.score and item.score.exact_form_match) for item in items)
        critical = sum(len(item.score.critical_violations) for item in items if item.score)
        if len(items) == 6 and exact >= 5 and critical == 0:
            robust += 1
    return _ratio(robust, len(grouped))


def _stability_metrics(results: list[RunResult]) -> tuple[float, float]:
    grouped: dict[str, list[RunResult]] = defaultdict(list)
    for item in results:
        grouped[item.fixture.id].append(item)
    identical = 0
    critical_identical = 0
    for items in grouped.values():
        if len(items) != 3 or any(item.actual is None for item in items):
            continue
        outputs = [normalized_output(item.actual) for item in items if item.actual]
        if len(set(outputs)) == 1:
            identical += 1
        critical = [
            (
                item.actual.sets_completed,
                item.actual.reps_per_set,
                item.actual.duration_seconds,
                item.actual.weight_value,
                item.actual.pain_after,
                tuple(getattr(item.actual, field) is None for field in ("sets_completed", "reps_per_set", "duration_seconds", "band_resistance", "weight_value", "pain_after", "each_side")),
            )
            for item in items
            if item.actual
        ]
        if len(set(critical)) == 1:
            critical_identical += 1
    return _ratio(identical, len(grouped)), _ratio(critical_identical, len(grouped))


def _minimum_mapping(values: dict[str, float]) -> str:
    key = min(values, key=values.get)
    return f"{key}: {_pct(values[key])}"


def _minimum_category(metrics: dict, key: str) -> str:
    values = {name: value[key] for name, value in metrics["categories"].items()}
    return _minimum_mapping(values)


def _markdown_report(payload: dict) -> str:
    icon = "✅" if payload["passed"] else "❌"
    metrics = payload["metrics"]
    lines = [
        f"# {icon} MotionLog audio-to-structure eval — {payload['tier']}",
        "",
        f"**Result:** {'PASS' if payload['passed'] else 'FAIL'}  ",
        f"**Runs:** {metrics['completed_runs']}/{metrics['scheduled_runs']} completed  ",
        f"**Exact form match:** {_pct(metrics['exact_form_match'])}  ",
        f"**Slot F1:** {_pct(metrics['slot_f1'])}",
        "",
        "## Release gates",
        "",
        "| Gate | Observed | Status |",
        "|---|---:|:---:|",
    ]
    for gate in payload["gates"]:
        lines.append(f"| {gate['name']} | {gate['observed']} | {'✅' if gate['passed'] else '❌'} |")
    failures = [item for item in payload["results"] if item["status"] != "passed"]
    lines.extend(["", "## Failures", ""])
    if not failures:
        lines.append("No failed fixtures.")
    else:
        lines.append("| Fixture | Stage | Details |")
        lines.append("|---|---|---|")
        for item in failures[:25]:
            differences = item.get("score", {}).get("field_differences", []) if item.get("score") else []
            details = item.get("error") or "; ".join(differences) or "Did not meet exact-match requirements"
            details = details.replace("|", "\\|").replace("\n", " ")[:240]
            lines.append(f"| `{item['fixture']['id']}` | {item.get('error_stage') or 'scoring'} | {details} |")
        if len(failures) > 25:
            lines.append(f"\nShowing 25 of {len(failures)} failures. Download the HTML report for all details.")
    lines.append("")
    return "\n".join(lines)


def _html_report(payload: dict) -> str:
    passed = payload["passed"]
    metrics = payload["metrics"]
    gate_rows = "".join(
        f"<tr><td>{escape(gate['name'])}</td><td>{escape(gate['observed'])}</td><td class='status {'pass' if gate['passed'] else 'fail'}'>{'PASS' if gate['passed'] else 'FAIL'}</td></tr>"
        for gate in payload["gates"]
    )
    result_rows = []
    for item in payload["results"]:
        if item["status"] == "passed":
            continue
        score = item.get("score") or {}
        differences = score.get("field_differences", [])
        critical = score.get("critical_violations", [])
        expected = json.dumps(item["fixture"]["expected"], indent=2)
        actual = json.dumps(item.get("actual"), indent=2)
        details = escape(item.get("error") or "\n".join(differences + critical) or "Exact form mismatch")
        result_rows.append(
            "<details><summary><strong>" + escape(item["fixture"]["id"]) + "</strong> — " + escape(item.get("error_stage") or "scoring") + "</summary>"
            + f"<p>{details}</p><div class='columns'><div><h4>Expected</h4><pre>{escape(expected)}</pre></div><div><h4>Actual</h4><pre>{escape(actual)}</pre></div></div>"
            + f"<h4>Intended utterance</h4><p>{escape(item['fixture']['utterance'])}</p><h4>Transcript</h4><p>{escape(item.get('transcript') or 'Unavailable')}</p></details>"
        )
    failures_html = "".join(result_rows) or "<p>No failed fixtures.</p>"
    return f"""<!doctype html>
<html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>MotionLog eval report</title><style>
:root{{--ink:#122033;--muted:#607087;--bg:#f5f7fb;--card:#fff;--green:#18794e;--red:#c9372c;--line:#dce2ea}}
*{{box-sizing:border-box}}body{{margin:0;background:var(--bg);color:var(--ink);font:15px/1.5 -apple-system,BlinkMacSystemFont,"Segoe UI",sans-serif}}
main{{max-width:1100px;margin:0 auto;padding:40px 20px 80px}}h1{{margin:0 0 8px;font-size:32px}}h2{{margin-top:36px}}.muted{{color:var(--muted)}}
.banner{{padding:22px 24px;border-radius:16px;background:{'#e7f6ef' if passed else '#fff0ef'};border:1px solid {'#9dd9bd' if passed else '#f0b5b0'}}}
.grid{{display:grid;grid-template-columns:repeat(auto-fit,minmax(170px,1fr));gap:12px;margin:18px 0}}.card{{background:var(--card);border:1px solid var(--line);border-radius:12px;padding:16px}}.value{{font-size:26px;font-weight:750}}
table{{width:100%;border-collapse:collapse;background:var(--card);border-radius:12px;overflow:hidden}}th,td{{padding:11px 14px;border-bottom:1px solid var(--line);text-align:left}}th{{background:#eef2f7}}.status{{font-weight:750}}.pass{{color:var(--green)}}.fail{{color:var(--red)}}
details{{background:var(--card);border:1px solid var(--line);border-radius:10px;padding:12px 15px;margin:10px 0}}summary{{cursor:pointer}}.columns{{display:grid;grid-template-columns:1fr 1fr;gap:14px}}pre{{overflow:auto;background:#101827;color:#edf2f7;padding:12px;border-radius:8px;font-size:12px}}@media(max-width:700px){{.columns{{grid-template-columns:1fr}}}}
</style></head><body><main>
<section class="banner"><h1>{'✓' if passed else '✕'} MotionLog audio-to-structure eval</h1><div class="muted">Tier: {escape(payload['tier'])} · Generated {escape(payload['generated_at'])}</div></section>
<section class="grid"><div class="card"><div class="muted">Overall</div><div class="value {'pass' if passed else 'fail'}">{'PASS' if passed else 'FAIL'}</div></div><div class="card"><div class="muted">Completed</div><div class="value">{metrics['completed_runs']}/{metrics['scheduled_runs']}</div></div><div class="card"><div class="muted">Exact form</div><div class="value">{_pct(metrics['exact_form_match'])}</div></div><div class="card"><div class="muted">Slot F1</div><div class="value">{_pct(metrics['slot_f1'])}</div></div></section>
<h2>Release gates</h2><table><thead><tr><th>Gate</th><th>Observed</th><th>Status</th></tr></thead><tbody>{gate_rows}</tbody></table>
<h2>Failed fixtures</h2>{failures_html}
</main></body></html>"""


def _write_junit(path: Path, tier: str, results: list[RunResult], gates: list[dict]) -> None:
    failures = sum(item.status != "passed" for item in results) + (0 if all(gate["passed"] for gate in gates) else 1)
    suite = ET.Element("testsuite", name=f"motionlog-audio-eval-{tier}", tests=str(len(results) + 1), failures=str(failures))
    for item in results:
        case = ET.SubElement(suite, "testcase", classname=item.fixture.category, name=f"{item.fixture.id}-attempt-{item.fixture.attempt}")
        if item.status != "passed":
            failure = ET.SubElement(case, "failure", message=item.error or "Structured output mismatch")
            differences = item.score.field_differences + item.score.critical_violations if item.score else []
            failure.text = "\n".join(differences) or item.error or "Unknown failure"
    gate_case = ET.SubElement(suite, "testcase", classname="release-gates", name=tier)
    failed_gates = [gate for gate in gates if not gate["passed"]]
    if failed_gates:
        failure = ET.SubElement(gate_case, "failure", message="Tier thresholds were not met")
        failure.text = "\n".join(f"{gate['name']}: {gate['observed']}" for gate in failed_gates)
    ET.ElementTree(suite).write(path, encoding="utf-8", xml_declaration=True)
