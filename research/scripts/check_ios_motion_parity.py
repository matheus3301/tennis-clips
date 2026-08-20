from __future__ import annotations

import argparse
import json
import subprocess
import tempfile
from pathlib import Path

import cv2

from tennis_clips.detector import DetectorConfig, audio_candidates, motion_ratio


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("video", type=Path)
    parser.add_argument("wav", type=Path)
    parser.add_argument(
        "--allow-decoder-variance",
        type=int,
        default=0,
        help="maximum AVFoundation/FFmpeg decision differences allowed",
    )
    args = parser.parse_args()
    video_path = args.video.resolve()
    wav_path = args.wav.resolve()
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
    if len(disagreements) <= args.allow_decoder_variance:
        print(
            f"PASS: {len(disagreements)} differences within allowed decoder variance "
            f"of {args.allow_decoder_variance}"
        )
        return 0
    return 1


if __name__ == "__main__":
    raise SystemExit(main())
