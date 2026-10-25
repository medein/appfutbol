from sqlalchemy import Column, BigInteger, String, Boolean, DateTime, Numeric, Time, ForeignKey
from sqlalchemy.sql import func
from app.database import Base

class Complejo(Base):
    __tablename__ = "complejos"

    id = Column(BigInteger, primary_key=True, index=True)
    nombre = Column(String(150), nullable=False)
    direccion = Column(String(255), nullable=False)
    latitud = Column(Numeric(10, 8))
    longitud = Column(Numeric(11, 8))
    telefono = Column(String(20))
    horario_apertura = Column(Time, default="07:00:00")
    horario_cierre = Column(Time, default="23:00:00")
    propietario_id = Column(BigInteger, ForeignKey("usuarios.id"))
    calificacion_promedio = Column(Numeric(3, 2), default=0.0)
    activo = Column(Boolean, default=True)
    fecha_creacion = Column(DateTime, server_default=func.now())
    imagen_url = Column(String(500), nullable=True)  