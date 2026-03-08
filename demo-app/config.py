import os

class MongoDBConfig:
    def __init__(self):
        self.DB_HOST = os.getenv("MONGO_DB_HOST", "mongodb")
        self.DB_PORT = os.getenv("MONGO_DB_PORT", "27017")
        self.DB_USERNAME = os.getenv("MONGO_DB_USERNAME", "root")
        self.DB_PASSWORD = os.getenv("MONGO_DB_PASSWORD", "root")
        self.DB_URI = f"mongodb://{self.DB_USERNAME}:{self.DB_PASSWORD}@{self.DB_HOST}:{self.DB_PORT}/"
        self.DB_NAME = os.getenv("MONGO_DB_NAME", "demo")


mongo_db_config = MongoDBConfig()