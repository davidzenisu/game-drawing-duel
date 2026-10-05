# Notes for running python app
uv sync
uv run ruff check
uv run uvicorn app.main:app --reload --host 0.0.0.0 --port 8000 --env-file .env