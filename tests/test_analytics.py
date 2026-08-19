import unittest

from tennis_clips.analytics import PoseSample, classify_swing


def sample(offset: float, wrist_x: float) -> PoseSample:
    return PoseSample(
        offset=offset,
        arm_quality=0.9,
        wrist_x=wrist_x,
        wrist_y=0.55,
        shoulder_y=0.50,
        hip_x=0.50,
        hip_y=0.65,
        foot_y=0.80,
        body_scale=0.20,
        wrist_above_head=False,
    )


class SwingClassificationTest(unittest.TestCase):
    def test_right_handed_positive_swing_is_forehand(self) -> None:
        result = classify_swing([sample(-0.2, 0.35), sample(0.2, 0.65)], "right", 2.0)
        self.assertEqual(result[0], "forehand")

    def test_right_handed_negative_swing_is_backhand(self) -> None:
        result = classify_swing([sample(-0.2, 0.65), sample(0.2, 0.35)], "right", 2.0)
        self.assertEqual(result[0], "backhand")

    def test_left_handed_direction_is_inverted(self) -> None:
        result = classify_swing([sample(-0.2, 0.35), sample(0.2, 0.65)], "left", 2.0)
        self.assertEqual(result[0], "backhand")

    def test_missing_pose_remains_unknown(self) -> None:
        result = classify_swing([], "right", 2.0)
        self.assertEqual(result[0], "unknown")


if __name__ == "__main__":
    unittest.main()
