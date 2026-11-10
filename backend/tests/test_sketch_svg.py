import unittest

from app.schemas import SketchData
from app.sketch_svg import render_svg


def _svg(*strokes: dict) -> str:
    return render_svg(SketchData.model_validate({"strokes": list(strokes)}))


class SketchSvgTests(unittest.TestCase):
    def test_strokes_are_smoothed_through_the_midpoints(self) -> None:
        svg = _svg(
            {"color": 0xFF000000, "width": 0.01, "points": [0, 0, 0.5, 0.2, 1, 1]}
        )
        self.assertIn('d="M0 0 Q200 100 300 300 L400 500"', svg)
        self.assertIn('stroke-linecap="round" stroke-linejoin="round"', svg)

    def test_a_single_point_is_a_dot(self) -> None:
        svg = _svg({"color": 0xFF112233, "width": 0.02, "points": [0.5, 0.5]})
        self.assertIn('<circle cx="200" cy="250" r="4" fill="#112233"/>', svg)

    def test_see_through_colors_keep_their_opacity(self) -> None:
        svg = _svg({"color": 0x80FF0000, "width": 0.01, "points": [0, 0, 1, 1]})
        self.assertIn('stroke="#ff0000" stroke-width="4" opacity="0.5"', svg)
