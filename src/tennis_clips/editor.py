from __future__ import annotations

import subprocess
from pathlib import Path

from tennis_clips.detector import Event, require_media_tools


def clip_ranges(
    events: list[Event],
    pre_roll: float,
    post_roll: float,
    merge_gap: float = 0.10,
) -> list[tuple[float, float]]:
    ranges: list[tuple[float, float]] = []
    for event in sorted(events, key=lambda item: item.time):
        start = max(0.0, event.time - pre_roll)
        end = event.time + post_roll
        if ranges and start <= ranges[-1][1] + merge_gap:
            ranges[-1] = (ranges[-1][0], max(ranges[-1][1], end))
        else:
            ranges.append((start, end))
    return ranges


def render_compilation(
    video: Path,
    events: list[Event],
    output: Path,
    work_dir: Path,
    pre_roll: float = 0.65,
    post_roll: float = 0.80,
    height: int = 1280,
) -> list[tuple[float, float]]:
    require_media_tools()
    if not events:
        raise ValueError("Nenhuma batida foi detectada; o video final nao pode ser criado.")
    output.parent.mkdir(parents=True, exist_ok=True)
    segments_dir = work_dir / "segments"
    segments_dir.mkdir(parents=True, exist_ok=True)
    ranges = clip_ranges(events, pre_roll, post_roll)
    segment_paths: list[Path] = []

    print(f"Renderizando {len(ranges)} cortes a partir de {len(events)} batidas...")
    for index, (start, end) in enumerate(ranges, start=1):
        duration = end - start
        segment = segments_dir / f"segment-{index:04d}.mp4"
        segment_paths.append(segment)
        fade_out = max(0.0, duration - 0.06)
        command = [
            "ffmpeg", "-hide_banner", "-loglevel", "error", "-y",
            "-ss", f"{start:.3f}", "-i", str(video), "-t", f"{duration:.3f}",
            "-map", "0:v:0", "-map", "0:a:0",
            "-vf",
            f"scale=-2:{height},setsar=1,fade=t=in:st=0:d=0.06,"
            f"fade=t=out:st={fade_out:.3f}:d=0.06",
            "-af", f"afade=t=in:st=0:d=0.04,afade=t=out:st={fade_out:.3f}:d=0.04",
            "-c:v", "libx264", "-preset", "veryfast", "-crf", "20",
            "-c:a", "aac", "-b:a", "160k", "-metadata:s:v:0", "rotate=0",
            str(segment),
        ]
        subprocess.run(command, check=True)
        if index % 10 == 0 or index == len(ranges):
            print(f"  {index}/{len(ranges)} cortes renderizados")

    concat_file = segments_dir / "concat.txt"
    concat_file.write_text(
        "".join(f"file '{path.name}'\n" for path in segment_paths),
        encoding="utf-8",
    )
    command = [
        "ffmpeg", "-hide_banner", "-loglevel", "error", "-y",
        "-f", "concat", "-safe", "0", "-i", str(concat_file),
        "-c", "copy", "-movflags", "+faststart", str(output),
    ]
    subprocess.run(command, check=True)
    return ranges
