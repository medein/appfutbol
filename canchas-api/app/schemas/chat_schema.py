from pydantic import BaseModel
from typing import List, Optional
from datetime import datetime


class MensajeChat(BaseModel):
    mensaje: str


class RespuestaChat(BaseModel):
    respuesta: str
    intencion: Optional[str] = None
    # Botones de respuesta rápida, ej.: ["Sí, confirmar", "No, cambiar"]
    opciones: List[str] = []
    accion_resultado: Optional[dict] = None


class ConversacionResponse(BaseModel):
    """Un turno del chat tal como lo guarda la tabla conversaciones_ia.

    La app parte cada registro en dos globos: la pregunta y la respuesta.
    """
    id: int
    mensaje_usuario: str
    respuesta_ia: Optional[str] = None
    intencion_detectada: Optional[str] = None
    resultado_accion: Optional[dict] = None
    fecha_creacion: Optional[datetime] = None

    class Config:
        from_attributes = True