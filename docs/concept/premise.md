---
share: true
repo:
  repo: game-drawing-duel
  branch: feature/docs
title: premise
category: concept
---
Main idea is that it's a game based on a minimal list of friends (5-10 people) where all the characters are variations of the playsers themselves.

There is a full 4 day cycle that happens simultaneously for all players:

1. Prompt: Each player gets a prompt for a challenger each day that is randomly drawn from the other players (never themselves). The player needs to put in a title among with randomly drawn name; either suffixed or prefixed. There should be a relatively tight character window (e.g. 35 characters). In the future there may be a theme to match (e.g. represented by the background) but for now it's just an open prompt each day. If missed by the player, a prompt will be randomly selected from a list of ~500 pregenerated prompts from the database.
2. Sketch: Once each day, the player should draw a "challenger" (enemy) based on the prompt (see previous step) that a player party will face (see next step). This is the main way of the game to generate new content so the focus of features, functionality etc. should be om that part. The player is given one of the prompts of stage 1 (but again, never their own name) and needs to draw that prompt in a given time (~60 seconds?). This is a "mandatory" step and the only thing a player should do each day. Without this step no new content can be generated. So this step should be front and center and be somewhat mandatory before doing anything else in the game. It should also be the step that's rewarded the most.
3. Boost: On day 3, a player can go through all the challengers one by one (except for the one they will face and the one they drew) and decide how much to boost them. The challenger starts with 3 stars and the boost should give up to 3 extra stars combined to each challenger (number subject to change based on balancing). Only match-ups where the player drew neither the enemy/challenger nor selected the fighting party members should be shown to them for voting. It should a random order but "fair" (one person gets one challenger first, another player a different challenger etc.). The player can freely navigate between the three challengers to decide which to boost. ~~They can't go back to previous challengers after boosting (or not boosting) them. If they haven't used all their boost by the end they have to use it all on the last one (they should see how many there are).~~ There should be a drag and drop control at the bottom of the screen for boosting. If the player doesn't boost (or only partially) it should be spread at random. To decrease complexity, all players are only given 3 random (but fair) challengers to choose from (top 3 in their random list, the rest are omitted)
4. Challenge: Once a day, players can face challengers/enemies from the day before (see previous step) by assembling a party of legends from their roster. The roster of the player will increase over time but the main idea is that each player can select up to 4 legends as "matchups" against challengers. These challengers will apear larger at the upper part of the screen, similar to a boss in a traditional Final Fantasy game, while the legends will slot in as party members on the bottom with both the enemy as well as the party member titles cleary visible.  Each player picks from their pool of heroes. The goal is to reach more stars than the challenger (which you don't know yet). E.g. if you pick 4 one-star characters, you beat the challenger which has three stars. For equal stars, the challenger wins. Duplicate upgrades might tip the scales in the future but shouldn't be considered right now. If a fight is won by the player, the player receives a pull as a reward. If the challenger wins, it enters the finale draw for stage 5. The balancing should be in a way that ~50% of the fights are won by challengers. They should see the result immediately. If they win they get the amount of stars as a currency (decided later what to use for).
# At the very end of the week:
The challenger with the most stars at the end of the week should be the winning challenger that becomes a new 3☆ hero available to be pulled from the gacha pool.

The full rank list of challengers in order (including the amount of stars) should also be visible to the players after the week.

*The section below is still in its concept phase, ignore for now!!*

In the final battle at the end of each week, the idea is to crown the best challenger while also allowing each player to show their best fighter setup. The main idea is to give players opportunities to boost challengers to slightly change the ranking while player by player they switch from a "challenger" role to a "heroes" role to fight an increasing number of challengers.

The final battle should be a display of all players and their strength against the "best" challengers of the week.

Open questions/features:
- Already use battle rates for the final battle in a next step