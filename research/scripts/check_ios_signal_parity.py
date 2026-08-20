from __future__ import annotations

import json
import subprocess
import sys
import tempfile
from pathlib import Path

import numpy as np
from scipy.io import wavfile

from tennis_clips.detector import DetectorConfig, audio_candidates


def main() -> int:
    if len(sys.argv) != 2:
        print("usage: check_ios_signal_parity.py <mono-16000.wav>", file=sys.stderr)
        return 2

    wav_path = Path(sys.argv[1]).resolve()
    sample_rate, samples = wavfile.read(wav_path)
    if sample_rate != 16_000:
        raise ValueError(f"expected 16000 Hz, got {sample_rate}")
    if samples.ndim > 1:
        samples = samples.mean(axis=1)
    if np.issubdtype(samples.dtype, np.integer):
        scale = max(abs(np.iinfo(samples.dtype).min), np.iinfo(samples.dtype).max)
        samples = samples.astype(np.float32) / scale
    else:
        samples = samples.astype(np.float32)

    python_candidates = audio_candidates(wav_path, DetectorConfig())
    core_path = Path(__file__).resolve().parents[2] / "ios" / "core"
    with tempfile.NamedTemporaryFile(suffix=".f32") as raw_audio:
        samples.astype("<f4", copy=False).tofile(raw_audio.name)
        result = subprocess.run(
            [
                "swift",
                "run",
                "--package-path",
                str(core_path),
                "--quiet",
                "tennis-signal-parity",
                raw_audio.name,
            ],
            check=True,
            capture_output=True,
            text=True,
        )
    swift_candidates = json.loads(result.stdout)

    if len(python_candidates) != len(swift_candidates):
        print(
            f"FAIL candidate count: Python={len(python_candidates)} Swift={len(swift_candidates)}"
        )
        return 1

    worst_delta = 0.0
    for python, swift in zip(python_candidates, swift_candidates, strict=True):
        worst_delta = max(worst_delta, abs(python["time"] - swift["time"]))
    if worst_delta > 0.005:
        print(f"FAIL maximum timestamp delta: {worst_delta:.6f}s")
        return 1

    print(
        f"PASS {len(python_candidates)} candidates; "
        f"maximum timestamp delta {worst_delta:.6f}s"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
