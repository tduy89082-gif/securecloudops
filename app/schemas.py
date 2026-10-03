from pydantic import BaseModel, Field


class TaskCreate(BaseModel):
    title: str = Field(min_length=1, max_length=200)
    description: str | None = Field(default=None, max_length=500)


class TaskUpdate(BaseModel):
    title: str = Field(min_length=1, max_length=200)
    description: str | None = Field(default=None, max_length=500)
    completed: bool


class TaskRead(BaseModel):
    id: int
    title: str
    description: str | None
    completed: bool

    model_config = {"from_attributes": True}