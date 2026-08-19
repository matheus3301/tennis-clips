from __future__ import annotations

import argparse
import json
from pathlib import Path

from tennis_clips.detector import (
    DetectorConfig,
    create_review_sheet,
    detect_events,
    load_events,
    save_analysis,
)
from tennis_clips.analytics import (
    analyze_shots,
    create_analytics_review_sheet,
    save_analytics,
)
from tennis_clips.editor import render_compilation, save_clip_manifest
from tennis_clips.overlay import render_analytics_overlay


def _parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="tennis-clips",
        description="Detecta suas batidas de tenis e monta um video curto automaticamente.",
    )
    subparsers = parser.add_subparsers(dest="command", required=True)

    analyze = subparsers.add_parser("analyze", help="Detecta batidas e gera material de revisao.")
    analyze.add_argument("video", type=Path)
    analyze.add_argument("--events", type=Path, default=Path("output/events.json"))
    analyze.add_argument("--review", type=Path, default=Path("output/review.jpg"))
    analyze.add_argument("--cache", type=Path, default=Path(".tennis-clips-cache"))
    analyze.add_argument("--amplitude-percentile", type=float, default=98.5)
    analyze.add_argument("--min-motion", type=float, default=0.08)

    make = subparsers.add_parser("make", help="Analisa e cria a compilacao final.")
    make.add_argument("video", type=Path)
    make.add_argument("--output", type=Path, default=Path("output/batidas.mp4"))
    make.add_argument("--events", type=Path, default=Path("output/events.json"))
    make.add_argument("--review", type=Path, default=Path("output/review.jpg"))
    make.add_argument("--manifest", type=Path, default=Path("output/clips.json"))
    make.add_argument("--cache", type=Path, default=Path(".tennis-clips-cache"))
    make.add_argument("--reuse-events", action="store_true")
    make.add_argument("--mode", choices=("hits", "rallies"), default="hits")
    make.add_argument("--pre-roll", type=float)
    make.add_argument("--post-roll", type=float)
    make.add_argument("--merge-gap", type=float)
    make.add_argument("--height", type=int, default=1280)
    make.add_argument("--amplitude-percentile", type=float, default=98.5)
    make.add_argument("--min-motion", type=float, default=0.08)

    analytics = subparsers.add_parser(
        "analytics", help="Classifica golpes e adiciona metricas ao video contextual."
    )
    analytics.add_argument("video", type=Path, help="Video original usado na deteccao.")
    analytics.add_argument("--base-video", type=Path, default=Path("output/jogadas-v1.mp4"))
    analytics.add_argument("--events", type=Path, default=Path("output/events.json"))
    analytics.add_argument("--clips", type=Path, default=Path("output/jogadas-v1.json"))
    analytics.add_argument("--output", type=Path, default=Path("output/jogadas-v3-analytics.mp4"))
    analytics.add_argument("--analytics-output", type=Path,
                           default=Path("output/analytics-v3.json"))
    analytics.add_argument("--review", type=Path,
                           default=Path("output/analytics-v3-review.jpg"))
    analytics.add_argument("--model", type=Path,
                           default=Path(".tennis-clips-models/pose_landmarker_full.task"))
    analytics.add_argument("--handedness", choices=("right", "left"), default="right")
    analytics.add_argument("--no-overlay", action="store_true")
    return parser


def _config(args: argparse.Namespace) -> DetectorConfig:
    return DetectorConfig(
        amplitude_percentile=args.amplitude_percentile,
        min_motion_ratio=args.min_motion,
    )


def _analyze(args: argparse.Namespace) -> list:
    video = args.video.expanduser().resolve()
    if not video.is_file():
        raise SystemExit(f"Video nao encontrado: {video}")
    events, metadata = detect_events(video, args.cache.resolve(), _config(args))
    save_analysis(args.events.resolve(), events, metadata)
    create_review_sheet(video, events, args.review.resolve())
    print(f"{len(events)} batidas aceitas")
    print(f"Eventos: {args.events.resolve()}")
    print(f"Revisao: {args.review.resolve()}")
    return events


def main() -> None:
    parser = _parser()
    args = parser.parse_args()
    if args.command == "analyze":
        _analyze(args)
        return

    if args.command == "analytics":
        video = args.video.expanduser().resolve()
        required = (video, args.events.resolve(), args.clips.resolve())
        missing = [str(path) for path in required if not path.is_file()]
        if missing:
            raise SystemExit(f"Arquivos nao encontrados: {', '.join(missing)}")
        events = load_events(args.events.resolve())
        payload = analyze_shots(
            video, events, args.clips.resolve(), args.model.resolve(), args.handedness,
        )
        save_analytics(args.analytics_output.resolve(), payload)
        create_analytics_review_sheet(video, payload, args.review.resolve())
        if not args.no_overlay:
            base_video = args.base_video.resolve()
            if not base_video.is_file():
                raise SystemExit(f"Video contextual nao encontrado: {base_video}")
            render_analytics_overlay(base_video, args.output.resolve(), payload)
            print(f"Video analitico: {args.output.resolve()}")
        print(f"Metricas: {args.analytics_output.resolve()}")
        print(f"Revisao: {args.review.resolve()}")
        print(json.dumps(payload["session"], ensure_ascii=False, indent=2))
        return

    if args.reuse_events:
        if not args.events.is_file():
            raise SystemExit(f"Arquivo de eventos nao encontrado: {args.events}")
        events = load_events(args.events)
    else:
        events = _analyze(args)
    if args.mode == "rallies":
        pre_roll = 1.20 if args.pre_roll is None else args.pre_roll
        post_roll = 2.60 if args.post_roll is None else args.post_roll
        merge_gap = 0.35 if args.merge_gap is None else args.merge_gap
    else:
        pre_roll = 0.65 if args.pre_roll is None else args.pre_roll
        post_roll = 0.80 if args.post_roll is None else args.post_roll
        merge_gap = 0.10 if args.merge_gap is None else args.merge_gap

    ranges = render_compilation(
        args.video.expanduser().resolve(), events, args.output.resolve(), args.cache.resolve(),
        pre_roll=pre_roll, post_roll=post_roll, merge_gap=merge_gap, height=args.height,
    )
    save_clip_manifest(args.manifest.resolve(), ranges, events, args.mode)
    duration = sum(end - start for start, end in ranges)
    print(f"Video final: {args.output.resolve()}")
    print(f"Manifesto: {args.manifest.resolve()}")
    print(f"Duracao aproximada: {duration:.1f}s")


if __name__ == "__main__":
    main()
