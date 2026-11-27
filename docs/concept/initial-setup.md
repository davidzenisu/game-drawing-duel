---
share: true
repo:
  repo: game-drawing-duel
  branch: feature/docs
title: initial-setup
category: concept
---
When a server is created, the creator can prepopulate their own and all other player's names. Their own name starts as their account's first name; tapping it lets them go by another name on that server only (the account keeps its name).

They can then share a generated server code with friends to join. The lobby (while friends join) and the setup (while they finish their drawings) don't update on their own: a **refresh** button in the top right checks who joined or finished, and whether the game moved on or was cancelled.

On the title screen the game opens on, below **Tap to start**, a small banner reads **SPONSORED BY OLIVIA'S CLAUDE SUBSCRIPTION** on three lines, in the outlined, slanted word art of the summon banners' names, in the standard banner's gold. It comes in last: once the title, the standees and the button are in, it waits a moment, then slides up from below (all at once when the platform asks for less motion). It shows nowhere else.

After signing up, a player picks between joining a server and creating one. Joining comes first, since most players join a friend's server with its code. Until they dismiss it, new players also see a short note there: the game in one sentence (you and your friends draw each other as heroes and challengers, collect the drawings and send them into fights), and that everything is explained step by step once they join or create a server.

In the top right of the main screens (servers, lobby, setup and the daily hub), an **account** menu shows who you're signed in as, lets you change your account's first name, turn **Music** and **Sound effects** on or off, see **What's new** (the release notes, newest version first, with their dates) and sign out (the mockup has no account to sign out of). On a server, it also holds cancelling the server, and the server's **Ideas & bugs** board.

Only the player ends their sign-in, by pressing **Sign out**: errors never sign anyone out. When a request fails mid-game, even because the server rejected the sign-in, the error shows and the player stays where they are, able to try again; a rejected sign-in's message adds a **Sign out** action, in case it keeps happening. On opening the game, a missing or rejected sign-in leads to the sign-in screen with the reason, which offers **Sign out** next to **Sign in** (to start over with another login). Any other problem loading the game, like no connection or the server being down, shows **Couldn't load the game** with the reason, **Try again** and **Sign out**, still signed in. A missing permission is an error like any other.

The **Ideas & bugs** board is where players post ideas for the game and report bugs: a kind (idea or bug), a title and a description. For now each server has its own board: only its players see its suggestions. The board lists them most upvoted first (then newest first); a tap opens one with its full description. Players upvote the ones they'd like to see done, once each and never their own, and can take their upvote back. Authors can remove their own suggestions, and server admins (permission `manage:servers`) any, once confirmed; its upvotes go with it. Every suggestion has a status: **Open** when posted, then **In progress** (it is or will be worked on), **Rejected** (it won't be), **In review** (ready for its author to check) or **Done**. Server admins set the first four from a dropdown on the suggestion. While it's in review, its author sees a button **It's fixed now**: pressing it makes it done, and sends them 1 pull as a gift ("<title> has been fixed. Thank you for reporting it."), to accept on the notification board like any gift. A done suggestion keeps its status. If it isn't fixed after all, they talk it through outside the game for now. The board shows the open, in progress and in review suggestions; a **Show all** toggle adds the rejected and done ones. The board doesn't update on its own: a refresh button reloads it. The mockup's board starts with two sample suggestions from the friends, one of them in progress; there, you set statuses like a server admin. A new first name is your default name on servers you create from then on; servers you already joined keep the name you have there.

Any player who joins needs to do 3-6 drawings and titles for other players. The title is asked once the drawing is done (pressing Done), so typing it never takes room from the canvas. While drawing, undo takes back the last stroke, and the bin clears the canvas without asking: a mis-tap costs nothing, since undo brings the whole drawing back in one tap (then takes back its strokes one by one, as before the clear). Redo brings back what undo took back, step by step, until the player draws or clears again. Each stroke follows the one finger or pen that started it, from where it touches down: another finger touching the canvas meanwhile doesn't move it, and while a pen is on the canvas, touches don't draw (the hand resting on the screen); a touch stroke already going when the pen comes down is taken back. Between pen strokes, a finger draws as usual.

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
