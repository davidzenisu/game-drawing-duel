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


Functionality:
- On the backend make sure that all routes are protected for authenticated users only except for the open api and health endpoint. Extend the health endpoint to check database access as well.
- Make sure that most endpoints also inect user data from the database with each request to have context.
- 

Design:
- 