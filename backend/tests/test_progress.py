from app.rules import UPGRADE_COSTS, UPGRADE_PATHS, Rarity
from tests import test_upgrades
from tests.helpers import bearer, make_token
from tests.test_pulls import PullTestCase
from tests.test_setup import ADMIN


class ProgressTests(PullTestCase):
    give_copies = test_upgrades.UpgradeTests.give_copies
    unlock = test_upgrades.UpgradeTests.unlock

    def progress(self, position: int, token: str | None = None):
        return self.client.get(
            f"/servers/{self.code}/seats/{position}/progress",
            headers=bearer(token or self.token),
        )

    def setUp(self) -> None:
        super().setUp()
        self.token = make_token(ADMIN)

    def progress_of(self, position: int) -> dict[str, dict]:
        response = self.progress(position)
        self.assertEqual(response.status_code, 200, response.text)
        body = response.json()
        self.assertEqual(body["player_position"], position)
        return {r.pop("rarity"): r for r in body["rarities"]}

    def test_counts_the_pool_and_your_collection_per_rarity(self) -> None:
        pool = self.get(f"/servers/{self.code}/pool").json()
        owned = self.get(f"/servers/{self.code}/collection").json()
        progress = self.progress_of(0)
        self.assertEqual(list(progress), [r.value for r in Rarity])
        for rarity in Rarity:
            in_pool = sum(c["rarity"] == rarity.value for c in pool)
            mine = sum(o["character"]["rarity"] == rarity.value for o in owned)
            steps = len(UPGRADE_PATHS[rarity])
            self.assertEqual(
                progress[rarity.value],
                {
                    "in_pool": in_pool,
                    "collected": mine,
                    "owned": mine,
                    "maxed": 0,
                    "unlocked_steps": 0,
                    "steps": mine * steps,
                    "duplicates_to_max": mine * sum(UPGRADE_COSTS[rarity]),
                    "spare_duplicates": 0,
                },
                rarity,
            )

    def test_counts_upgrades_and_duplicates(self) -> None:
        owned = self.get(f"/servers/{self.code}/collection").json()
        basic = next(
            o["character"]["id"] for o in owned if o["character"]["rarity"] == "basic"
        )
        first, second = UPGRADE_COSTS[Rarity.BASIC][:2]
        self.give_copies(basic, first + second + 1)
        self.assertEqual(self.unlock(basic).status_code, 200)
        progress = self.progress_of(0)["basic"]
        self.assertEqual(progress["unlocked_steps"], 1)
        # One duplicate spent on the first upgrade, the rest spare.
        self.assertEqual(progress["spare_duplicates"], second + 1)
        self.assertEqual(
            progress["duplicates_to_max"],
            sum(UPGRADE_COSTS[Rarity.BASIC][1:]) - second - 1,
        )

    def test_shows_other_players_progress(self) -> None:
        # Nobody else pulled or drew in a session played alone.
        progress = self.progress_of(1)
        self.assertTrue(any(p["in_pool"] for p in progress.values()))
        for p in progress.values():
            self.assertEqual((p["collected"], p["owned"], p["steps"]), (0, 0, 0))

    def test_an_unknown_seat_is_not_found(self) -> None:
        self.assertEqual(self.progress(99).status_code, 404)

    def test_only_players_of_the_server_see_it(self) -> None:
        response = self.progress(0, make_token("someone-else"))
        self.assertEqual(response.status_code, 403)
