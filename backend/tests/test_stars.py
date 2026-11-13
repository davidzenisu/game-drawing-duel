from tests.test_fights import SAM, FightTestCase


class StarTests(FightTestCase):
    """Day 3 of a test session: everyone drew a challenger yesterday."""

    def stars(self, subject: str) -> int:
        return self.get(f"/servers/{self.code}/gacha", subject).json()["stars"]

    def write_prompt(self, subject: str):
        return self.post(
            "today/prompt", subject, {"subject_position": 0, "title": "Sauna Lord"}
        )

    def test_drawing_a_challenger_earns_three_stars(self) -> None:
        self.assertEqual(self.stars(SAM), 3, "yesterday's drawing")

    def test_writing_a_title_earns_three_stars_once_a_day(self) -> None:
        response = self.write_prompt(SAM)
        self.assertEqual(response.status_code, 200, response.text)
        self.assertEqual(self.stars(SAM), 6)
        self.assertEqual(self.write_prompt(SAM).status_code, 409)
        self.assertEqual(self.stars(SAM), 6, "once")
        self.next_day()
        self.write_prompt(SAM)
        self.assertEqual(self.stars(SAM), 9, "and again the next day")
