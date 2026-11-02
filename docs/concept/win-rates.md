---
share: true
repo:
  repo: game-drawing-duel
  branch: feature/docs
title: win-rates
category: concept
---
After each week, there should be win rates that affect if the selected heroes or the challenger get additional ☆ when fighting.

This should work the following way:
- After each week, the win rates for each player should be calculated (only use the fights of the previous week fir calculation):
	- If a hero or challenger with that player name won more than 50% of fights agains a hero or challenger during that week, they should receive **two** extra stars when fighting against them.
	- If a hero or challenger with that player name won more than 75% of fights agains a hero or challenger during that week, they should receive **two** extra stars when fighting against them.

These changes should be shown in a table in a separate item in the main menu and the extra stars should be shown during battles.