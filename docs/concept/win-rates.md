---
share: true
repo:
  repo: game-drawing-duel
  branch: feature/docs
title: win-rates
category: concept
---
After each week, there are win rates that decide whether the selected heroes or the challenger get extra ☆ when fighting.

This works the following way:
- After each week, the win rates between every pair of players are calculated, only from the fights of the previous week:
	- A hero or challenger counts for the player it shows.
	- In a fight, every hero meets the challenger once; the side that won the fight wins that meeting. Heroes showing the challenger's own player don't count.
	- It takes at least **3** meetings between two players for a win rate to count.
	- If a player's heroes and challengers won at least **80%** of their meetings with another player's, they get **one** extra ☆ against that player this week. Exactly 80% counts, e.g. 4 of 5. Anything below gives no extra ☆.
	- This band holds from Monday, 23 November 2026 (since 0.27.0; that week started with one extra ☆ for more than 60% and two for more than 80%, like the [Boost Balance](./boost-balance.md)'s bands); the weeks before gave one extra ☆ for 50% and two for 75%. The win rates screen explains the band of its week.
	- Losing gives no negative stars: a player who won 20% or less against another is the one the other player's bonus counts against.
- The boost stars of the following week are balanced with bands of their own (see [Boost Balance](./boost-balance.md)).
- In a fight, each hero gets its extra stars against the challenger's player, and the challenger gets its extra stars once for each hero whose player it beat most of the time. Ties still go to the challenger.
- The extra stars only decide the fight: the stars and pulls a win earns still come from the challenger's own and boost stars.
- Speed mode has no weeks, so it has no win rates.

Where to see them:
- **Win rates** (in the heroes menu): every player as a card with their basic drawing, name and a "Show win rates" button. It opens that player's matchups side by side: both players' basic drawings and names, their extra ☆ and how many fights they won. Only matchups that change stars on either side are shown. It opens once the first week is over (on the first Monday), so it doesn't give away everyone's basic drawing before players met them in fights and pulls. The win rates are kept on the device for the week they apply to, so they open without asking the server again; the refresh button in the top right asks anyway.
- **Picking fighters**: every hero shows the stars its player's win rate changes against today's challenger: "+N ★" in green when it gets them, "−N ★" in red when the challenger gets them against it. They show in the roster, on the stage and summed up below it.
- **Battles**: the fight reveal adds each side's extra stars to its stars and shows them as "+N from win rates".
