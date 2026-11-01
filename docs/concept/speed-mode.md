---
share: true
repo:
  repo: game-drawing-duel
  branch: feature/docs
title: speed-mode
category: concept
---

Speed mode is a "one-off" server session of about 17 minutes. It replaces the old test sessions. It follows the same rules as any "generic" server (see [Initial Setup](./initial-setup.md)): 5 to 10 players, and everyone has to join before the admin starts. It then goes through the following phases back-to-back, each on a timer:

- Setup: 5 min
- Day 1: Title (1 min)
- Day 2: Title + Drawing (2 min)
- Day 3: Title + Drawing + Boost (3 min)
- Day 4: Drawing + Boost + Fighters (3 min)
- Day 5: Boost + Fighters (2 min)
- Day 6: Fighters (1 min)
- End: Final ranking

A day ends early once every player has done everything there is to do that day, or has ended their day. The admin can also skip to the next day.

### Setup
- Only two drawings per player, spread out across the different rarities:
	- For 5 players: 5☆, 1☆☆, 2☆☆☆, 2☆☆☆☆
	- For 6 players: 6☆, 2☆☆, 2☆☆☆, 2☆☆☆☆
	- For 7 players: 7☆, 2☆☆, 3☆☆☆, 2☆☆☆☆
	- For 8 players: 8☆, 3☆☆, 3☆☆☆, 2☆☆☆☆
	- For 9 players: 9☆, 3☆☆, 3☆☆☆, 3☆☆☆☆
	- For 10 players: 10☆, 4☆☆, 3☆☆☆, 3☆☆☆☆
- Every player draws the 1☆ (basic) drawing of the next player, and one higher ☆ drawing of the player after that. So everyone is drawn twice.
- Only the 1☆ setup drawing is gained by the player who drew it, not the higher ☆ one. The higher ☆ drawings only go into the gacha pool.
- The setup ends once everyone is done, or after 5 minutes with whatever was drawn by then.

### Days
- Challenger titles are only written on days 1 to 3, so the last days finish the loop: drawing on days 2 to 4, boosting on days 3 to 5, fighting on days 4 to 6.
- For each win: get one pull for each star that the challenger has (speed mode only), plus the challenger's stars as victory stars.
- There is no weekly finale.

Total drawings: 5 per player (25-50 drawings)

### End
After day 6, all of the session's challengers are ranked by their stars. The winner is presented first with its amount of stars. Then every other challenger scrolls by automatically in a smaller display, also showing its amount of stars.

Old speed mode sessions (older than 1 day) are deleted by an admin-only cleanup API.

### Balancing notes
Average player battlers in speed mode:
- enough 1 ☆
- Realistically no more than 1-2x 4 ☆☆☆☆
- 2-3x ☆☆
- 3-4x ☆☆☆

Average stars in a fight: ~8☆ per fight (average of ☆☆ per fighter)
Min stars per fight: 4☆
Max stars per fight: 14☆ (but very unlikely, more around 12 on average)

### Open ideas
- The stronger your opponents are, the stronger the challenger becomes? > Yes, reward better drawings!
- Rather than only a ranking at the end, a massive battle > lowest ranking challenger who won starts?
