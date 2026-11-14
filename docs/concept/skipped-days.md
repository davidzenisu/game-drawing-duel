---
share: true
repo:
  repo: game-drawing-duel
  branch: feature/docs
title: skipped-days
category: concept
---

Nobody has to do every step every day: the game never waits for a player. A day ends at midnight UTC on a regular server (in speed mode on its timer, or early once everyone is done; in a test session once the admin or everyone ends it), and whatever a player left undone is handled as below. Every step but the drawing has a stand-in, so the others' days go on as if nothing happened.

# 1. Prompt
If a player writes no challenger title, a premade one stands in: the premade title of the theme hint they got that day (see [Themes](./themes.md)), for a person picked by chance (never themselves). Without any hint, the title is "The Mystery Challenger". The next player draws it the day after like any other prompt, so nobody misses their drawing because someone skipped writing. The drawer isn't told who wrote none: the drawing screen just shows the person and title to draw in a blue nameplate, like any prompt (the day's question and theme are behind its info button, to leave the canvas the whole width).

# 2. Drawing
The drawing has no stand-in. Its prompt can only be drawn on its own day; once the day is over, that challenger is never drawn.
- The player misses the pull a drawing earns, and has no challenger in that week's ranking (or the race to become the weekly hero).
- The player can't boost the next day: the boost step is greyed out, saying why, and chance doesn't spread their stars either.
- The next day, the boosts skip the missing challenger: everyone who would have seen it gets the next player's instead, so some challengers are boosted by more players than others.
- The day after, the player who would have fought it fights the next player's challenger instead, so that one gets two fights.
- Hurries sent against that drawing do nothing.
- The other players aren't told; only the ranking shows that a challenger is missing.

This makes the drawing the only step whose skipping costs the others something: the prompt someone wrote goes undrawn, and boosts and fights are spread unevenly.

# 3. Boosts
Once the day is over, the boost stars a player didn't give are spread by chance across their challengers to boost. A player who skipped the drawing the day before has no boosts to give, by hand or by chance (see above). That's for balance: only the players who drew boost, so however many skip, there are as many boosters as challengers, and challengers get about the same boost stars as on a day everyone drew instead of a few challengers sharing everyone's stars.

# 4. Fight
Once the day is over, chance picks fighters for a player who didn't: 1 to 4 of their characters that don't rest after a fight, sent against their challenger (with every one resting, nobody). The fight is decided by the stars as usual and counts for the challenger's record, the ranking and next week's win rates (see [Win Rates](./win-rates.md)). A win by chance earns no pull and no stars, though: only fights a player picks themselves pay out. The characters chance sent rest afterwards like any others.

# Hurry
A free hurry that isn't sent is lost; it doesn't carry over to the next day.

# Open ideas
- A stand-in for a skipped drawing, e.g. one of the player's setup drawings or a premade sketch, so the prompt's author still sees a challenger and boosts and fights stay even.
- A reminder before the day ends for a player who hasn't drawn yet.
