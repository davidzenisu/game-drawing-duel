"""Draws a stored sketch as SVG, to look at a drawing outside the app.

Mirrors the app's `SketchPainter` (frontend/lib/game/widgets/sketch_canvas.dart):
a 4:5 card, points normalised to it, widths relative to its width, strokes
smoothed with quadratic curves through the midpoints, round caps and joins.
"""

from itertools import pairwise

from app.schemas import SketchData

# The card's size in SVG units; 4:5 like `cardAspectRatio` in the app.
WIDTH = 400
HEIGHT = 500
# The white cardboard the drawings are on.
BACKGROUND = "#ffffff"


def _num(value: float) -> str:
    """Short coordinates: two decimals, no trailing zeros."""
    return f"{value:.2f}".rstrip("0").rstrip(".")


def _color(argb: int) -> tuple[str, float]:
    """`#rrggbb` and the opacity of an ARGB color like 0xFF000000."""
    return f"#{argb & 0xFFFFFF:06x}", ((argb >> 24) & 0xFF) / 255


def render_svg(sketch: SketchData) -> str:
    shapes = []
    for stroke in sketch.strokes:
        color, opacity = _color(stroke.color)
        alpha = "" if opacity == 1 else f' opacity="{_num(opacity)}"'
        width = stroke.width * WIDTH
        points = [
            (stroke.points[i] * WIDTH, stroke.points[i + 1] * HEIGHT)
            for i in range(0, len(stroke.points), 2)
        ]
        if len(points) == 1:
            x, y = points[0]
            shapes.append(
                f'<circle cx="{_num(x)}" cy="{_num(y)}" r="{_num(width / 2)}"'
                f' fill="{color}"{alpha}/>'
            )
            continue
        path = [f"M{_num(points[0][0])} {_num(points[0][1])}"]
        for (x, y), (nx, ny) in pairwise(points[1:]):
            path.append(
                f"Q{_num(x)} {_num(y)} {_num((x + nx) / 2)} {_num((y + ny) / 2)}"
            )
        path.append(f"L{_num(points[-1][0])} {_num(points[-1][1])}")
        shapes.append(
            f'<path d="{" ".join(path)}" stroke="{color}"'
            f' stroke-width="{_num(width)}"{alpha}/>'
        )
    return (
        f'<svg xmlns="http://www.w3.org/2000/svg" width="{WIDTH}" height="{HEIGHT}"'
        f' viewBox="0 0 {WIDTH} {HEIGHT}">'
        f'<rect width="{WIDTH}" height="{HEIGHT}" fill="{BACKGROUND}"/>'
        f'<g fill="none" stroke-linecap="round" stroke-linejoin="round">'
        f"{''.join(shapes)}</g></svg>"
    )
