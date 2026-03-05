from typing import List
from fastapi import APIRouter, HTTPException, Depends
from bson import ObjectId

from models import GenericItemCreate, GenericItemUpdate, GenericItemResponse
from dependencies import get_current_user
from database import db_instance, serialize_mongo_doc
from logger import audit_logger

router = APIRouter(prefix="/items", tags=["Items"])

@router.post("", response_model=GenericItemResponse, status_code=201)
async def create_item(item: GenericItemCreate, current_user: str = Depends(get_current_user)):
    item_dict = item.model_dump()
    collection = db_instance.get_collection("items")
    result = await collection.insert_one(item_dict)
    item_dict["_id"] = str(result.inserted_id)
    
    # --- AUDIT LOG: CREATE ---
    audit_logger.info(f"User '{current_user}' created a new item", extra={
        "event.action": "item_created",
        "event.outcome": "success",
        "user.name": current_user,
        "resource.id": item_dict["_id"],
        "resource.name": item.name
    })
    
    return item_dict

@router.get("", response_model=List[GenericItemResponse])
async def list_items(current_user: str = Depends(get_current_user)):
    collection = db_instance.get_collection("items")
    cursor = collection.find()
    items = [serialize_mongo_doc(doc) async for doc in cursor]
    
    # --- AUDIT LOG: READ (LIST) ---
    audit_logger.info(f"User '{current_user}' listed items", extra={
        "event.action": "items_listed",
        "user.name": current_user
    })
    
    return items

@router.get("/{id}", response_model=GenericItemResponse)
async def get_item(id: str, current_user: str = Depends(get_current_user)):
    if not ObjectId.is_valid(id):
        raise HTTPException(status_code=400, detail="Invalid ID format")
        
    collection = db_instance.get_collection("items")
    item = await collection.find_one({"_id": ObjectId(id)})
    if not item:
        raise HTTPException(status_code=404, detail="Item not found")
        
    # --- AUDIT LOG: READ (SINGLE) ---
    audit_logger.info(f"User '{current_user}' viewed item {id}", extra={
        "event.action": "item_viewed",
        "user.name": current_user,
        "resource.id": id
    })
        
    return serialize_mongo_doc(item)

@router.put("/{id}", response_model=GenericItemResponse)
async def update_item(id: str, item_update: GenericItemUpdate, current_user: str = Depends(get_current_user)):
    if not ObjectId.is_valid(id):
        raise HTTPException(status_code=400, detail="Invalid ID format")
        
    update_data = {k: v for k, v in item_update.model_dump().items() if v is not None}
    collection = db_instance.get_collection("items")
    
    if len(update_data) >= 1:
        update_result = await collection.update_one(
            {"_id": ObjectId(id)}, {"$set": update_data}
        )

        if update_result.modified_count == 1:
            updated_item = await collection.find_one({"_id": ObjectId(id)})
            
            # --- AUDIT LOG: UPDATE ---
            audit_logger.info(f"User '{current_user}' updated item {id}", extra={
                "event.action": "item_updated",
                "event.outcome": "success",
                "user.name": current_user,
                "resource.id": id,
                "changes": update_data # Log lại các trường dữ liệu bị thay đổi
            })
            
            return serialize_mongo_doc(updated_item)

    existing_item = await collection.find_one({"_id": ObjectId(id)})
    if existing_item:
        return serialize_mongo_doc(existing_item)

    raise HTTPException(status_code=404, detail="Item not found")

@router.delete("/{id}", status_code=204)
async def delete_item(id: str, current_user: str = Depends(get_current_user)):
    if not ObjectId.is_valid(id):
        raise HTTPException(status_code=400, detail="Invalid ID format")
        
    collection = db_instance.get_collection("items")
    delete_result = await collection.delete_one({"_id": ObjectId(id)})

    if delete_result.deleted_count == 1:
        # --- AUDIT LOG: DELETE ---
        audit_logger.info(f"User '{current_user}' deleted item {id}", extra={
            "event.action": "item_deleted",
            "event.outcome": "success",
            "user.name": current_user,
            "resource.id": id
        })
        return

    raise HTTPException(status_code=404, detail="Item not found")