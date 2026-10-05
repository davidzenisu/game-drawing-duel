from datetime import datetime

from pydantic import BaseModel, ConfigDict


class DrawingResponse(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: int
    description: str
    created_at: datetime
    updated_at: datetime
