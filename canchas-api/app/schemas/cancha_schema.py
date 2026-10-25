from pydantic import BaseModel
from typing import Optional

class CanchaBase(BaseModel):
    complejo_id: int = 1
    nombre: str
    tipo_deporte: Optional[str] = "futbol5"
    tipo_superficie: Optional[str] = "sintetica"
    capacidad_jugadores: Optional[int] = 10
    tiene_techo: Optional[int] = 0
    tiene_iluminacion: Optional[int] = 1
    precio_hora: float
    precio_hora_pico: Optional[float] = 0.0
    descripcion: Optional[str] 
    imagen_url: Optional[str] = None
    activa: Optional[int] = 1

class CanchaCreate(CanchaBase):
    pass

class CanchaUpdate(BaseModel):
    """Actualización parcial: solo se cambian los campos que llegan.

    El panel web manda un único campo (por ejemplo `precio_hora` al editar el
    precio, o `activa` al poner una cancha en mantenimiento). Con el esquema
    de creación eso fallaba con 422 por pedir `nombre` y, cuando sí pasaba,
    reescribía el resto de los campos con sus valores por defecto.
    """
    complejo_id: Optional[int] = None
    nombre: Optional[str] = None
    tipo_deporte: Optional[str] = None
    tipo_superficie: Optional[str] = None
    capacidad_jugadores: Optional[int] = None
    tiene_techo: Optional[int] = None
    tiene_iluminacion: Optional[int] = None
    precio_hora: Optional[float] = None
    precio_hora_pico: Optional[float] = None
    descripcion: Optional[str]
    imagen_url: Optional[str] = None
    activa: Optional[int] = None

class CanchaResponse(CanchaBase):
    id: int

    class Config:
        from_attributes = True

from pydantic import field_validator

class CanchaUpdate(BaseModel):
    activa: bool | None = None

    @field_validator("activa", mode="before")
    @classmethod
    def _coercionar_activa(cls, v):
        if v is None:
            return v
        if isinstance(v, bool):
            return v
        if isinstance(v, (int, float)):
            return bool(v)
        if isinstance(v, str):
            return v.lower() in ("true", "1", "yes", "si", "sí")
        return v
