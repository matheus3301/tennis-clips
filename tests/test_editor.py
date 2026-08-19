import json
import tempfile
import unittest
from pathlib import Path

from tennis_clips.detector import Event
from tennis_clips.editor import clip_ranges, save_clip_manifest


def event(time: float) -> Event:
    return Event(
        time=time,
        score=1.0,
        amplitude=1.0,
        mid_energy_ratio=0.2,
        high_energy_ratio=0.1,
        motion_ratio=0.2,
    )


class ClipRangesTest(unittest.TestCase):
    def test_merges_overlapping_events(self) -> None:
        ranges = clip_ranges([event(3.0), event(3.8)], pre_roll=0.6, post_roll=0.8)
        self.assertEqual(ranges, [(2.4, 4.6)])

    def test_keeps_distant_events_separate_and_sorted(self) -> None:
        ranges = clip_ranges([event(8.0), event(2.0)], pre_roll=0.5, post_roll=0.5)
        self.assertEqual(ranges, [(1.5, 2.5), (7.5, 8.5)])

    def test_does_not_create_negative_start(self) -> None:
        ranges = clip_ranges([event(0.2)], pre_roll=0.6, post_roll=0.8)
        self.assertEqual(ranges, [(0.0, 1.0)])

    def test_manifest_is_ready_for_human_review(self) -> None:
        events = [event(2.0), event(8.0)]
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "clips.json"
            save_clip_manifest(path, [(1.0, 4.0), (7.0, 10.0)], events, "rallies")
            payload = json.loads(path.read_text(encoding="utf-8"))
        self.assertEqual(payload["clip_count"], 2)
        self.assertEqual(payload["clips"][0]["id"], "rallies-001")
        self.assertEqual(payload["clips"][0]["review_status"], "unreviewed")
        self.assertEqual(payload["clips"][0]["event_times"], [2.0])


if __name__ == "__main__":
    unittest.main()
