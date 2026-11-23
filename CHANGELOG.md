# Release notes

All notable changes to Drawing Duel, newest first. The app shows these same
notes under **What's new** in the account menu.

Versions follow [semantic versioning](https://semver.org). Up to 0.6.0,
every week (Monday to Sunday, UTC) was one version. Since then, every
change is a version of its own, dated the day it went live (UTC): a minor
version when it adds or changes something, a patch when it only fixes. While
the game is in early development (0.x), versions stay below 1.0.

## [0.30.0] - 2026-11-23

### Added
- Music and sound effects, in a retro chiptune style: turn **Music** and
  **Sound effects** on separately in the account menu (both are off until
  you do, and your device remembers them).
- Buttons click like a mouse when you press them, the main ones (like
  Ready, Done or Save) a little fuller.
- Fights are heard as they play out: the entrance, "Fight!", every swing
  and punch, and a booming knockout.
- Every reward chimes as it comes in: the daily steps, won fights,
  collected rewards and accepted gifts. Unlocking an upgrade gets a
  fanfare.
- The drawing clock ticks each second and beeps for the last 10, a buzzer
  sounds when time is up, and a chime when your drawing is saved.
- Boost stars sparkle as they land, and fights end on a fanfare when your
  fighters win, or a sad little tune when the challenger does.
- An epic-sounding summon: the tape tears as fast as you swipe, the box
  rumbles and bursts open, and every rarity gets its own fanfare, the
  legend's the biggest.

## [0.29.0] - 2026-11-23

### Changed
- Pulls now give a 1 star 60% of the time and a 2 star 30% (instead of 50%
  and 40%), on both banners; 3 and 4 stars stay at 8% and 2%. Teams get a
  little weaker, so challengers win a few more fights.

## [0.28.0] - 2026-11-23

### Changed
- In the week ranking, challengers with as many boost stars now rank a
  player's second drawing after everyone else's first, so the weekly heroes
  spread across players. More boost stars still always rank higher.

## [0.27.0] - 2026-11-23

### Changed
- Win rates now give one extra star for winning at least 80% of the
  meetings with another player's characters, exactly 80% included. Winning
  less gives no extra stars, and there are no more two extra stars. It
  counts from today's fights on.

## [0.26.0] - 2026-11-22

### Changed
- Each week's finale now crowns its top 3 challengers as weekly heroes:
  the 1st as a ★★★★ legend, the 2nd as a ★★★ hero and the 3rd as a ★★
  adventurer.
- Challengers with as many boost stars are ranked by the boost stars all the
  challengers of their artist got that week, then by their win rate, then
  by the latest day they were drawn.
- A challenger's details in the ranking show the day it was drawn with that
  day's theme, its artist's boost stars that week and its win rate.
- The weekly banner features this week's three heroes only, without the
  legends of their players.
- Last week's ranking shows the weekly heroes on big cards with their place,
  framed in their rarity's colour, then the other challengers.

## [0.25.0] - 2026-11-22

### Added
- Close Calls: new rewards for winning your fights by exactly one star, like
  9 against 8, at 1, 3, 5, 10, 25 and 50 close calls.
- Many more levels of wins and streaks: wins at 1, 3, 5, 10, 25 and 50, and
  every streak from 3 to 25 wins in a row. Every level is worth 5 stars, and
  the levels you already reached are ready to collect.

### Changed
- Rewards show only the next level of wins, streaks and Close Calls;
  collecting one brings up the next.
- Speed sessions only show the rewards you can still reach in them.

## [0.24.0] - 2026-11-22

### Added
- A redo button next to undo while drawing: it brings back what undo took
  back, stroke by stroke, until you draw or clear again.

### Changed
- Cleared the canvas by mistake? Undo brings the whole drawing back in one
  tap, then takes back its strokes one by one as usual. Undo and the bin are
  greyed out while there's nothing to undo or clear.

## [0.23.0] - 2026-11-21

### Added
- A hurry can come with a short message of up to 60 characters: write your
  own or pick "No pressure 😇", "You can do it 💪" or "Hurry crew 👩‍🚀". It
  stays a surprise until the hurry hits, then shows with the sender's name
  while drawing, and the drawing's result screen lists every hurry with its
  message. Tapping the hub's **Hurry sent**
  button shows whom you hurried and what you wrote.

### Changed
- The hurry banner shows over the top bar, next to the clock, instead of over
  the drawing, so it never covers what you draw.

## [0.22.1] - 2026-11-20

### Fixed
- In the browser, back goes back one screen at a time, however often you
  press it, instead of leaving the game for the sign-in page from the second
  time on. On the hub, it asks **Leave the game?** first.

## [0.22.0] - 2026-11-19

### Added
- The boost stars change every week with how last week's fights went: when
  the heroes won more than 60% of them, everyone has one more boost star a
  day this week, more than 80% two more; under 40%, one fewer, under 20% two
  fewer. They stack from week to week, between 3 and 6 a day, and it takes
  at least 7 fights. It starts with the week of Monday, 23 November; speed
  mode keeps 3.
- Last week's challengers in the week ranking start with a **Boost balance**
  card: this week's boost stars a day, and how they changed with last
  week's hero win rate. The boost tutorial explains how it works.

### Changed
- From the week of Monday, 23 November, win rates give one extra star for
  winning more than 60% of the meetings with another player's characters
  (was 50%), and two for more than 80% (was 75%).

## [0.21.0] - 2026-11-19

### Added
- The Collection shows which characters are resting after a fight: greyed
  out, with a moon and the days left on their card ("Resting, back in 2
  days" or "back tomorrow"), every day, also on days without a fight, and
  right after you pick them. Their details say so too, and the new
  **Resting** filter lists only the characters on cooldown.
- The Collection's new **Cooldown** sort, now the default: the characters
  without a cooldown first, then the ones back soonest.

## [0.20.3] - 2026-11-18

### Fixed
- In the week ranking's challenger pie, the ninth and tenth players of a
  full roster get colors of their own, instead of sharing one grey slice.

## [0.20.2] - 2026-11-18

### Added
- The week ranking's challengers of this week show who they portray, as a
  pie, drawn so far. Their stars and ranking still wait for the week to be
  over.

## [0.20.1] - 2026-11-18

### Added
- The week ranking ranks the **players** too: Giant Slayer, Grand Artist
  and Addict, picked with a three-part button, for this week so far or last
  week. First places wear a trophy (outlined while it's still to win), and
  everyone shows the trophies they won. Grand Artist stays secret until the
  week is over.

### Changed
- The week ranking opens from the first day, with two views, Players and
  Challengers, each for this week or last week. It opens on the players of
  this week. This week's challengers wait for the week to be over; last
  week's are ranked by their stars as before.
- Weeks are named by number: "Week 1" is the launch week.
- This week's ranking is kept on the device for the day, last week's until
  the next week is over; the refresh button asks again.

## [0.20.0] - 2026-11-18

### Added
- **Weekly trophies**: every week, the players are ranked in three
  categories, and when a new week begins, the first place of each wins a
  trophy worth 3 stars, as a gift on the notification board. Tied first
  places each win one.
  - **Giant Slayer**: fights won with the fighters you picked.
  - **Grand Artist**: the boost stars your challengers got, in the week of
    their fight.
  - **Addict**: the days in a row, even across weeks, you did every step
    you could: your title, drawing, boosts and fight.

## [0.19.0] - 2026-11-18

### Added
- A small banner on the title screen, in the gold word art of the summon
  banners: SPONSORED BY OLIVIA'S CLAUDE SUBSCRIPTION. A moment after everything else is in, it
  slides up from below, under Tap to start.

## [0.18.0] - 2026-11-17

### Changed
- Stars now buy pulls any time, not only once your pulls are used up, and
  right where you summon: short of pulls for a Pull ×1 or Pull ×10, the
  missing ones are bought with your stars (10 stars a pull) in the same
  step. A ×10 with 3 pulls left and 70 stars just works.
- Every pull asks first, showing what it spends: your pulls, and the stars
  for the ones you're short of.

### Removed
- The **Buy a pull** button in the menu under your pulls: summoning tops up
  your pulls instead.

## [0.17.0] - 2026-11-17

### Added
- Ideas and bug reports have a status: open, in progress, in review,
  rejected or done. Server admins set it from a dropdown on each one.
- Once your idea or bug report is in review, check it and tap **It's fixed
  now**: it's done, and a pull waits for you on the notification board as
  a thank you.
- A **Show all** toggle on the Ideas & bugs board.

### Changed
- The Ideas & bugs board only shows the open, in progress and in review
  ones, unless you show them all.

## [0.16.1] - 2026-11-17

### Fixed
- The app is called Drawing Duel from the start: in the browser tab while
  it loads, and when you install it on your phone or computer, instead of
  "frontend".

## [0.16.0] - 2026-11-17

### Changed
- Who draws your prompt, whose challengers you boost and whose you fight
  are now shuffled afresh every day, instead of always the same players.
  You never draw your own prompt, nor one of yourself. Running games
  switch from tomorrow on.

## [0.15.0] - 2026-11-17

### Changed
- Pulls come out of a cardboard gacha box in 3D, the camera swaying round
  it. Swipe along its tape to cut it open: the phone buzzes and light
  shines out of the cut, white at first, then in the colour of the rarest
  pull inside. Nine tenths of the way is enough. The box then shakes and opens with a heavy buzz, heavier
  the rarer the pull, and the card rises out of it before it flips. A 10-pull
  has one box: its cards fan out of it into the carousel. The weekly hero
  banner's box is taped in gold.

## [0.14.0] - 2026-11-16

### Added
- Refresh buttons on the win rates and the fight replay.

### Changed
- The win rates and the fight replay open right away: the win rates are
  kept on your device for their week, the days with fights for the day,
  and a past day's fights for good.

## [0.13.0] - 2026-11-16

### Added
- The week ranking shows a pie of how often each player was chosen as a
  challenger, with every player's count and share.
- A refresh button on the week ranking.

### Changed
- The weekly hero sits on a big card of its own above the ranking.
- The week ranking opens right away: it's kept on your device until the
  next week is over.

## [0.12.1] - 2026-11-16

### Fixed
- The week ranking only has challengers whose fight was that week: one
  titled on Friday or later is fought the next week, and ranks there.

## [0.12.0] - 2026-11-15

### Added
- Tap a challenger in the week ranking for its details: its drawing full
  screen, who drew it, who wrote its prompt, who boosted it with how many
  stars, and who it won or lost against.

### Changed
- The week ranking shows each challenger's drawing, nameplate and stars
  only.

## [0.11.1] - 2026-11-15

### Fixed
- Far fewer "Something went wrong" errors when several players play at
  once, and a clear message instead of "Failed to fetch" when one happens.

## [0.11.0] - 2026-11-14

### Added
- **Rewards** in the heroes menu: stars for summoning every starter hero of
  a player (as artist or portrayed) or of a rarity, and for winning 1, 3
  and 10 fights, and 3 and 5 in a row.
- Release notes, under **What's new** in the account menu, and in the
  repository.

### Changed
- After a fight, characters rest by rarity instead of until Monday: a day
  for a basic one, up to four for a legend. Basic ones rest too, and the
  roster shows the days left.
- The game loads faster after your first visit: drawings are kept on your
  device instead of downloaded every time. Signing out removes them.
- Boosts are saved all at once with **Done**, not with every star; leaving
  with stars not saved asks first.

### Fixed
- A drawing that fails to download while the game loads is tried again,
  instead of stopping with "Signing in failed".
- The stars for writing a title show right away, instead of with the next
  reward.

## [0.10.0] - 2026-11-13

### Added
- **Stars**, a new currency: 3 for writing a challenger title, 3 for drawing
  a challenger, and a challenger's stars for beating it. They show under your
  pulls.
- The artist of a challenger that wins a fight collects its stars in the
  Challengers menu, from the day after the fight.
- 10 stars buy a pull once all your pulls are used.
- New stars are celebrated like pulls, together when both arrive.
- Gifts can also bring stars, or just a message.
- An **Ideas & bugs** board in the account menu: post ideas and bug reports,
  upvote the ones of your server, and remove your own.
- A **Ready** button starts the challenger drawing's clock, so you can read
  the prompt first.

### Changed
- You only see your own challengers, and replays of your own fights.
- The drawing canvas takes the full width on phones, with a slimmer top bar
  and the tools on two rows.
- Who and what to draw shows in a nameplate; the prompt's question is behind
  the info button.

### Fixed
- The text under the banners on the summon page is readable in dark mode.
- After a drawing, the upload finishes before its recap and the
  celebration of its rewards.

## [0.9.0] - 2026-11-12

### Added
- Hero list filters for the heroes you summoned and the drawings of or by a
  player.

### Changed
- Win rates open once the first week is over.
- The standard banner shows a fixed trio each week, rotating through the
  roster; more 1 stars than 2 stars, and each week's new 3 star joins it.

### Fixed
- No drawing preview when choosing a challenger to write a title for.

## [0.8.0] - 2026-11-10

### Added
- Download a character's drawing as a PNG from its page.

### Changed
- 90 seconds to draw a challenger, and the hurry button sits on the hub.
- The lobby and the setup refresh on demand instead of every few seconds.

## [0.7.0] - 2026-11-09

### Added
- Gifts of pulls on the notification board, celebrated with a ticket that
  flies into your pulls.
- Change your account name from the account menu, and your name on a server
  when you create it.

### Changed
- The boost step shows the challenger's fight scenery.

## [0.6.0] - 2026-11-08

### Added
- **Win rates**: last week's results give extra stars in this week's fights.
- Replay any fight of the days before today.
- A recap of your challenger drawing, to share as a screenshot.
- A title screen while the game loads, and the game's logo as the app icon.
- A note on the game for new players; joining a server comes first.
- When a summoned duplicate makes an upgrade ready, the game tells you.

### Changed
- A new daily hub with big buttons, the daily loop two by two, and a heroes
  menu.
- A greyed out button says why it isn't available when tapped.
- Hurries hit the day after they're sent: 5 seconds each, spread between
  55 and 15 seconds left.
- Once the drawing clock runs, there's no backing out.
- Skipping your drawing costs the next day's boosts.

### Fixed
- Seven small layout fixes on phones: keyboard, hub title, win rates, the
  drawing tools, the hero list and the fight's life bars.

## [0.5.0] - 2026-11-01

### Added
- **Speed mode**: a one-off session of about 17 minutes on timers, with its
  own final ranking.
- Change a character's element for free, and see your collection's progress.
- Unlocked upgrades are celebrated.
- Every setup drawing gets a starter prompt.

### Changed
- Boost challengers before they're fought, by dragging stars onto them, and
  fights are decided right away.
- A won fight earns a pull and the challenger's stars.
- The week's challengers are ranked instead of voted on.

### Removed
- The battle results overview.

## [0.4.0] - 2026-10-21

### Added
- Intros the first time each step opens, and **How to play**.
- Fights with entrances, clearer hits and a result reveal.
- A pull reveal that builds up to its rarity, and a carousel for multi-pulls.
- See what you can pull, by rarity and chance.
- Standard and weekly banners, with the weekly hero and their legend rated
  up, and big banners to swipe through.
- Longer upgrade paths with four new effects; filter and sort the collection,
  and switch effects on and off.

### Changed
- Every character's name shows before it's summoned.

### Fixed
- Every challenger gets one fight.

## [0.3.0] - 2026-10-18

### Added
- Weekday themes, each with descriptions and premade titles.
- Choose who fits the day's description best for your challenger title.
- Boost yesterday's challengers: stars decide the fights.
- The weekly finale: the week's best challenger joins the gacha pool.
- The intros you saw are remembered.

### Changed
- Every character fights once a week; basic characters every day.
- A server uses every description once only.

## [0.2.0] - 2026-10-11

### Added
- Sign in, and servers: create one with a 6-digit code, or join by claiming a
  seat.
- The setup: everyone draws the other players, then the game launches.
- Gacha pulls, and upgrades unlocked with duplicates.
- The daily loop: write a title, draw a challenger, pick fighters, and the
  free daily hurry.
- Cancel a server.
- A brown brush.
- Challengers get their own list, outside the gacha pool, and the collection
  shows characters not summoned yet.

## [0.1.0] - 2026-10-04

### Added
- The first version: the drawing canvas and a mockup of the gameplay loop.
