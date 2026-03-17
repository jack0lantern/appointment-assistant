from pydantic import BaseModel


class ClientCreate(BaseModel):
    name: str


class ClientResponse(BaseModel):
    id: int
    user_id: int | None = None
    therapist_id: int
    name: str

    model_config = {"from_attributes": True}
