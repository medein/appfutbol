from sqlalchemy import (
    Column, BigInteger, String, Boolean, Numeric, Integer, ForeignKey
)
from sqlalchemy.orm import relationship
from app.database import Base


class Cancha(Base):
    __tablename__ = "canchas"

    id = Column(BigInteger, primary_key=True, index=True)
    complejo_id = Column(BigInteger, ForeignKey("complejos.id"))
    nombre = Column(String(100), nullable=False)
    tipo_deporte = Column(String(50))
    tipo_superficie = Column(String(50))
    capacidad_jugadores = Column(Integer)
    tiene_techo = Column(Integer)
    tiene_iluminacion = Column(Integer)
    precio_hora = Column(Numeric(10, 2))
    precio_hora_pico = Column(Numeric(10, 2))
    descripcion = Column(String(255), nullable=True)
    imagen_url = Column(String(255), nullable=True)
    activa = Column(Integer)

    # Relación con el complejo (para hacer joinedload desde Reserva).
    complejo = relationship("Complejo", lazy="joined")

    @property
    def complejo_nombre(self) -> str | None:
        """Se expone en la API para que la app muestre el nombre del complejo."""
        return self.complejo.nombre if self.complejo else None