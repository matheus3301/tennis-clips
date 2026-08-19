from __future__ import annotations

import json
import shutil
import subprocess
from dataclasses import asdict, dataclass
from pathlib import Path
from typing import Any

import cv2
import numpy as np
from scipy.io import wavfile
from scipy.signal import butter, find_peaks, sosfiltfilt


@dataclass(frozen=True)
class DetectorConfig:
    audio_sample_rate: int = 16_000
    analysis_rate: int = 200
    amplitude_percentile: float = 98.5
    min_event_distance: float = 0.7
    min_mid_energy_ratio: float = 0.07
    max_high_energy_ratio: float = 0.35
    min_motion_ratio: float = 0.08
    motion_offset: float = 0.05
    motion_pixel_threshold: int = 25
    shirt_hue_min: int = 18
    shirt_hue_max: int = 42


@dataclass(frozen=True)
class Event:
    time: float
    score: float
    amplitude: float
    mid_energy_ratio: float
    high_energy_ratio: float
    motion_ratio: float


def require_media_tools() -> None:
    missing = [name for name in ("ffmpeg", "ffprobe") if shutil.which(name) is None]
    if missing:
        raise RuntimeError(f"Ferramentas ausentes no PATH: {', '.join(missing)}")


def probe_video(video: Path) -> dict[str, Any]:
    require_media_tools()
    command = [
        "ffprobe", "-v", "error", "-show_entries",
        "format=duration,size:stream=index,codec_type,codec_name,width,height,r_frame_rate",
        "-of", "json", str(video),
    ]
    result = subprocess.run(command, check=True, capture_output=True, text=True)
    return json.loads(result.stdout)


def extract_audio(video: Path, wav_path: Path, sample_rate: int) -> None:
    wav_path.parent.mkdir(parents=True, exist_ok=True)
    command = [
        "ffmpeg", "-hide_banner", "-loglevel", "error", "-y", "-i", str(video),
        "-map", "0:a:0", "-ac", "1", "-ar", str(sample_rate), str(wav_path),
    ]
    subprocess.run(command, check=True)


def _band_envelope(
    samples: np.ndarray,
    sample_rate: int,
    band: tuple[int, int],
    analysis_rate: int,
) -> np.ndarray:
    sos = butter(4, band, btype="bandpass", fs=sample_rate, output="sos")
    filtered = sosfiltfilt(sos, samples)
    window_size = max(1, round(sample_rate * 0.008))
    kernel = np.ones(window_size, dtype=np.float32) / window_size
    envelope = np.sqrt(np.convolve(filtered * filtered, kernel, mode="same"))
    step = max(1, round(sample_rate / analysis_rate))
    return envelope[::step]


def audio_candidates(wav_path: Path, config: DetectorConfig) -> list[dict[str, float]]:
    sample_rate, samples = wavfile.read(wav_path)
    if samples.ndim > 1:
        samples = samples.mean(axis=1)
    if np.issubdtype(samples.dtype, np.integer):
        scale = max(abs(np.iinfo(samples.dtype).min), np.iinfo(samples.dtype).max)
        samples = samples.astype(np.float32) / scale
    else:
        samples = samples.astype(np.float32)

    envelopes = {
        "full": _band_envelope(samples, sample_rate, (80, 7_500), config.analysis_rate),
        "mid": _band_envelope(samples, sample_rate, (600, 4_800), config.analysis_rate),
        "high": _band_envelope(samples, sample_rate, (1_800, 7_500), config.analysis_rate),
    }
    full = envelopes["full"]
    threshold = float(np.percentile(full, config.amplitude_percentile))
    peak_indexes, properties = find_peaks(
        full,
        distance=round(config.min_event_distance * config.analysis_rate),
        height=threshold,
        prominence=threshold * 0.5,
    )

    candidates: list[dict[str, float]] = []
    for index, amplitude in zip(peak_indexes, properties["peak_heights"], strict=True):
        safe_amplitude = max(float(amplitude), 1e-9)
        mid_ratio = float((envelopes["mid"][index] / safe_amplitude) ** 2)
        high_ratio = float((envelopes["high"][index] / safe_amplitude) ** 2)
        if mid_ratio < config.min_mid_energy_ratio or high_ratio > config.max_high_energy_ratio:
            continue
        candidates.append({
            "time": float(index / config.analysis_rate),
            "amplitude": safe_amplitude,
            "threshold": threshold,
            "mid_energy_ratio": mid_ratio,
            "high_energy_ratio": high_ratio,
        })
    return candidates


def _read_frame(capture: cv2.VideoCapture, time_seconds: float) -> np.ndarray | None:
    capture.set(cv2.CAP_PROP_POS_MSEC, max(0.0, time_seconds) * 1_000)
    ok, frame = capture.read()
    if not ok:
        return None
    return cv2.resize(frame, (270, 480), interpolation=cv2.INTER_AREA)


def _player_roi(frame: np.ndarray, config: DetectorConfig) -> tuple[int, int, int, int]:
    height, width = frame.shape[:2]
    hsv = cv2.cvtColor(frame, cv2.COLOR_BGR2HSV)
    mask = cv2.inRange(
        hsv,
        (config.shirt_hue_min, 90, 90),
        (config.shirt_hue_max, 255, 255),
    )
    mask[: round(height * 0.40)] = 0
    count, _, stats, _ = cv2.connectedComponentsWithStats(mask)
    components = [index for index in range(1, count) if stats[index, cv2.CC_STAT_AREA] > 50]
    if not components:
        return 0, round(height * 0.35), width, round(height * 0.80)

    component = max(components, key=lambda index: stats[index, cv2.CC_STAT_AREA])
    x, y, box_width, box_height, _ = stats[component]
    center_x = x + box_width / 2
    center_y = y + box_height / 2
    roi_width = max(90.0, box_width * 3.0)
    roi_height = max(140.0, box_height * 2.4)
    return (
        max(0, round(center_x - roi_width / 2)),
        max(round(height * 0.35), round(center_y - roi_height / 2)),
        min(width, round(center_x + roi_width / 2)),
        min(height, round(center_y + roi_height / 2)),
    )


def motion_ratio(
    capture: cv2.VideoCapture,
    event_time: float,
    config: DetectorConfig,
) -> float:
    frames = [
        _read_frame(capture, event_time - config.motion_offset),
        _read_frame(capture, event_time),
        _read_frame(capture, event_time + config.motion_offset),
    ]
    if any(frame is None for frame in frames):
        return 0.0
    before, center, after = frames
    assert before is not None and center is not None and after is not None
    x1, y1, x2, y2 = _player_roi(center, config)

    gray_frames = []
    for frame in (before, after):
        gray = cv2.cvtColor(frame, cv2.COLOR_BGR2GRAY)
        gray = cv2.GaussianBlur(gray, (5, 5), 0)
        gray_frames.append(gray[y1:y2, x1:x2])
    difference = cv2.absdiff(gray_frames[0], gray_frames[1])
    return float(np.mean(difference > config.motion_pixel_threshold))


def detect_events(
    video: Path,
    work_dir: Path,
    config: DetectorConfig | None = None,
) -> tuple[list[Event], dict[str, Any]]:
    config = config or DetectorConfig()
    work_dir.mkdir(parents=True, exist_ok=True)
    wav_path = work_dir / f"{video.stem}-mono-{config.audio_sample_rate}.wav"
    if not wav_path.exists():
        print("Extraindo o audio do video...")
        extract_audio(video, wav_path, config.audio_sample_rate)

    print("Procurando transientes com assinatura de raquetada...")
    candidates = audio_candidates(wav_path, config)
    print(f"{len(candidates)} candidatos de audio; validando movimento do jogador...")

    capture = cv2.VideoCapture(str(video))
    if not capture.isOpened():
        raise RuntimeError(f"Nao foi possivel abrir o video: {video}")
    events: list[Event] = []
    try:
        for position, candidate in enumerate(candidates, start=1):
            movement = motion_ratio(capture, candidate["time"], config)
            if movement < config.min_motion_ratio:
                continue
            amplitude_score = candidate["amplitude"] / candidate["threshold"]
            spectral_score = min(2.0, candidate["mid_energy_ratio"] / 0.15)
            motion_score = min(2.0, movement / config.min_motion_ratio)
            score = amplitude_score * (0.5 + 0.25 * spectral_score + 0.25 * motion_score)
            events.append(Event(
                time=candidate["time"],
                score=float(score),
                amplitude=candidate["amplitude"],
                mid_energy_ratio=candidate["mid_energy_ratio"],
                high_energy_ratio=candidate["high_energy_ratio"],
                motion_ratio=movement,
            ))
            if position % 25 == 0:
                print(f"  {position}/{len(candidates)} candidatos analisados")
    finally:
        capture.release()

    metadata = {
        "input": str(video),
        "config": asdict(config),
        "video": probe_video(video),
        "audio_candidates": len(candidates),
        "accepted_events": len(events),
    }
    return events, metadata


def save_analysis(path: Path, events: list[Event], metadata: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    payload = {**metadata, "events": [asdict(event) for event in events]}
    path.write_text(json.dumps(payload, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def load_events(path: Path) -> list[Event]:
    payload = json.loads(path.read_text(encoding="utf-8"))
    return [Event(**item) for item in payload["events"]]


def create_review_sheet(
    video: Path,
    events: list[Event],
    output: Path,
    columns: int = 6,
) -> None:
    if not events:
        return
    capture = cv2.VideoCapture(str(video))
    thumbs: list[np.ndarray] = []
    try:
        for number, event in enumerate(events, start=1):
            frame = _read_frame(capture, event.time)
            if frame is None:
                continue
            frame = cv2.resize(frame, (180, 320), interpolation=cv2.INTER_AREA)
            label = f"#{number}  {event.time:.2f}s  {event.score:.1f}"
            cv2.rectangle(frame, (0, 0), (180, 28), (0, 0, 0), -1)
            cv2.putText(frame, label, (6, 20), cv2.FONT_HERSHEY_SIMPLEX, 0.42,
                        (255, 255, 255), 1, cv2.LINE_AA)
            thumbs.append(frame)
    finally:
        capture.release()

    rows = (len(thumbs) + columns - 1) // columns
    canvas = np.zeros((rows * 320, columns * 180, 3), dtype=np.uint8)
    for index, thumb in enumerate(thumbs):
        row, column = divmod(index, columns)
        canvas[row * 320 : (row + 1) * 320, column * 180 : (column + 1) * 180] = thumb
    output.parent.mkdir(parents=True, exist_ok=True)
    cv2.imwrite(str(output), canvas, [cv2.IMWRITE_JPEG_QUALITY, 88])
