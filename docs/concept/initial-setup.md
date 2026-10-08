---
share: true
repo:
  repo: game-drawing-duel
  branch: feature/docs
title: initial-setup
category: concept
---
When a server is created, the creator can prepopulate their own and all other player's names.

They can then share a generated server code with friends to join.

Any player who joins needs to do 3-6 drawings and titles for other players. 

The following prompts should be the default prompts:
- 1 star: basic
- 1 star (second): alter (based on the first)
- 2 star: Knight
- 2 start (second): Mage
- 2 star (third): Rogue
- 3 star: A legend

The "basic" and "alter" shouldn't need additional prompting, the alter should be drawn after the original has been created.

All can be redrawn but with a different time limit

- basics (normal & alter, 1 star): 30 seconds
- adventurers (2 stars): 1 minute
- heroes (3 stars): 2 minutes
- legends (4 stars): unlimited


| **Player** count | ☆                 | ☆☆      | ☆☆☆ | ☆☆☆☆ | Total |
| ---------------- | ----------------- | ------- | --- | ---- | ----- |
| 5                | 10 (basic +alter) | 15 (3x) | -   | 5    | 30    |
| 6                | 12 (basic +alter) | 12 (2x) | -   | 6    | 30    |
| 7                | 7                 | 14 (2x) | -   | 7    | 28    |
| 8                | 8                 | 16 (2x) | -   | 8    | 32    |
| 9                | 9                 | 9 (1x)  | -   | 9    | 27    |
| 10               | 10                | 10 (1x) |     | 10   | 30    |

Main idea: Always ~30 total at launch

Drawings per player

| Player count | Drawings |
| ------------ | -------- |
| 5            | 6        |
| 6            | 5        |
| 7            | 4        |
| 8            | 4        |
| 9            | 3        |
| 10           | 3        |
