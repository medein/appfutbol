from sqlalchemy import Column, BigInteger, String, Boolean, DateTime, Numeric, Date, Time, Text, ForeignKey
from sqlalchemy.orm import relationship
from sqlalchemy.sql import func
from app.database import Base
import uuid as uuid_lib

class Reserva(Base):
    __tablename__ = "reservas"

    id = Column(BigInteger, primary_key=True, index=True)
    uuid = Column(String(36), unique=True, default=lambda: str(uuid_lib.uuid4()))
    cancha_id = Column(BigInteger, ForeignKey("canchas.id"), nullable=False)
    usuario_id = Column(BigInteger, ForeignKey("usuarios.id"), nullable=False)
    fecha_reserva = Column(Date, nullable=False)
    hora_inicio = Column(Time, nullable=False)
    hora_fin = Column(Time, nullable=False)
    estado = Column(String(30), default="pendiente")
    precio_total = Column(Numeric(10, 2), nullable=False)
    metodo_pago = Column(String(30))
    pagado = Column(Boolean, default=False)
    notas = Column(Text)
    creado_por_ia = Column(Boolean, default=False)
    fecha_creacion = Column(DateTime, server_default=func.now())
    fecha_cancelacion = Column(DateTime, nullable=True)
    motivo_cancelacion = Column(Text)
    # Foto del depósito que sube el cliente y que el admin valida
    comprobante_url = Column(String(255), nullable=True)
    # Últimos 4 dígitos u código de la pasarela; nunca datos completos de tarjeta
    referencia_pago = Column(String(50), nullable=True)

    cancha = relationship("Cancha")
    usuario = relationship("Usuario")