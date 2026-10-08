---
share: true
repo:
  repo: game-drawing-duel
  branch: feature/docs
title: premise
category: concept
---
There is already a huge amount of components set up in this resository and infrastructure code outside of it.

Implement the code

- Use libraries with first party or big community support only.


For CI/CD:
- Add pipelines to deploy the frontend and database migrations + backend respectively on open pull request and on main branch pushes (already exists for frontend). For PRs push to a test infrastructure.
- Add build/test validation pipelines for PRs for frontend, backend, database migrations. For database migrations ensure that no new migrations are required (alembic check)


Technical Functionality:
- On the backend make sure that all routes are protected for authenticated users only except for the open api and health endpoint. Extend the health endpoint to check database access as well.
- Make sure that most endpoints also inject user data from the database with each request to have context.
- If a user signs up for the first time, create a database record for that user and link their user id from Auth0.
- For a new drawing, upload the file to the backend, generate a uuid, save it as database metadata record and as a blob with that name and metadata (labels) with that uuid.
- For the gacha pulls, store all awarded currency on the server with timestamps, there should be checks to see if players have already received currency for something so it's no redeemed mutpile times. When spending a currency, each of the awarded currency should match that pull record. A player's pull records are the player's pool

Gameplay Loops:
- Signup/Account Creation: Keep this super simple, sign up, pick a first name (can be prefilled from the social login) to finalize the account.
- Server creation/join: One player can create a server that generates a 6-digit unique code that can be shared with friends to join there. The admin can prepopulate the server with a full list of players to start the initial drawing setup
- Initial drawing setup: See [Initial Setup](./initial-setup.md)
- Daily routine: See [Gameplay Loop](premise.md)

Design:
- Use smooth transition animations and put emphasis effort for animation on the gacha pulls and the fights
- Use Material3 where possible with a dedicated centralised color pallette 