from __future__ import annotations

import argparse
from pathlib import Path

from tennis_clips.detector import (
    DetectorConfig,
    create_review_sheet,
    detect_events,
    load_events,
    save_analysis,
)
from tennis_clips.editor import render_compilation


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
    make.add_argument("--cache", type=Path, default=Path(".tennis-clips-cache"))
    make.add_argument("--reuse-events", action="store_true")
    make.add_argument("--pre-roll", type=float, default=0.65)
    make.add_argument("--post-roll", type=float, default=0.80)
    make.add_argument("--height", type=int, default=1280)
    make.add_argument("--amplitude-percentile", type=float, default=98.5)
    make.add_argument("--min-motion", type=float, default=0.08)
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

    if args.reuse_events:
        if not args.events.is_file():
            raise SystemExit(f"Arquivo de eventos nao encontrado: {args.events}")
        events = load_events(args.events)
    else:
        events = _analyze(args)
    ranges = render_compilation(
        args.video.expanduser().resolve(), events, args.output.resolve(), args.cache.resolve(),
        pre_roll=args.pre_roll, post_roll=args.post_roll, height=args.height,
    )
    duration = sum(end - start for start, end in ranges)
    print(f"Video final: {args.output.resolve()}")
    print(f"Duracao aproximada: {duration:.1f}s")


if __name__ == "__main__":
    main()
