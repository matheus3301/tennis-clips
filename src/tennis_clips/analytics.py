from __future__ import annotations

import json
import math
import urllib.request
from dataclasses import asdict, dataclass
from pathlib import Path
from typing import Any

import cv2
import numpy as np

from tennis_clips.detector import Event


POSE_MODEL_URL = (
    "https://storage.googleapis.com/mediapipe-models/pose_landmarker/"
    "pose_landmarker_full/float16/latest/pose_landmarker_full.task"
)
POSE_OFFSETS = (-0.45, -0.30, -0.15, 0.0, 0.15, 0.30, 0.45)


@dataclass(frozen=True)
class PoseSample:
    offset: float
    arm_quality: float
    wrist_x: float
    wrist_y: float
    shoulder_y: float
    hip_x: float
    hip_y: float
    foot_y: float
    body_scale: float
    wrist_above_head: bool


@dataclass(frozen=True)
class ShotMetric:
    time: float
    output_time: float
    clip_id: str
    clip_index: int
    rally_shot_number: int
    shot_type: str
    shot_type_confidence: float
    pose_confidence: float
    swing_score: float
    response_detected: bool
    player_position: list[float] | None


def ensure_pose_model(path: Path) -> Path:
    if path.is_file():
        return path
    path.parent.mkdir(parents=True, exist_ok=True)
    print("Baixando o modelo de pose do MediaPipe (aprox. 9 MB)...")
    urllib.request.urlretrieve(POSE_MODEL_URL, path)
    return path


def _visible(point: Any) -> float:
    return float(point.visibility or 0.0)


def _pick_player_pose(poses: list[list[Any]]) -> list[Any] | None:
    """Select the closest/largest person without depending on clothing color."""
    best_pose = None
    best_score = -1.0
    for pose in poses:
        visible = [point for point in pose if _visible(point) > 0.25]
        if len(visible) < 12:
            continue
        xs = [point.x for point in visible]
        ys = [point.y for point in visible]
        area = (max(xs) - min(xs)) * (max(ys) - min(ys))
        foot_y = (pose[27].y + pose[28].y) / 2
        visibility = float(np.mean([_visible(point) for point in visible]))
        score = area + 0.10 * foot_y + 0.02 * visibility
        if score > best_score:
            best_score = score
            best_pose = pose
    return best_pose


def _pose_sample(pose: list[Any], offset: float, handedness: str) -> PoseSample:
    dominant = 16 if handedness == "right" else 15
    elbow = 14 if handedness == "right" else 13
    shoulder = 12 if handedness == "right" else 11
    shoulder_center = np.array([
        (pose[11].x + pose[12].x) / 2,
        (pose[11].y + pose[12].y) / 2,
    ])
    hip_center = np.array([
        (pose[23].x + pose[24].x) / 2,
        (pose[23].y + pose[24].y) / 2,
    ])
    shoulder_width = float(np.linalg.norm(np.array([pose[11].x, pose[11].y]) -
                                          np.array([pose[12].x, pose[12].y])))
    torso_height = float(np.linalg.norm(shoulder_center - hip_center))
    body_scale = max(shoulder_width, torso_height, 0.03)
    arm_quality = min(_visible(pose[shoulder]), _visible(pose[elbow]), _visible(pose[dominant]))
    wrist_above_head = (
        _visible(pose[dominant]) > 0.40
        and _visible(pose[0]) > 0.40
        and pose[dominant].y < pose[0].y + 0.02
    )
    return PoseSample(
        offset=offset,
        arm_quality=arm_quality,
        wrist_x=float(pose[dominant].x),
        wrist_y=float(pose[dominant].y),
        shoulder_y=float(shoulder_center[1]),
        hip_x=float(hip_center[0]),
        hip_y=float(hip_center[1]),
        foot_y=float((pose[27].y + pose[28].y) / 2),
        body_scale=body_scale,
        wrist_above_head=wrist_above_head,
    )


def classify_swing(
    samples: list[PoseSample],
    handedness: str,
    previous_gap: float,
) -> tuple[str, float, float, float, list[float] | None]:
    good = [sample for sample in samples if sample.arm_quality > 0.22]
    if not good:
        return "unknown", 0.0, 0.0, 0.0, None

    pre = max((sample for sample in good if sample.offset < -0.05),
              key=lambda sample: sample.arm_quality, default=None)
    post = max((sample for sample in good if sample.offset > 0.05),
               key=lambda sample: sample.arm_quality, default=None)
    near = max(good, key=lambda sample: sample.arm_quality - 0.30 * abs(sample.offset))
    direction = 0.0
    if pre and post:
        scale = (pre.body_scale + post.body_scale) / 2
        direction = (post.wrist_x - pre.wrist_x) / scale
    contact_side = (near.wrist_x - near.hip_x) / near.body_scale
    swing_score = 0.75 * direction + 0.25 * contact_side
    if handedness == "left":
        swing_score *= -1

    pose_confidence = float(np.mean([sample.arm_quality for sample in good]))
    vertical_reach = max(
        (sample.shoulder_y - sample.wrist_y) / sample.body_scale
        for sample in good
        if abs(sample.offset) <= 0.15
    ) if any(abs(sample.offset) <= 0.15 for sample in good) else -9.0
    overhead_frames = sum(sample.wrist_above_head for sample in good if sample.offset <= 0.15)
    if vertical_reach > 1.10 and overhead_frames >= 1:
        label = "serve" if previous_gap > 4.5 else "smash"
        confidence = min(0.90, 0.45 + 0.18 * min(vertical_reach, 2.0))
    elif abs(swing_score) >= 0.18:
        label = "forehand" if swing_score > 0 else "backhand"
        confidence = min(0.92, 0.44 + 0.20 * min(abs(swing_score), 2.0))
    else:
        label = "unknown"
        confidence = min(0.45, 0.25 + 0.15 * abs(swing_score))
    confidence *= 0.65 + 0.35 * pose_confidence
    position = [round(near.hip_x, 4), round(near.hip_y, 4)]
    return label, float(confidence), pose_confidence, float(swing_score), position


def _clips_with_output_times(path: Path) -> list[dict[str, Any]]:
    payload = json.loads(path.read_text(encoding="utf-8"))
    clips = payload["clips"]
    cursor = 0.0
    for clip in clips:
        clip.setdefault("output_start", round(cursor, 3))
        cursor = float(clip["output_start"]) + float(clip["duration"])
    return clips


def _clip_for_event(clips: list[dict[str, Any]], time_seconds: float) -> tuple[int, dict[str, Any]]:
    for index, clip in enumerate(clips, start=1):
        if float(clip["start"]) <= time_seconds <= float(clip["end"]):
            return index, clip
    raise ValueError(f"Evento fora dos clipes contextuais: {time_seconds:.3f}s")


def analyze_shots(
    video: Path,
    events: list[Event],
    clips_path: Path,
    model_path: Path,
    handedness: str = "right",
) -> dict[str, Any]:
    import mediapipe as mp
    from mediapipe.tasks import python
    from mediapipe.tasks.python import vision

    model_path = ensure_pose_model(model_path)
    clips = _clips_with_output_times(clips_path)
    event_groups: dict[str, list[float]] = {clip["id"]: [] for clip in clips}
    for event in events:
        _, clip = _clip_for_event(clips, event.time)
        event_groups[clip["id"]].append(event.time)

    capture = cv2.VideoCapture(str(video))
    capture.set(cv2.CAP_PROP_ORIENTATION_AUTO, 1)
    if not capture.isOpened():
        raise RuntimeError(f"Nao foi possivel abrir o video: {video}")
    options = vision.PoseLandmarkerOptions(
        base_options=python.BaseOptions(model_asset_path=str(model_path)),
        running_mode=vision.RunningMode.IMAGE,
        num_poses=4,
        min_pose_detection_confidence=0.20,
        min_pose_presence_confidence=0.20,
    )
    shots: list[ShotMetric] = []
    previous_time = -math.inf
    print(f"Analisando pose em {len(events)} golpes...")
    try:
        with vision.PoseLandmarker.create_from_options(options) as landmarker:
            for number, event in enumerate(events, start=1):
                samples: list[PoseSample] = []
                for offset in POSE_OFFSETS:
                    capture.set(cv2.CAP_PROP_POS_MSEC, max(0.0, event.time + offset) * 1_000)
                    ok, frame = capture.read()
                    if not ok:
                        continue
                    scale = 540 / frame.shape[1]
                    resized = cv2.resize(frame, (540, round(frame.shape[0] * scale)),
                                         interpolation=cv2.INTER_AREA)
                    rgb = cv2.cvtColor(resized, cv2.COLOR_BGR2RGB)
                    image = mp.Image(image_format=mp.ImageFormat.SRGB, data=rgb)
                    result = landmarker.detect(image)
                    pose = _pick_player_pose(result.pose_landmarks)
                    if pose is not None:
                        samples.append(_pose_sample(pose, offset, handedness))

                label, confidence, pose_confidence, swing_score, position = classify_swing(
                    samples, handedness, event.time - previous_time,
                )
                clip_index, clip = _clip_for_event(clips, event.time)
                group = sorted(event_groups[clip["id"]])
                shot_number = group.index(event.time) + 1
                response_detected = shot_number < len(group)
                output_time = float(clip["output_start"]) + event.time - float(clip["start"])
                shots.append(ShotMetric(
                    time=event.time,
                    output_time=output_time,
                    clip_id=clip["id"],
                    clip_index=clip_index,
                    rally_shot_number=shot_number,
                    shot_type=label,
                    shot_type_confidence=confidence,
                    pose_confidence=pose_confidence,
                    swing_score=swing_score,
                    response_detected=response_detected,
                    player_position=position,
                ))
                previous_time = event.time
                if number % 10 == 0 or number == len(events):
                    print(f"  {number}/{len(events)} golpes analisados")
    finally:
        capture.release()

    counts = {name: sum(shot.shot_type == name for shot in shots)
              for name in ("forehand", "backhand", "serve", "volley", "smash", "unknown")}
    intervals = []
    for clip in clips:
        times = sorted(event_groups[clip["id"]])
        intervals.extend(b - a for a, b in zip(times, times[1:]))
    rhythm_consistency = None
    if len(intervals) >= 2 and np.mean(intervals) > 0:
        rhythm_consistency = float(max(0.0, 1.0 - np.std(intervals) / np.mean(intervals)))
    movement_index = 0.0
    for clip in clips:
        positions = [shot.player_position for shot in shots
                     if shot.clip_id == clip["id"] and shot.player_position]
        movement_index += sum(math.dist(a, b) for a, b in zip(positions, positions[1:]))

    first_third = events[: max(1, len(events) // 3)]
    last_third = events[-max(1, len(events) // 3):]
    early_motion = float(np.median([event.motion_ratio for event in first_third]))
    late_motion = float(np.median([event.motion_ratio for event in last_third]))
    fatigue_ratio = late_motion / max(early_motion, 1e-9)
    fatigue_signal = "stable"
    if fatigue_ratio < 0.85:
        fatigue_signal = "possible_decline"
    elif fatigue_ratio > 1.15:
        fatigue_signal = "increased_intensity"

    return {
        "version": "0.3.0",
        "input": str(video),
        "handedness": handedness,
        "metric_notes": {
            "response_detected": "Inferida quando existe outra batida no mesmo clipe contextual.",
            "movement_index": "Deslocamento normalizado entre poses; nao representa metros.",
            "fatigue_signal": "Proxy experimental baseado em movimento, nao avaliacao fisiologica.",
        },
        "session": {
            "detected_shots": len(shots),
            "rallies": len(clips),
            "shot_counts": counts,
            "classification_rate": float(1.0 - counts["unknown"] / max(1, len(shots))),
            "response_rate": float(np.mean([shot.response_detected for shot in shots])),
            "rhythm_consistency": rhythm_consistency,
            "movement_index": movement_index,
            "fatigue_signal": fatigue_signal,
            "fatigue_motion_ratio": fatigue_ratio,
        },
        "clips": clips,
        "shots": [asdict(shot) for shot in shots],
    }


def save_analytics(path: Path, payload: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(payload, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def create_analytics_review_sheet(video: Path, payload: dict[str, Any], output: Path) -> None:
    capture = cv2.VideoCapture(str(video))
    capture.set(cv2.CAP_PROP_ORIENTATION_AUTO, 1)
    thumbs = []
    try:
        for shot in payload["shots"]:
            capture.set(cv2.CAP_PROP_POS_MSEC, float(shot["time"]) * 1_000)
            ok, frame = capture.read()
            if not ok:
                continue
            thumb = cv2.resize(frame, (180, 320), interpolation=cv2.INTER_AREA)
            label = f"{shot['shot_type'].upper()} {shot['shot_type_confidence']:.0%}"
            cv2.rectangle(thumb, (0, 0), (180, 30), (0, 0, 0), -1)
            cv2.putText(thumb, label, (6, 21), cv2.FONT_HERSHEY_SIMPLEX, 0.45,
                        (255, 255, 255), 1, cv2.LINE_AA)
            thumbs.append(thumb)
    finally:
        capture.release()
    columns = 6
    rows = math.ceil(len(thumbs) / columns)
    canvas = np.zeros((rows * 320, columns * 180, 3), dtype=np.uint8)
    for index, thumb in enumerate(thumbs):
        row, column = divmod(index, columns)
        canvas[row * 320:(row + 1) * 320, column * 180:(column + 1) * 180] = thumb
    output.parent.mkdir(parents=True, exist_ok=True)
    cv2.imwrite(str(output), canvas, [cv2.IMWRITE_JPEG_QUALITY, 88])
