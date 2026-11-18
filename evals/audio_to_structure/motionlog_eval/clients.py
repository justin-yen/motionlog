from __future__ import annotations

import json
import os
from pathlib import Path
import urllib.error
import urllib.request

from .models import ExerciseContext, StructuredLog


class StageError(RuntimeError):
    def __init__(self, stage: str, message: str, *, response_received: bool = False) -> None:
        super().__init__(message)
        self.stage = stage
        self.response_received = response_received


def transcribe(audio_path: Path, endpoint: str, timeout: int = 120) -> str:
    request = urllib.request.Request(
        endpoint,
        data=audio_path.read_bytes(),
        headers={"Content-Type": "audio/mp4"},
        method="POST",
    )
    payload = _request_json(request, timeout, "transcription")
    text = payload.get("text")
    if not isinstance(text, str) or not text.strip():
        raise StageError("transcription", "Transcription response did not contain text", response_received=True)
    return text.strip()


class SupabaseParserClient:
    def __init__(self) -> None:
        self.supabase_url = _required_env("SUPABASE_URL").rstrip("/")
        self.anon_key = _required_env("SUPABASE_ANON_KEY")
        self.function_url = os.getenv(
            "MOTIONLOG_PARSER_URL",
            f"{self.supabase_url}/functions/v1/parse-exercise-log",
        )
        self.access_token = os.getenv("MOTIONLOG_ACCESS_TOKEN")

    def authenticate(self) -> None:
        if self.access_token:
            return
        phone = _required_env("MOTIONLOG_TEST_PHONE")
        otp = _required_env("MOTIONLOG_TEST_OTP")
        request = urllib.request.Request(
            f"{self.supabase_url}/auth/v1/verify",
            data=json.dumps({"phone": phone, "token": otp, "type": "sms"}).encode(),
            headers={"apikey": self.anon_key, "Content-Type": "application/json"},
            method="POST",
        )
        payload = _request_json(request, 30, "authentication")
        token = payload.get("access_token")
        if not isinstance(token, str) or not token:
            raise StageError("authentication", "Supabase verification did not return an access token", response_received=True)
        self.access_token = token

    def parse(self, transcript: str, exercise: ExerciseContext) -> StructuredLog:
        if not self.access_token:
            self.authenticate()
        body = {
            "version": 1,
            "transcript": transcript,
            "exercise": exercise.model_dump(mode="json"),
        }
        request = urllib.request.Request(
            self.function_url,
            data=json.dumps(body).encode(),
            headers={
                "apikey": self.anon_key,
                "Authorization": f"Bearer {self.access_token}",
                "Content-Type": "application/json",
            },
            method="POST",
        )
        payload = _request_json(request, 60, "parsing")
        if payload.get("version") != 1 or "extraction" not in payload:
            raise StageError("parsing", "Parser response did not match version 1", response_received=True)
        try:
            return StructuredLog.model_validate(payload["extraction"])
        except Exception as error:
            raise StageError("parsing", f"Parser response failed schema validation: {error}", response_received=True) from error


def _request_json(request: urllib.request.Request, timeout: int, stage: str) -> dict:
    try:
        with urllib.request.urlopen(request, timeout=timeout) as response:
            data = response.read()
    except urllib.error.HTTPError as error:
        detail = error.read().decode(errors="replace")[:500]
        raise StageError(stage, f"HTTP {error.code}: {detail}", response_received=True) from error
    except (urllib.error.URLError, TimeoutError) as error:
        raise StageError(stage, f"Request failed: {error}") from error
    try:
        payload = json.loads(data)
    except json.JSONDecodeError as error:
        raise StageError(stage, "Response was not valid JSON", response_received=True) from error
    if not isinstance(payload, dict):
        raise StageError(stage, "Response JSON was not an object", response_received=True)
    return payload


def _required_env(name: str) -> str:
    value = os.getenv(name)
    if not value:
        raise StageError("authentication", f"Required environment variable {name} is not configured")
    return value
