from typing import List, Optional
from fastapi import APIRouter, HTTPException, Request, Query
from bson import ObjectId
from datetime import datetime, UTC

from schemas import DocumentCreateSchema, DocumentUpdateSchema, DocumentResponseSchema, DocumentSchema
from database import db_instance, serialize_mongo_doc
from logger import log_audit_event

router = APIRouter(prefix="/documents", tags=["Documents"])


@router.post("", response_model=DocumentResponseSchema, status_code=201)
async def create_document(request: Request, doc_in: DocumentCreateSchema):
    # Prepare data for MongoDB (using DocumentSchema default values for timestamps/deleted)
    doc_dict = doc_in.model_dump()
    doc_dict["created_at"] = datetime.now(UTC)
    doc_dict["updated_at"] = datetime.now(UTC)
    doc_dict["last_updated_by"] = doc_in.owner_id
    doc_dict["is_deleted"] = False

    collection = db_instance.get_collection("documents")
    result = await collection.insert_one(doc_dict)

    # Retrieve the saved document to return it
    saved_doc = await collection.find_one({"_id": result.inserted_id})
    serialized_doc = serialize_mongo_doc(saved_doc)
    doc_obj = DocumentSchema(**serialized_doc)

    # --- AUDIT LOG ---
    log_audit_event(
        action="create_doc",
        request=request,
        user_id=doc_in.owner_id,
        document=doc_obj,
        outcome="success"
    )

    return serialized_doc


@router.get("", response_model=List[DocumentResponseSchema])
async def list_documents(
    request: Request,
    user_id: str = Query(..., description="User ID performing the read (for audit log)"),
    owner_id: Optional[str] = Query(None, description="Filter by owner_id"),
    include_deleted: bool = Query(False, description="Include soft-deleted documents")
):
    query = {}
    if owner_id:
        query["owner_id"] = owner_id
    if not include_deleted:
        query["is_deleted"] = False

    collection = db_instance.get_collection("documents")
    cursor = collection.find(query)
    documents = [serialize_mongo_doc(doc) async for doc in cursor]

    # --- AUDIT LOG ---
    log_audit_event(
        action="list_doc",
        request=request,
        user_id=user_id,
        document=None,
        outcome="success",
        message=f"User '{user_id}' listed documents (Filters: owner_id={owner_id}, include_deleted={include_deleted})"
    )

    return documents


@router.get("/{id}", response_model=DocumentResponseSchema)
async def get_document(
    id: str,
    request: Request,
    user_id: str = Query(..., description="User ID performing the read (for audit log)")
):
    if not ObjectId.is_valid(id):
        raise HTTPException(status_code=400, detail="Invalid ID format")

    collection = db_instance.get_collection("documents")
    doc = await collection.find_one({"_id": ObjectId(id)})

    if not doc:
        raise HTTPException(status_code=404, detail="Document not found")

    serialized_doc = serialize_mongo_doc(doc)
    doc_obj = DocumentSchema(**serialized_doc)

    # --- AUDIT LOG ---
    log_audit_event(
        action="read_doc",
        request=request,
        user_id=user_id,
        document=doc_obj,
        outcome="success"
    )

    return serialized_doc


@router.put("/{id}", response_model=DocumentResponseSchema)
async def update_document(id: str, request: Request, doc_update: DocumentUpdateSchema):
    if not ObjectId.is_valid(id):
        raise HTTPException(status_code=400, detail="Invalid ID format")

    collection = db_instance.get_collection("documents")

    # Check if document exists and get its current state
    existing_doc = await collection.find_one({"_id": ObjectId(id)})
    if not existing_doc:
        raise HTTPException(status_code=404, detail="Document not found")

    # Check soft delete status
    if existing_doc.get("is_deleted", False):
        raise HTTPException(status_code=400, detail="Cannot update a deleted document")

    # Prepare update data
    update_data = {k: v for k, v in doc_update.model_dump().items() if v is not None and k != "user_id"}
    if update_data:
        update_data["updated_at"] = datetime.now(UTC)
        update_data["last_updated_by"] = doc_update.user_id

        await collection.update_one(
            {"_id": ObjectId(id)},
            {"$set": update_data}
        )

    # Retrieve updated document
    updated_doc = await collection.find_one({"_id": ObjectId(id)})
    serialized_doc = serialize_mongo_doc(updated_doc)
    doc_obj = DocumentSchema(**serialized_doc)

    # ===== AUDIT LOG =====
    log_audit_event(
        action="update_doc",
        request=request,
        user_id=doc_update.user_id,
        document=doc_obj,
        outcome="success"
    )

    return serialized_doc


@router.delete("/{id}", status_code=204)
async def soft_delete_document(
    id: str,
    request: Request,
    user_id: str = Query(..., description="User ID performing the deletion")
):
    if not ObjectId.is_valid(id):
        raise HTTPException(status_code=400, detail="Invalid ID format")

    collection = db_instance.get_collection("documents")

    # Find existing doc
    existing_doc = await collection.find_one({"_id": ObjectId(id)})
    if not existing_doc:
        raise HTTPException(status_code=404, detail="Document not found")

    if existing_doc.get("is_deleted", False):
        raise HTTPException(status_code=400, detail="Document is already deleted")

    # Soft Delete: Update state instead of removing from DB
    await collection.update_one(
        {"_id": ObjectId(id)},
        {"$set": {
            "is_deleted": True,
            "deleted_at": datetime.now(UTC),
            "deleted_by": user_id,
            "updated_at": datetime.now(UTC),
            "last_updated_by": user_id
        }}
    )

    # Create an object representation for the log
    deleted_doc = await collection.find_one({"_id": ObjectId(id)})
    doc_obj = DocumentSchema(**serialize_mongo_doc(deleted_doc))

    # ===== AUDIT LOG =====
    log_audit_event(
        action="soft_delete_doc",
        request=request,
        user_id=user_id,
        document=doc_obj,
        outcome="success"
    )

    return
