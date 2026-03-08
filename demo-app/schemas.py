from pydantic import BaseModel, Field, ConfigDict
from datetime import datetime, UTC
from typing import Optional

# Base Schema containing common fields for the current state
class DocumentBase(BaseModel):
    title: str = Field(..., min_length=1, max_length=200, description="The current title of the document")
    content: str = Field(..., description="The current content of the document")

# Input Schema for creating a new document
class DocumentCreateSchema(DocumentBase):
    owner_id: str = Field(..., description="The original owner who created this document")

# Input Schema for updating a document (User ID is required for Audit Log)
class DocumentUpdateSchema(BaseModel):
    user_id: str = Field(..., description="The user ID of the person performing the update")
    title: Optional[str] = Field(None, min_length=1, max_length=200)
    content: Optional[str] = None

# Full Document State as stored in MongoDB
class DocumentSchema(DocumentBase):
    # Mapping _id from MongoDB to id in Python
    id: str = Field(..., description="MongoDB ObjectId as string", alias="_id")
    owner_id: str = Field(..., description="The document owner")
    
    # Current State Timestamps (Elasticsearch handles the historical changes)
    created_at: datetime = Field(default_factory=lambda: datetime.now(UTC))
    updated_at: datetime = Field(default_factory=lambda: datetime.now(UTC))
    last_updated_by: Optional[str] = None
    
    # Soft Delete Status
    is_deleted: bool = Field(default=False)
    deleted_at: Optional[datetime] = None
    deleted_by: Optional[str] = None

    # Pydantic v2 configuration
    model_config = ConfigDict(
        populate_by_name=True,
        json_schema_extra={
            "example": {
                "title": "Project Roadmap",
                "content": "Steps to implement ELK Audit logging.",
                "owner_id": "cuong"
            }
        }
    )

# Schema used for API responses
class DocumentResponseSchema(DocumentSchema):
    pass
