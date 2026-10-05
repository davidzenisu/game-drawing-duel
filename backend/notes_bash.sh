# Notes for running python app
uv sync
uv run ruff check
uv run uvicorn app.main:app --reload --host 0.0.0.0 --port 8000 --env-file .env
# run alembic revision
uv run --env-file .env alembic revision --autogenerate -m "describe schema change"
# run alembic migration
uv run --env-file .env alembic upgrade head
# check if there are changes
uv run alembic check
echo $? #should be 0 if no changes