import uuid

from sqlalchemy import func, select

from app.models import Character, Pull, PullGrant, ServerSeat, Upgrade
from app.rules import UPGRADE_COSTS, UPGRADE_PATHS, Rarity, UpgradeEffect
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

    def test_each_upgrade_costs_more_duplicates(self) -> None:
        basic = self.by_rarity["basic"]
        first, second, third = UPGRADE_COSTS[Rarity.BASIC][:3]
        response = self.unlock(basic)
        self.assertEqual(response.status_code, 409)
        self.assertEqual(
            response.json()["detail"], "You need 1 more duplicate to unlock this"
        )

        self.give_copies(basic, first)
        response = self.unlock(basic)
        self.assertEqual(response.status_code, 200, response.text)
        owned = response.json()
        self.assertEqual((owned["copies"], owned["upgrades"]), (2, ["shadow"]))
        response = self.unlock(basic)
        self.assertEqual(response.status_code, 409, "the duplicate is spent")
        self.assertEqual(
            response.json()["detail"],
            f"You need {second} more duplicates to unlock this",
        )
        self.give_copies(basic, second + 1)
        self.assertEqual(self.unlock(basic).json()["upgrades"], ["shadow", "outline"])
        self.assertEqual(
            self.unlock(basic).json()["detail"],
            f"You need {third - 1} more duplicates to unlock this",
            "the spare duplicate counts",
        )

        collection = {
            o["character"]["id"]: o
            for o in self.get(f"/servers/{self.code}/collection").json()
        }
        self.assertEqual(collection[basic]["upgrades"], ["shadow", "outline"])

    def test_1_and_2_stars_take_about_30_duplicates_over_6_steps_or_more(self) -> None:
        self.assertEqual(UPGRADE_COSTS[Rarity.BASIC], (1, 2, 3, 5, 7, 10))
        for rarity in (Rarity.BASIC, Rarity.ADVENTURER):
            self.assertGreaterEqual(len(UPGRADE_PATHS[rarity]), 6, rarity)
            self.assertAlmostEqual(sum(UPGRADE_COSTS[rarity]), 30, delta=2)

    def test_the_path_ends_with_the_rarity(self) -> None:
        basic = self.by_rarity["basic"]
        self.give_copies(basic, sum(UPGRADE_COSTS[Rarity.BASIC]) + 5)
        for _ in UPGRADE_PATHS[Rarity.BASIC]:
            upgrades = self.unlock(basic).json()["upgrades"]
        self.assertEqual(upgrades, [e.value for e in UPGRADE_PATHS[Rarity.BASIC]])
        response = self.unlock(basic)
        self.assertEqual(response.status_code, 409)
        self.assertEqual(response.json()["detail"], "Every upgrade is unlocked already")

    def test_upgrades_from_a_shorter_path_keep_their_place(self) -> None:
        """Basics used to unlock the light right after the shadow."""
        basic = self.by_rarity["basic"]
        with self.session_factory() as session:
            seat = session.scalar(select(ServerSeat).where(ServerSeat.position == 0))
            for effect in ("shadow", "light"):
                session.add(
                    Upgrade(
                        seat_id=seat.id,
                        character_id=uuid.UUID(basic),
                        effect=effect,
                    )
                )
            session.commit()
        # The shadow and the light cost 1 + 3 now; the outline 2 more.
        self.give_copies(basic, 5)
        self.assertEqual(
            self.unlock(basic).json()["detail"],
            "You need 1 more duplicate to unlock this",
        )
        self.give_copies(basic, 1)
        self.assertEqual(
            self.unlock(basic).json()["upgrades"], ["shadow", "outline", "light"]
        )

    def test_the_element_upgrade_needs_a_choice(self) -> None:
        knight = self.by_rarity["adventurer"]
        path = UPGRADE_PATHS[Rarity.ADVENTURER]
        self.give_copies(knight, sum(UPGRADE_COSTS[Rarity.ADVENTURER]))
        before = path[: path.index(UpgradeEffect.ELEMENT)]
        for _ in before:
            self.unlock(knight)
        response = self.unlock(knight)
        self.assertEqual(response.status_code, 422)
        self.assertEqual(
            response.json()["detail"], "Choose an element for this upgrade"
        )
        self.assertEqual(self.unlock(knight, "lava").status_code, 422)
        owned = self.unlock(knight, "storm").json()
        self.assertEqual(
            owned["upgrades"], [e.value for e in (*before, UpgradeEffect.ELEMENT)]
        )
        self.assertEqual(owned["element"], "storm")

    def test_only_characters_of_the_server(self) -> None:
        response = self.unlock("00000000-0000-0000-0000-000000000000")
        self.assertEqual(response.status_code, 404)
