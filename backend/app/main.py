import os
from typing import Annotated

from fastapi import Depends, FastAPI
from fastapi.middleware.cors import CORSMiddleware
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.database import get_db
from app.models import Drawing
from app.schemas import DrawingResponse

app = FastAPI(title="Game Drawing Duel API", version="0.1.0")


def configure_frontend_cors(application: FastAPI) -> None:
    frontend_url = os.getenv("FRONTEND_URL")
    if frontend_url:
        application.add_middleware(
            CORSMiddleware,
            allow_origins=[frontend_url],
            allow_methods=["*"],
            allow_headers=["*"],
        )


configure_frontend_cors(app)


@app.get("/health", tags=["health"])
async def health_check() -> dict[str, str]:
    return {"status": "ok"}


@app.get("/drawings", response_model=list[DrawingResponse], tags=["drawings"])
def list_drawings(
    session: Annotated[Session, Depends(get_db)],
) -> list[DrawingResponse]:
    drawings = session.scalars(select(Drawing).order_by(Drawing.id)).all()
    return [DrawingResponse.model_validate(drawing) for drawing in drawings]
