import uuid
from datetime import datetime
from typing import Annotated

from pydantic import BaseModel, ConfigDict, StringConstraints

FirstName = Annotated[
    str, StringConstraints(strip_whitespace=True, min_length=1, max_length=50)
]


class PlayerUpdate(BaseModel):
    first_name: FirstName


class PlayerResponse(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: uuid.UUID
    first_name: str
    created_at: datetime
