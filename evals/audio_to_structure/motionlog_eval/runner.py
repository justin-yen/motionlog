from __future__ import annotations

import argparse
import importlib.metadata
import os
from pathlib import Path
import sys
import time

from .audio import KOKORO_MODEL, KOKORO_MODEL_SHA256_PREFIX, KokoroRenderer
from .clients import StageError, SupabaseParserClient, transcribe
from .fixtures import fixtures_for_tier
from .models import RunResult
from .reporting import aggregate, evaluate_gates, git_sha, write_reports
from .scoring import score


def main() -> int:
    parser = argparse.ArgumentParser(description="Run MotionLog's audio-to-structure evaluation")
    parser.add_argument("--tier", choices=("smoke", "full", "stability"), default="smoke")
    parser.add_argument("--output", type=Path, default=Path("evals/audio_to_structure/output"))
    parser.add_argument("--audio-cache", type=Path, default=Path("evals/audio_to_structure/.cache/audio"))
    parser.add_argument("--transcription-url", default=os.getenv("MOTIONLOG_TRANSCRIPTION_URL", "http://127.0.0.1:55330/transcribe"))
    parser.add_argument("--limit", type=int, help="Run only the first N scheduled cases for local diagnostics")
    args = parser.parse_args()

    fixtures = fixtures_for_tier(args.tier)
    if args.limit is not None:
        fixtures = fixtures[:args.limit]
    renderer = KokoroRenderer(args.audio_cache)
    results: list[RunResult] = []
    client: SupabaseParserClient | None = None
    authentication_error: StageError | None = None
    try:
        client = SupabaseParserClient()
        client.authenticate()
    except StageError as error:
        authentication_error = error

    print(f"Running MotionLog {args.tier} audio-to-structure eval with {len(fixtures)} runs")
    for index, fixture in enumerate(fixtures, start=1):
        print(f"[{index:03}/{len(fixtures):03}] {fixture.id} attempt {fixture.attempt}", flush=True)
        started = time.monotonic()
        result = RunResult(fixture=fixture, status="error")
        if authentication_error:
            result.error_stage = "authentication"
            result.error = str(authentication_error)
            result.parser_response_received = authentication_error.response_received
            result.total_ms = round((time.monotonic() - started) * 1000)
            results.append(result)
            continue
        try:
            audio_path, checksum = renderer.render(fixture.id, fixture.utterance, fixture.voice)
            result.audio_checksum = checksum

            transcription_started = time.monotonic()
            transcript = transcribe(audio_path, args.transcription_url)
            result.transcription_ms = round((time.monotonic() - transcription_started) * 1000)
            result.transcription_completed = True
            result.transcript = transcript

            parsing_started = time.monotonic()
            actual = client.parse(transcript, fixture.exercise) if client else None
            result.parsing_ms = round((time.monotonic() - parsing_started) * 1000)
            result.parser_response_received = True
            result.schema_valid = True
            result.actual = actual

            run_score = score(fixture, actual)
            result.score = run_score
            result.status = "passed" if run_score.exact_form_match and not run_score.critical_violations else "failed"
        except StageError as error:
            result.error_stage = error.stage
            result.error = str(error)
            if error.stage == "transcription":
                result.transcription_completed = error.response_received
            if error.stage == "parsing":
                result.parser_response_received = error.response_received
        except Exception as error:
            result.error_stage = "audio" if not result.transcription_completed else "scoring"
            result.error = f"{type(error).__name__}: {error}"
        result.total_ms = round((time.monotonic() - started) * 1000)
        results.append(result)

    metrics = aggregate(results, args.tier)
    gates = evaluate_gates(metrics, args.tier)
    metadata = {
        "git_sha": git_sha(),
        "dataset_version": "1",
        "kokoro_model": KOKORO_MODEL,
        "kokoro_model_sha256_prefix": KOKORO_MODEL_SHA256_PREFIX,
        "kokoro_package": _package_version("kokoro"),
        "whisper_package": _package_version("openai-whisper"),
        "parser_url_host": _safe_host(os.getenv("MOTIONLOG_PARSER_URL") or os.getenv("SUPABASE_URL", "not-configured")),
    }
    write_reports(args.output, args.tier, results, metrics, gates, metadata)
    return 0 if all(gate["passed"] for gate in gates) else 1


def _package_version(name: str) -> str:
    try:
        return importlib.metadata.version(name)
    except importlib.metadata.PackageNotFoundError:
        return "not-installed"


def _safe_host(value: str) -> str:
    from urllib.parse import urlparse

    parsed = urlparse(value)
    return parsed.hostname or "not-configured"


if __name__ == "__main__":
    sys.exit(main())
