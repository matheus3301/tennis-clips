from __future__ import annotations

import subprocess
from pathlib import Path
from typing import Any

import cv2
import numpy as np


LABELS = {
    "forehand": "FOREHAND",
    "backhand": "BACKHAND",
    "serve": "SAQUE",
    "volley": "VOLEIO",
    "smash": "SMASH",
    "unknown": "INDEFINIDO",
}


def _panel(frame: np.ndarray, top_left: tuple[int, int], bottom_right: tuple[int, int],
           opacity: float = 0.72) -> None:
    overlay = frame.copy()
    cv2.rectangle(overlay, top_left, bottom_right, (12, 18, 22), -1)
    cv2.addWeighted(overlay, opacity, frame, 1 - opacity, 0, frame)


def _text(frame: np.ndarray, value: str, position: tuple[int, int], scale: float,
          color: tuple[int, int, int] = (245, 245, 245), thickness: int = 1) -> None:
    cv2.putText(frame, value, position, cv2.FONT_HERSHEY_SIMPLEX, scale, color,
                thickness, cv2.LINE_AA)


def _current_clip(clips: list[dict[str, Any]], time_seconds: float) -> dict[str, Any] | None:
    for clip in clips:
        start = float(clip["output_start"])
        if start <= time_seconds <= start + float(clip["duration"]):
            return clip
    return None


def draw_analytics(frame: np.ndarray, time_seconds: float, payload: dict[str, Any]) -> None:
    height, width = frame.shape[:2]
    unit = width / 720
    shots = payload["shots"]
    elapsed = [shot for shot in shots if float(shot["output_time"]) <= time_seconds]
    counts = {name: sum(shot["shot_type"] == name for shot in elapsed)
              for name in ("forehand", "backhand", "serve", "volley", "smash")}
    clip = _current_clip(payload["clips"], time_seconds)
    rally_index = payload["clips"].index(clip) + 1 if clip else 0
    rally_shots = [shot for shot in shots if clip and shot["clip_id"] == clip["id"]]
    rally_seen = sum(float(shot["output_time"]) <= time_seconds for shot in rally_shots)

    margin = round(22 * unit)
    _panel(frame, (margin, margin), (width - margin, round(142 * unit)))
    _text(frame, "TENNIS CLIPS  /  ANALYTICS V0.3", (round(40 * unit), round(55 * unit)),
          0.55 * unit, (126, 238, 255), max(1, round(1.5 * unit)))
    _text(frame, f"FH {counts['forehand']:02d}   BH {counts['backhand']:02d}   "
                 f"SAQ {counts['serve']:02d}   VOL {counts['volley']:02d}",
          (round(40 * unit), round(92 * unit)), 0.55 * unit,
          thickness=max(1, round(1.5 * unit)))
    _text(frame, f"RALLY {rally_index:02d}/{len(payload['clips']):02d}   "
                 f"GOLPES {rally_seen}/{len(rally_shots)}",
          (round(40 * unit), round(124 * unit)), 0.48 * unit, (205, 214, 220),
          max(1, round(unit)))

    active = [shot for shot in shots
              if -0.22 <= time_seconds - float(shot["output_time"]) <= 1.55]
    if not active:
        return
    shot = min(active, key=lambda item: abs(time_seconds - float(item["output_time"])))
    card_width = round(430 * unit)
    x1 = (width - card_width) // 2
    y2 = height - round(56 * unit)
    y1 = y2 - round(150 * unit)
    _panel(frame, (x1, y1), (x1 + card_width, y2), 0.82)
    label = LABELS.get(shot["shot_type"], shot["shot_type"].upper())
    label_color = (88, 231, 255) if shot["shot_type"] != "unknown" else (180, 190, 198)
    _text(frame, label, (x1 + round(28 * unit), y1 + round(54 * unit)),
          0.95 * unit, label_color, max(2, round(2.2 * unit)))
    response = "DEVOLUCAO DETECTADA" if shot["response_detected"] else "SEM DEVOLUCAO DETECTADA"
    _text(frame, response, (x1 + round(28 * unit), y1 + round(94 * unit)),
          0.45 * unit, (235, 238, 240), max(1, round(unit)))
    _text(frame, f"CONFIANCA {float(shot['shot_type_confidence']):.0%}",
          (x1 + round(28 * unit), y1 + round(128 * unit)), 0.42 * unit,
          (173, 184, 192), max(1, round(unit)))


def render_analytics_overlay(
    base_video: Path,
    output: Path,
    payload: dict[str, Any],
) -> None:
    capture = cv2.VideoCapture(str(base_video))
    if not capture.isOpened():
        raise RuntimeError(f"Nao foi possivel abrir o video base: {base_video}")
    fps = capture.get(cv2.CAP_PROP_FPS) or 30.0
    width = round(capture.get(cv2.CAP_PROP_FRAME_WIDTH))
    height = round(capture.get(cv2.CAP_PROP_FRAME_HEIGHT))
    output.parent.mkdir(parents=True, exist_ok=True)
    command = [
        "ffmpeg", "-hide_banner", "-loglevel", "error", "-y",
        "-f", "rawvideo", "-pix_fmt", "bgr24", "-s", f"{width}x{height}",
        "-r", f"{fps:.6f}", "-i", "pipe:0", "-i", str(base_video),
        "-map", "0:v:0", "-map", "1:a:0", "-c:v", "libx264",
        "-preset", "veryfast", "-crf", "20", "-c:a", "copy",
        "-movflags", "+faststart", "-shortest", str(output),
    ]
    process = subprocess.Popen(command, stdin=subprocess.PIPE)
    assert process.stdin is not None
    frame_index = 0
    print("Renderizando overlay analitico...")
    try:
        while True:
            ok, frame = capture.read()
            if not ok:
                break
            draw_analytics(frame, frame_index / fps, payload)
            process.stdin.write(frame.tobytes())
            frame_index += 1
            if frame_index % round(fps * 30) == 0:
                print(f"  {frame_index / fps:.0f}s processados")
    finally:
        capture.release()
        process.stdin.close()
    return_code = process.wait()
    if return_code != 0:
        raise subprocess.CalledProcessError(return_code, command)
