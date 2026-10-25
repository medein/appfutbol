import os
from sqlalchemy import create_engine
from sqlalchemy.ext.declarative import declarative_base
from sqlalchemy.orm import sessionmaker

# Lee la URL desde las variables de entorno
DATABASE_URL = os.getenv("DATABASE_URL")

# 👇 FORZAMOS EL USO DE SSL (Sin necesidad del archivo ca.pem)
engine = create_engine(
    DATABASE_URL,
    connect_args={
        "ssl": {
            "ssl_disabled": False
        }
    }
)

SessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)
Base = declarative_base()

def get_db():
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()