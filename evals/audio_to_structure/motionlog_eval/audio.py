from __future__ import annotations

import hashlib
import importlib.metadata
import json
from pathlib import Path
import subprocess


KOKORO_MODEL = "hexgrad/Kokoro-82M"
KOKORO_MODEL_SHA256_PREFIX = "496dba11"


class KokoroRenderer:
    def __init__(self, cache_directory: Path) -> None:
        self.cache_directory = cache_directory
        self.cache_directory.mkdir(parents=True, exist_ok=True)
        self._pipeline = None

    @property
    def package_version(self) -> str:
        try:
            return importlib.metadata.version("kokoro")
        except importlib.metadata.PackageNotFoundError:
            return "not-installed"

    def render(self, fixture_id: str, utterance: str, voice: str) -> tuple[Path, str]:
        identity = json.dumps(
            {
                "utterance": utterance,
                "voice": voice,
                "kokoro_package": self.package_version,
                "model": KOKORO_MODEL,
                "model_sha256_prefix": KOKORO_MODEL_SHA256_PREFIX,
                "sample_rate": 24_000,
                "format": "m4a-aac",
            },
            sort_keys=True,
        ).encode()
        cache_key = hashlib.sha256(identity).hexdigest()[:16]
        output = self.cache_directory / f"{fixture_id}-{cache_key}.m4a"
        if output.exists():
            return output, _checksum(output)

        wav_path = output.with_suffix(".wav")
        self._render_wav(utterance, voice, wav_path)
        try:
            subprocess.run(
                [
                    "ffmpeg",
                    "-hide_banner",
                    "-loglevel",
                    "error",
                    "-y",
                    "-i",
                    str(wav_path),
                    "-c:a",
                    "aac",
                    "-b:a",
                    "128k",
                    str(output),
                ],
                check=True,
                timeout=120,
            )
        finally:
            wav_path.unlink(missing_ok=True)
        return output, _checksum(output)

    def _render_wav(self, utterance: str, voice: str, output: Path) -> None:
        import numpy as np
        import soundfile as sf
        from kokoro import KPipeline

        if self._pipeline is None:
            self._pipeline = KPipeline(lang_code="a", repo_id=KOKORO_MODEL)
        segments = [audio for _, _, audio in self._pipeline(utterance, voice=voice, speed=1.0)]
        if not segments:
            raise RuntimeError("Kokoro returned no audio")
        combined = np.concatenate(segments)
        sf.write(output, combined, 24_000, subtype="PCM_16")


def _checksum(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()
