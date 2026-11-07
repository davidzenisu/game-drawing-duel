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
	- If a player's heroes and challengers won more than **50%** of their meetings with another player's, they get **one** extra ☆ against that player this week.
	- If they won more than **75%**, they get **two** extra ☆ instead.
- In a fight, each hero gets its extra stars against the challenger's player, and the challenger gets its extra stars once for each hero whose player it beat most of the time. Ties still go to the challenger.
- The extra stars only decide the fight: victory stars and pulls still come from the challenger's own and boost stars.
- Speed mode has no weeks, so it has no win rates.

Where to see them:
- **Win rates** (in the heroes menu): every player as a card with their basic drawing, name and a "Show win rates" button. It opens that player's matchups side by side: both players' basic drawings and names, their extra ☆ and how many fights they won. Only matchups that change stars on either side are shown.
- **Picking fighters**: every hero shows the stars its player's win rate changes against today's challenger: "+N ★" in green when it gets them, "−N ★" in red when the challenger gets them against it. They show in the roster, on the stage and summed up below it.
- **Battles**: the fight reveal adds each side's extra stars to its stars and shows them as "+N from win rates".
