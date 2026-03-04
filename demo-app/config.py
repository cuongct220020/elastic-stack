import os

MONGO_URI = os.getenv("MONGO_URI", "mongodb://root:example@mongodb:27017/")
DATABASE_NAME = "demo_db"
