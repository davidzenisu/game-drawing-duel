---
share: true
repo:
  repo: game-drawing-duel
  branch: feature/docs
title: boost-balance
category: concept
---
Each week, the boost stars every player gives a day change with how the fights of the week before went, so challengers and heroes stay about even.

This works the following way:
- In the first week, every player gives **3** boost stars a day.
- The balance starts with the week of Monday, 23 November 2026, so servers running when it came in switched between two weeks, not in the middle of one: the weeks before kept 3 boost stars a day, and their first week with it started from 3, changed by the week before's fights.
- Each following week starts from the week before's boost stars and changes them by the heroes' share of the week before's fights (every decided fight counts, also the ones chance picked the fighters for):

| Heroes won | Boost stars |
|---|---|
| 0–20% | −2 ★ |
| 20–40% | −1 ★ |
| 40–60% | ±0 ★ |
| 60–80% | +1 ★ |
| 80–100% | +2 ★ |

- A share exactly on an edge counts towards the smaller change: 40% and 60% change nothing, 20% and 80% change by one.
- It takes at least **7** fights in the week before (one a day); with fewer, the stars stay as they were.
- The stars stack week over week, but never go below **3** or above **6** a day.
- One challenger takes all of a player's stars at most, so a player can still put all of them on one.
- Chance spreads the stars a player didn't give the same way: all of the week's stars count.
- Speed mode has no weeks, so it always has 3 boost stars a day.

Where to see it:
- **Boost challengers**: the star tray shows the week's stars ("2 of 4 left"), without more on the balance. With many stars, they shrink to fit a phone.
- **Week ranking**: last week's **Challengers** start with a short **Boost balance** card: "Boost balance 4 ★ a day", and below "Up from 3 ★ from last week (hero win rate 75%)" ("Down from …", "Same as last week", or "only 5 fights" instead of the win rate when there were too few).
- **Tutorial**: the boost tutorial's last page, "A balance every week", explains the bands, the fights it takes and the limits.
