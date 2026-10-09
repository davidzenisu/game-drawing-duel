import uuid

from sqlalchemy import func, select

from app.models import Character, Pull, PullGrant, ServerSeat
from tests.helpers import bearer, make_token
from tests.test_pulls import PullTestCase
from tests.test_setup import ADMIN


class UpgradeTests(PullTestCase):
    def setUp(self) -> None:
        super().setUp()
        owned = self.get(f"/servers/{self.code}/collection").json()
        self.by_rarity = {o["character"]["rarity"]: o["character"]["id"] for o in owned}

    def give_copies(self, character_id: str, count: int) -> None:
        """Records `count` more pulls of the character, as if pulled."""
        with self.session_factory() as session:
            seat = session.scalar(select(ServerSeat).where(ServerSeat.position == 0))
            character = session.get(Character, uuid.UUID(character_id))
            pulled = session.scalar(select(func.count()).select_from(Pull))
            for n in range(count):
                grant = PullGrant(seat_id=seat.id, reason=f"test:{pulled + n}")
                session.add(grant)
                session.flush()
                session.add(
                    Pull(
                        seat_id=seat.id,
                        grant_id=grant.id,
                        character_id=character.id,
                        number=pulled + n + 1,
                        rarity=character.rarity,
                    )
                )
            session.commit()

    def unlock(self, character_id: str, element: str | None = None):
        return self.client.post(
            f"/servers/{self.code}/collection/{character_id}/upgrades",
            json={} if element is None else {"element": element},
            headers=bearer(make_token(ADMIN)),
        )

    def test_an_upgrade_costs_a_duplicate(self) -> None:
        basic = self.by_rarity["basic"]
        response = self.unlock(basic)
        self.assertEqual(response.status_code, 409)
        self.assertEqual(
            response.json()["detail"], "You need a duplicate to unlock this"
        )

        self.give_copies(basic, 1)
        response = self.unlock(basic)
        self.assertEqual(response.status_code, 200, response.text)
        owned = response.json()
        self.assertEqual((owned["copies"], owned["upgrades"]), (2, ["shadow"]))
        self.assertEqual(self.unlock(basic).status_code, 409, "the duplicate is spent")

        collection = {
            o["character"]["id"]: o
            for o in self.get(f"/servers/{self.code}/collection").json()
        }
        self.assertEqual(collection[basic]["upgrades"], ["shadow"])

    def test_the_path_ends_with_the_rarity(self) -> None:
        basic = self.by_rarity["basic"]
        self.give_copies(basic, 5)
        self.assertEqual(self.unlock(basic).json()["upgrades"], ["shadow"])
        self.assertEqual(self.unlock(basic).json()["upgrades"], ["shadow", "light"])
        response = self.unlock(basic)
        self.assertEqual(response.status_code, 409)
        self.assertEqual(response.json()["detail"], "Every upgrade is unlocked already")

    def test_the_element_upgrade_needs_a_choice(self) -> None:
        knight = self.by_rarity["adventurer"]
        self.give_copies(knight, 3)
        self.unlock(knight)
        self.unlock(knight)
        response = self.unlock(knight)
        self.assertEqual(response.status_code, 422)
        self.assertEqual(
            response.json()["detail"], "Choose an element for this upgrade"
        )
        self.assertEqual(self.unlock(knight, "lava").status_code, 422)
        owned = self.unlock(knight, "storm").json()
        self.assertEqual(owned["upgrades"], ["shadow", "light", "element"])
        self.assertEqual(owned["element"], "storm")

    def test_only_characters_of_the_server(self) -> None:
        response = self.unlock("00000000-0000-0000-0000-000000000000")
        self.assertEqual(response.status_code, 404)
