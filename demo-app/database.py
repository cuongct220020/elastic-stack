from motor.motor_asyncio import AsyncIOMotorClient
from config import MONGO_URI, DATABASE_NAME

class Database:
    client: AsyncIOMotorClient = None
    db = None

    @classmethod
    def connect(cls):
        cls.client = AsyncIOMotorClient(MONGO_URI)
        cls.db = cls.client[DATABASE_NAME]
    
    @classmethod
    def close(cls):
        if cls.client:
            cls.client.close()

    @classmethod
    def get_collection(cls, name: str):
        return cls.db[name]

# Instance toàn cục để gọi db ở mọi nơi
db_instance = Database()

def serialize_mongo_doc(doc) -> dict:
    """Helper chuyển _id (ObjectId) thành string để trả về dạng JSON"""
    if doc and "_id" in doc:
        doc["_id"] = str(doc["_id"])
    return doc
