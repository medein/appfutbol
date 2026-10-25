"""
app/models/__init__.py

Importa todos los modelos en un solo lugar para que SQLAlchemy pueda
resolver las relaciones entre tablas (relationship(...)) sin importar
en qué orden se carguen los archivos.
"""

from app.models.usuario import Usuario
from app.models.complejo import Complejo
from app.models.cancha import Cancha
from app.models.reserva import Reserva
from app.models.conversacion_ia import ConversacionIA

__all__ = [
    "Usuario",
    "Complejo",
    "Cancha",
    "Reserva",
    "ConversacionIA",
]