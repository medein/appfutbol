from pydantic import BaseModel, Field


# ---------------------------------------------------------------------------
# Entrada: crear
# ---------------------------------------------------------------------------

class ComplejoCreate(BaseModel):
    nombre: str = Field(..., min_length=2, max_length=150)
    direccion: str = Field(..., min_length=3, max_length=255)
    telefono: str | None = None
    latitud: float | None = None
    longitud: float | None = None
    horario_apertura: str | None = "07:00"
    horario_cierre: str | None = "23:00"
    calificacion_promedio: float | None = 0.0
    activo: bool = True
    imagen_url: str | None = None


# ---------------------------------------------------------------------------
# Entrada: actualizar
# ---------------------------------------------------------------------------

class ComplejoUpdate(BaseModel):
    nombre: str | None = None
    direccion: str | None = None
    telefono: str | None = None
    latitud: float | None = None
    longitud: float | None = None
    horario_apertura: str | None = None
    horario_cierre: str | None = None
    calificacion_promedio: float | None = None
    activo: bool | None = None
    imagen_url: str | None = None


# ---------------------------------------------------------------------------
# Salida: respuesta
# ---------------------------------------------------------------------------

class ComplejoOut(BaseModel):
    id: int
    nombre: str
    direccion: str | None = None
    telefono: str | None = None
    latitud: float | None = None
    longitud: float | None = None
    horario_apertura: str | None = None
    horario_cierre: str | None = None
    calificacion_promedio: float | None = None
    activo: bool | None = True
    imagen_url: str | None = None        

    # Campos calculados que agrega el router al responder
    total_canchas: int = 0
    precio_desde: float | None = None
    distancia_km: float | None = None

    class Config:
        from_attributes = True