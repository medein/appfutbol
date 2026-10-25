from sqlalchemy import Column, BigInteger, String, Text, DateTime, JSON, ForeignKey
from datetime import datetime
from app.database import Base

class ConversacionIA(Base):
    __tablename__ = "conversaciones_ia"

    id = Column(BigInteger, primary_key=True, index=True)
    usuario_id = Column(BigInteger, ForeignKey("usuarios.id"), nullable=False)
    mensaje_usuario = Column(Text, nullable=False)
    respuesta_ia = Column(Text, nullable=True)
    intencion_detectada = Column(String(50), nullable=True)
    resultado_accion = Column(JSON, nullable=True)
    fecha_creacion = Column(DateTime, default=datetime.now)