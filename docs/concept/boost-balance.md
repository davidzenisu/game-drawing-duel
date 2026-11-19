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
- **Boost challengers**: the star tray shows the week's stars, and below the count why: "Heroes won 72% last week: +1 ★ to give a day this week, 4 in all." (or that they stay the same, that there were too few fights, or that they're already at the most or the fewest). With many stars, the tray's stars shrink to fit a phone.
- **Week ranking**: last week's **Challengers** start with a **Boost balance** card: how many of last week's fights the challengers and the heroes won, with their shares, and the boost stars to give a day this week, with the change from the week before ("4 a day (+1 from 3)"), above the bands it goes by.
