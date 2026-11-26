---
share: true
repo:
  repo: game-drawing-duel
  branch: feature/docs
title: win-rates
category: concept
---
After each week, there are win rates that decide whether the selected heroes or the challenger get extra ☆ when fighting. They come from the **Arena** votes (see [The Arena](./premise.md#the-arena)), not from the fights: the fights only use them.

This works the following way:
- Every week, the win rates between every pair of players are calculated from the Arena voted on in the week before (which holds the challengers of the week before that). So the challengers of week X are voted on in week X+1, and their votes give the win rates of week X+2: the Arena decided on Monday gives the win rates of the week that starts then.
	- A challenger counts for the player it portrays.
	- A vote for a challenger portraying Sam over one portraying Alex is a **matchup** Sam won against Alex.
	- Draws ("can't decide") and matchups of two challengers portraying the same player count for nothing.
	- Only each voter's first **10** votes on a pair of players count, so no single voter can swing a win rate.
	- It takes at least **10** matchups between two players for a win rate to count.
	- If a player's portraits won at least **60%** of their matchups with another player's, they get **one** extra ☆ against that player this week. Exactly 60% counts, e.g. 6 of 10. Anything below gives no extra ☆.
	- The win rates screen explains the band.
	- Losing gives no negative stars: a player who won 40% or less against another is the one the other player's bonus counts against.
- The first Arena is voted on in a server's second week, so the first win rates come in its third week; until then, there are none. Past fights never count.
- The numbers come from a simulation of Arena weeks with 5, 7 and 10 players (`backend/simulations/win_rates.py`), comparing each pair's share of the matchups with the share their drawings deserve: with the 60% band, about a quarter of the pairs of players get an extra ☆ a week, mostly ones that deserve it, and seldom (about 1 in 10) ones whose drawings actually lost. With higher bands, far fewer pairs get one and a much larger share of them by luck, as the matchups between two players all come from the same few drawings. Leaving out the votes on your own portraits was tried too: it loses more matchups than it removes bias.
- The boost stars of the following week are balanced with bands of their own (see [Boost Balance](./boost-balance.md)), still from the fights.
- In a fight, each hero gets its extra stars against the challenger's player, and the challenger gets its extra stars once for each hero whose player it beat most of the time. Ties still go to the challenger.
- The extra stars only decide the fight: the stars and pulls a win earns still come from the challenger's own and boost stars.
- Speed mode has no weeks and no Arena, so it has no win rates.

Where to see them:
- **Win rates** (in the heroes menu): every player as a card with their basic drawing, name and a "Show win rates" button. The top says which Arena counts ("From the Arena votes of days 8 to 14, on the challengers of days 1 to 7."), or that there are none yet before the third week. A player's card opens their matchups side by side: both players' basic drawings and names, their extra ☆ and how many matchups they won ("won 7/11 matchups"). Only pairs of players that change stars on either side are shown. It opens once the first week is over (on the first Monday), so it doesn't give away everyone's basic drawing before players met them in fights and pulls. The win rates are kept on the device for the week they apply to, so they open without asking the server again; the refresh button in the top right asks anyway.
- **Picking fighters**: every hero shows the stars its player's win rate changes against today's challenger: "+N ★" in green when it gets them, "−N ★" in red when the challenger gets them against it. They show in the roster, on the stage and summed up below it.
- **Battles**: the fight reveal adds each side's extra stars to its stars and shows them as "+N from win rates".
- **Arena tutorial**: its last page explains that the votes set the next week's win rates.
