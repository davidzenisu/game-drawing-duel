from typing import Annotated

from fastapi import APIRouter, Depends
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.auth import CurrentPlayer
from app.database import get_db
from app.models import Drawing
from app.schemas import DrawingResponse

router = APIRouter(prefix="/drawings", tags=["drawings"])


@router.get("", response_model=list[DrawingResponse])
def list_drawings(
    _player: CurrentPlayer,
    session: Annotated[Session, Depends(get_db)],
) -> list[DrawingResponse]:
    drawings = session.scalars(select(Drawing).order_by(Drawing.id)).all()
    return [DrawingResponse.model_validate(drawing) for drawing in drawings]
