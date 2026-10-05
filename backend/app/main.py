from fastapi import FastAPI

app = FastAPI(title="Game Drawing Duel API", version="0.1.0")


@app.get("/health", tags=["health"])
async def health_check() -> dict[str, str]:
    return {"status": "ok", "other_info": "Game Drawing Duel API is running smoothly."}