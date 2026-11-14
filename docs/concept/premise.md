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
2. Sketch: Once each day, the player should draw a "challenger" (enemy) based on the prompt (see previous step) that a player party will face (see next step). This is the main way of the game to generate new content so the focus of features, functionality etc. should be om that part. The player is given one of the prompts of stage 1 (but again, never their own name) and needs to draw that prompt in a given time (90 seconds). The timer only starts once they press **Ready** on top of the canvas: until then they can read the prompt (and the question and theme behind its info button) and still leave, but not draw. Once the timer runs there's no backing out to start over: the app has no back button until the drawing is done, and on the web the browser asks before the page is closed or reloaded (if time runs out with nothing drawn, leaving is allowed again). Once the player presses Done, the clock stops and the drawing is saved first (the screen says so; if saving fails, Done tries again). Only then does the player see the drawing with its title in the blue nameplate and the names of the players who sent a hurry against it, all on one screen to share as a screenshot. This is a "mandatory" step and the only thing a player should do each day. Without this step no new content can be generated. So this step should be front and center and be somewhat mandatory before doing anything else in the game. It should also be the step that's rewarded the most.
3. Boost: On day 3, a player can go through all the challengers one by one (except for the one they will face and the one they drew) and decide how much to boost them. The challenger starts with 3 stars and the boost should give up to 3 extra stars combined to each challenger (number subject to change based on balancing). Only match-ups where the player drew neither the enemy/challenger nor selected the fighting party members should be shown to them for voting. It should a random order but "fair" (one person gets one challenger first, another player a different challenger etc.). The player can freely navigate between the three challengers to decide which to boost. ~~They can't go back to previous challengers after boosting (or not boosting) them. If they haven't used all their boost by the end they have to use it all on the last one (they should see how many there are).~~ There should be a drag and drop control at the bottom of the screen for boosting. The stars moved are only saved with the **Done** button (one save for all of them); leaving the screen with stars not saved asks first whether to save them, discard them or keep boosting (on the web, the browser asks too before the page is closed). If the player doesn't boost (or only partially) it should be spread at random. A player who didn't draw their challenger the day before can't boost at all that day (see [Skipped Days](./skipped-days.md)). To decrease complexity, all players are only given 3 random (but fair) challengers to choose from (top 3 in their random list, the rest are omitted)
4. Challenge: Once a day, players can face challengers/enemies from the day before (see previous step) by assembling a party of legends from their roster. The roster of the player will increase over time but the main idea is that each player can select up to 4 legends as "matchups" against challengers. These challengers will apear larger at the upper part of the screen, similar to a boss in a traditional Final Fantasy game, while the legends will slot in as party members on the bottom with both the enemy as well as the party member titles cleary visible.  Each player picks from their pool of heroes. The goal is to reach more stars than the challenger (which you don't know yet). E.g. if you pick 4 one-star characters, you beat the challenger which has three stars. For equal stars, the challenger wins. Duplicate upgrades might tip the scales in the future but shouldn't be considered right now. If a fight is won by the player, the player receives a pull as a reward. If the challenger wins, it enters the finale draw for stage 5. The balancing should be in a way that ~50% of the fights are won by challengers. They should see the result immediately. If they win they get the amount of stars as a currency (decided later what to use for). After a fight, a character rests before it can fight again, by its rarity: 1 day for a basic one, 2 for an adventurer, 3 for a hero and 4 for a legend (one that fought on Monday with 1 rest day is back on Wednesday). Rest days carry over from one week into the next. When picking fighters, a resting character shows a moon with the days it still rests ("2d") and "Resting, back in 2 days" (or "back tomorrow"); resting ones come last in the roster, the ones back soonest first. With every character resting, a player has no fight that day: **Pick your fighters** is greyed out, and tapping it says no heroes are available for fighting and when the first one is back.
# The app
The daily hub shows the 4 steps of the cycle as big buttons (icon and title, the tutorials explain each step), two by two:

| | |
|---|---|
| 1. Choose a challenger | 2. Draw a challenger |
| 3. Boost challengers | 4. Pick your fighters |

When choosing a challenger, picking a player shows only their name, no drawing of them.

Above them, next to the day's title and above the drawing step, a **Send a hurry** button sends the day's free hurry (greyed out once sent, or on a day without one).

Below them, a **Heroes** button opens the heroes menu with the same big buttons:

| | |
|---|---|
| **Summon** (an animated banner with the pulls ready) | |
| Hero List | Challengers |
| Rewards | Win rates |
| Fight replay (past days' fights) | Week ranking |

**Challengers** lists the challengers you drew (for now only your own, not the ones you fought or boosted), each with its record in its decided fights.

**Rewards** lists your achievements, each with your progress (e.g. "2/5"), its reward in stars and, once reached, a **Collect** button; each is collected once, and celebrated like other stars. Ready ones come first, collected ones last. The Rewards button, and the Heroes button on the hub, count the ones to collect.

| Achievement | Goal | Reward |
|---|---|---|
| *Sam's gallery* (one per other player) | Summon every starter hero (setup drawing) that player drew; your own are yours from the start | 15 − players ⭐: 10 with 5 players … 5 with 10 |
| *Portraits of Sam* / *Your portraits* (one per player) | Summon every starter hero portraying that player | the same |
| *Every starter Basic / Adventurer / Legend* | Summon every starter hero of that rarity | 10 / 15 / 20 ⭐ |
| *First win*, *3 wins*, *10 wins* | Win fights you picked the fighters for (not chance's) | 5 ⭐ each |
| *3 wins in a row*, *5 wins in a row* | Win that many of your fights in a row; a lost one starts over, days without one of your fights don't | 5 ⭐ each |

**Fight replay** lists the days before today that had fights of yours, with the day number and the calendar date (the first fights are on day 4, so replays start on day 5). For now a player only sees their own fights: picking a day shows the fight they picked the fighters for (not one chance picked for them) and the fight against the challenger they drew, each by its challenger and highlighted. Tapping a challenger replays its fight and shows the result. Today's own fight replays from the fight screen.

The **Hero List** shows every character of the pool, summoned or not, and can be narrowed down by rarity, by status (upgrade ready, summoned, not summoned) and by player: the drawings *of* a player or *by* a player. In the **Hero List**, a character's page has a **download** button (in the browser) that saves its drawing as a PNG image on its cardboard card, named after the character.

In the top right of the hub and the heroes menu, a **notification board** button has a badge counting what's new. For now that's **gifts**: pulls, stars or both an admin gives players outside the regular rewards, each with a message, or just a message when it gives neither. A gift's pulls and stars only count once it's accepted on the board ("Accept", or "Accept all"); a message is marked as read with "OK". Gifts don't expire. The board is loaded with the app and the day, without live updates; later it may carry other news too, like the weekly hero or patch notes.

Next to it, the **pulls** chip shows the pulls you have. New pulls, from a gift, a drawing or a win, are celebrated: the screen darkens, a big glowing ticket with "+N pulls" pops up in the middle, then flies into the chip, which counts up one pull at a time as it lands. Pulls earned on another screen (like the pull a drawing or a win earns) are celebrated once you're back on a screen with the chip and the other screen is gone; they're yours as soon as they're earned, even if you close the app before.

New stars are celebrated the same way, with a big star and "+N stars" flying into the pulls chip. Pulls and stars earned together (a drawing, a win) are celebrated together: the ticket and the star side by side, with e.g. "+1 pull · +3 stars". Spending stars on a pull only celebrates the pull.

A tap on the pulls chip opens a small menu under it with your **stars** ⭐, the currency players collect. What earns them is explained in the welcome intro (and "How to play"):
- writing a challenger title (step 1): 3 stars;
- drawing a challenger (step 2): 3 stars, besides its pull;
- winning a fight you picked the fighters for (step 4): the challenger's stars (its own and its boost stars), besides the pull.
- drawing a challenger that wins a fight: its stars in that fight (its own and its boost stars), whoever picked the fighters, even chance. Its artist collects them in the **Challengers** menu, on the challenger's card, from the day after the fight: the 5th day of the rotation. The Challengers button, and the Heroes button on the hub, show a badge counting the challengers with stars to collect.

Once all of a player's pulls are used, **10 stars buy a pull**, from the same menu (greyed out while pulls are left or stars are short). Each reward counts once. The victory stars of the fights won before stars came in carried over.

Players with admin permissions get an **Admin** menu in the app bar instead of several buttons: the game content (for content editors), and for players who manage servers, trying the mockup and **sending a gift**. The gift form sends pulls with a message to all servers (and all players), or to one server picked from a list, to all of its players or to players picked from its roster. The **Drawings** screen shows any drawing of any server, picked from three lists: the server, the date (or "Setup" for the initial drawings) and the drawing. It's shown as drawn, without upgrade effects, with a download button that saves it as a PNG.

A button that isn't available (yet) is greyed out instead of hidden, e.g. everything but step 1 on day 1. Tapping a greyed out button shows why, e.g. "Boosting starts on day 3." or "Speed mode has no win rates.".

# At the very end of the week:
The challenger with the most stars at the end of the week should be the winning challenger that becomes a new 3☆ hero available to be pulled from the gacha pool.

The full rank list of challengers in order (including the amount of stars) should also be visible to the players after the week.

*The section below is still in its concept phase, ignore for now!!*

In the final battle at the end of each week, the idea is to crown the best challenger while also allowing each player to show their best fighter setup. The main idea is to give players opportunities to boost challengers to slightly change the ranking while player by player they switch from a "challenger" role to a "heroes" role to fight an increasing number of challengers.

The final battle should be a display of all players and their strength against the "best" challengers of the week.

Open questions/features:
- Already use battle rates for the final battle in a next step