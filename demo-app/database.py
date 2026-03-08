from motor.motor_asyncio import AsyncIOMotorClient
from config import mongo_db_config

class Database:
    def __init__(self, client: AsyncIOMotorClient | None, db: None):
        self.client = client
        self.db = db

    @classmethod
    def connect(cls):
        cls.client = AsyncIOMotorClient(mongo_db_config.DB_URI)
        cls.db = cls.client[mongo_db_config.DB_NAME]
    
    @classmethod
    def close(cls):
        if cls.client:
            cls.client.close()

    @classmethod
    def get_collection(cls, name: str):
        return cls.db[name]

# Global Instance
db_instance = Database(None, None)

def serialize_mongo_doc(doc) -> dict:
    """Helper chuyển _id (ObjectId) thành string để trả về dạng JSON"""
    if doc and "_id" in doc:
        doc["_id"] = str(doc["_id"])
    return doc
