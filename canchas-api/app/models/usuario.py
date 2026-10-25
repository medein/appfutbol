from sqlalchemy import (
    Column, BigInteger, String, Boolean, DateTime, Date, ForeignKey
)
from sqlalchemy.sql import func
from app.database import Base


class Usuario(Base):
    __tablename__ = "usuarios"

    id = Column(BigInteger, primary_key=True, index=True)
    nombre = Column(String(100), nullable=False)
    email = Column(String(150), unique=True, nullable=False, index=True)
    telefono = Column(String(20))
    password_hash = Column(String(255), nullable=True)

    # cliente | admin_complejo | superadmin
    rol = Column(String(20), nullable=False, default="cliente")

    # Solo aplica si rol == "admin_complejo": qué complejo administra.
    complejo_id = Column(BigInteger, ForeignKey("complejos.id"), nullable=True)  # ← NUEVO

    fecha_registro = Column(DateTime, server_default=func.now())
    activo = Column(Boolean, default=True)
    foto_url = Column(String(500))
    direccion = Column(String(255), nullable=True)
    fecha_nacimiento = Column(Date, nullable=True)