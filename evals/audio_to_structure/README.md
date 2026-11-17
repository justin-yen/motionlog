# Audio-to-structure evaluation

This package implements the pipeline defined in [`docs/prds/audio-to-structure-eval-pipeline.md`](../../docs/prds/audio-to-structure-eval-pipeline.md).

It renders fixed utterances with local Kokoro voices, sends the cached audio through MotionLog's local Whisper endpoint, calls the authenticated `parse-exercise-log` Supabase Edge Function, and scores the structured response. It never inserts exercise logs or audio-recording rows.

## Reports

Every run produces:

- `summary.md`, printed in the GitHub Actions log. A separate `always()` workflow step publishes it on the run's **Summary** page even when an evaluation gate fails.
- `report.html`, a self-contained downloadable report with expandable failure details.
- `results.json`, the complete machine-readable evidence.
- `junit.xml`, for CI test integrations.

GitHub Actions uploads all four files as the `motionlog-audio-eval-*` artifact even when release gates fail. Download the artifact and open `report.html` in any browser.

## Required environment

```sh
export SUPABASE_URL="https://your-project.supabase.co"
export SUPABASE_ANON_KEY="your-public-anon-key"
export MOTIONLOG_TEST_PHONE="+12025550147"
export MOTIONLOG_TEST_OTP="123456"
```

Alternatively, set `MOTIONLOG_ACCESS_TOKEN` to an already authenticated test-user access token. The workflow expects the four values above as GitHub Actions secrets.

Do not use a service-role key. The test phone must be configured as a Supabase test number and must not send an SMS.

## Local setup

Use Python 3.12. Kokoro and Whisper share their local model dependencies.

```sh
python3.12 -m venv .venv-audio-eval
source .venv-audio-eval/bin/activate
pip install -r evals/audio_to_structure/requirements.txt
brew install ffmpeg espeak-ng
```

Start the existing simulator transcription service:

```sh
python scripts/dev_transcription_server.py
```

In another terminal, run a tier:

```sh
PYTHONPATH=evals/audio_to_structure \
python -m motionlog_eval.runner --tier smoke
```

Available tiers are `smoke`, `full`, and `stability`. Kokoro audio is generated once under `.cache/audio` and reused byte-for-byte.

## Unit tests

```sh
PYTHONPATH=evals/audio_to_structure \
pytest evals/audio_to_structure/tests
```
