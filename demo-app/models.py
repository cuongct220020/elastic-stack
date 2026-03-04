from typing import Optional
from pydantic import BaseModel, Field

# Template Model: Sau này bạn có thể đổi thành Account, User, Document...
class GenericItemCreate(BaseModel):
    name: str
    description: Optional[str] = None
    status: str = "active"

class GenericItemUpdate(BaseModel):
    name: Optional[str] = None
    description: Optional[str] = None
    status: Optional[str] = None

class GenericItemResponse(GenericItemCreate):
    id: str = Field(alias="_id") # Map _id của MongoDB thành id dạng chuỗi
