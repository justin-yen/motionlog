#!/usr/bin/env python3
"""Local-only Whisper endpoint used by the iOS Simulator."""

from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import json
from pathlib import Path
import subprocess
import tempfile


HOST = "127.0.0.1"
PORT = 55330
MAX_AUDIO_BYTES = 25 * 1024 * 1024
MODEL_DIRECTORY = Path(__file__).resolve().parents[1] / ".dev-cache" / "whisper"


class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path != "/health":
            self.send_error(404)
            return
        self.respond(200, {"status": "ok"})

    def do_POST(self):
        if self.path != "/transcribe":
            self.send_error(404)
            return
        try:
            length = int(self.headers.get("Content-Length", "0"))
        except ValueError:
            self.send_error(400, "Invalid Content-Length")
            return
        if length <= 0 or length > MAX_AUDIO_BYTES:
            self.send_error(413, "Audio must be between 1 byte and 25 MB")
            return

        with tempfile.TemporaryDirectory(prefix="motionlog-whisper-") as directory:
            root = Path(directory)
            source = root / "recording.m4a"
            source.write_bytes(self.rfile.read(length))
            result = subprocess.run(
                [
                    "whisper",
                    str(source),
                    "--model",
                    "tiny.en",
                    "--model_dir",
                    str(MODEL_DIRECTORY),
                    "--language",
                    "en",
                    "--task",
                    "transcribe",
                    "--fp16",
                    "False",
                    "--output_format",
                    "txt",
                    "--output_dir",
                    str(root),
                ],
                capture_output=True,
                text=True,
                timeout=120,
            )
            transcript_path = root / "recording.txt"
            if result.returncode != 0 or not transcript_path.exists():
                self.respond(500, {"error": result.stderr.strip() or "Whisper failed"})
                return
            self.respond(200, {"text": transcript_path.read_text().strip()})

    def respond(self, status, payload):
        body = json.dumps(payload).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, format, *args):
        print(f"[motionlog-transcription] {format % args}", flush=True)


if __name__ == "__main__":
    MODEL_DIRECTORY.mkdir(parents=True, exist_ok=True)
    print(f"MotionLog development transcription server listening on http://{HOST}:{PORT}", flush=True)
    ThreadingHTTPServer((HOST, PORT), Handler).serve_forever()
