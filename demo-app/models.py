from typing import Optional
from pydantic import BaseModel, Field
from datetime import datetime


class DocumentSchema(BaseModel):
    doc_id: str
    title: str
    content: str
    created_at: datetime = Field(default_factory=datetime.utcnow)


class GenericItemCreate(BaseModel):
    name: str
    description: Optional[str] = None
    status: str = "active"


class GenericItemUpdate(BaseModel):
    name: Optional[str] = None
    description: Optional[str] = None
    status: Optional[str] = None


class GenericItemResponse(GenericItemCreate):
    id: str = Field(alias="_id") # Map MonogoDB _id của MongoDB to string id
