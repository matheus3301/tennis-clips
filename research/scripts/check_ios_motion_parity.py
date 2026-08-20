from __future__ import annotations

import json
import subprocess
import sys
import tempfile
from pathlib import Path

import cv2

from tennis_clips.detector import DetectorConfig, audio_candidates, motion_ratio


def main() -> int:
    if len(sys.argv) != 3:
        print("usage: check_ios_motion_parity.py <video> <mono-16000.wav>", file=sys.stderr)
        return 2

    video_path = Path(sys.argv[1]).resolve()
    wav_path = Path(sys.argv[2]).resolve()
    config = DetectorConfig()
    candidates = audio_candidates(wav_path, config)
    times = [candidate["time"] for candidate in candidates]
    core_path = Path(__file__).resolve().parents[2] / "ios" / "core"

    with tempfile.NamedTemporaryFile(mode="w", suffix=".json") as times_file:
        json.dump(times, times_file)
        times_file.flush()
        result = subprocess.run(
            [
                "swift",
                "run",
                "--package-path",
                str(core_path),
                "--quiet",
                "tennis-motion-parity",
                str(video_path),
                times_file.name,
            ],
            check=True,
            capture_output=True,
            text=True,
        )
    swift_results = json.loads(result.stdout)

    capture = cv2.VideoCapture(str(video_path))
    capture.set(cv2.CAP_PROP_ORIENTATION_AUTO, 1)
    if not capture.isOpened():
        raise RuntimeError(f"cannot open {video_path}")
    rows = []
    try:
        for candidate, swift in zip(candidates, swift_results, strict=True):
            python_ratio = motion_ratio(capture, candidate["time"], config)
            rows.append(
                (
                    candidate["time"],
                    python_ratio,
                    swift["motion_ratio"],
                    python_ratio >= config.min_motion_ratio,
                    swift["motion_ratio"] >= config.min_motion_ratio,
                )
            )
    finally:
        capture.release()

    for threshold in (0.05, 0.06, 0.07, 0.075, 0.08, 0.085, 0.09, 0.10):
        python_decisions = [row[1] >= threshold for row in rows]
        swift_decisions = [row[2] >= threshold for row in rows]
        differences = sum(a != b for a, b in zip(python_decisions, swift_decisions, strict=True))
        print(
            f"threshold={threshold:.3f} "
            f"Python={sum(python_decisions)} Swift={sum(swift_decisions)} "
            f"differences={differences}"
        )
        if threshold in (0.07, 0.075):
            for row, python_ok, swift_ok in zip(
                rows, python_decisions, swift_decisions, strict=True
            ):
                if python_ok != swift_ok:
                    print(
                        f"  {row[0]:8.3f}s Python={row[1]:.6f} "
                        f"Swift={row[2]:.6f}"
                    )

    disagreements = [row for row in rows if row[3] != row[4]]
    print(
        f"Python accepted {sum(row[3] for row in rows)}; "
        f"Swift accepted {sum(row[4] for row in rows)}; "
        f"{len(disagreements)} decisions differ"
    )
    for time, python_ratio, swift_ratio, python_ok, swift_ok in disagreements:
        print(
            f"{time:8.3f}s Python={python_ratio:.6f} ({python_ok}) "
            f"Swift={swift_ratio:.6f} ({swift_ok})"
        )
    return 0 if not disagreements else 1


if __name__ == "__main__":
    raise SystemExit(main())
