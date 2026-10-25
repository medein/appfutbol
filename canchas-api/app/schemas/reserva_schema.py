from pydantic import BaseModel, field_validator
from datetime import date, time, datetime
from typing import Optional

# Estados que entiende la app Flutter (EstadoReserva en reserva_model.dart)
ESTADOS_VALIDOS = ["pendiente", "confirmada", "rechazada", "completada", "cancelada"]

# Métodos de pago que entiende la app Flutter (MetodoPago en reserva_model.dart)
METODOS_PAGO_VALIDOS = ["tarjeta", "transferencia", "efectivo"]


class CanchaResumen(BaseModel):
    """Datos mínimos de la cancha para que la app muestre el nombre sin otra llamada."""
    id: int
    nombre: str
    imagen_url: Optional[str] = None
    complejo_id: Optional[int] = None
    complejo_nombre: Optional[str] = None

    class Config:
        from_attributes = True


class UsuarioResumen(BaseModel):
    """Quién hizo la reserva. Lo usa el panel del administrador."""
    id: int
    nombre: str
    email: str
    telefono: Optional[str] = None

    class Config:
        from_attributes = True


class ReservaCreate(BaseModel):
    cancha_id: int
    fecha_reserva: date
    hora_inicio: time
    hora_fin: time
    notas: Optional[str] = None
    metodo_pago: Optional[str] = "transferencia"

    @field_validator("metodo_pago")
    @classmethod
    def validar_metodo_pago(cls, valor: Optional[str]) -> str:
        normalizado = (valor or "transferencia").strip().lower()
        if normalizado not in METODOS_PAGO_VALIDOS:
            raise ValueError(
                f"Método de pago no válido. Usa uno de: {', '.join(METODOS_PAGO_VALIDOS)}"
            )
        return normalizado


class EstadoUpdate(BaseModel):
    estado: str
    motivo: Optional[str] = None

    @field_validator("estado")
    @classmethod
    def validar_estado(cls, valor: str) -> str:
        normalizado = (valor or "").strip().lower()
        if normalizado not in ESTADOS_VALIDOS:
            raise ValueError(
                f"Estado no válido. Usa uno de: {', '.join(ESTADOS_VALIDOS)}"
            )
        return normalizado


class PagoCreate(BaseModel):
    """Constancia del cobro con tarjeta.

    La app solo envía el monto, el método y los últimos 4 dígitos como
    referencia: el número completo, el CVV y el vencimiento nunca llegan aquí.
    """
    metodo_pago: Optional[str] = "tarjeta"
    monto: Optional[float] = None
    referencia: Optional[str] = None
    estado: Optional[str] = None


class ReservaResponse(BaseModel):
    id: int
    uuid: str
    cancha_id: int
    usuario_id: int
    fecha_reserva: date
    hora_inicio: time
    hora_fin: time
    estado: str
    precio_total: float
    metodo_pago: Optional[str] = None
    pagado: bool
    comprobante_url: Optional[str] = None
    referencia_pago: Optional[str] = None
    notas: Optional[str] = None
    motivo_cancelacion: Optional[str] = None
    fecha_cancelacion: Optional[datetime] = None
    creado_por_ia: bool
    fecha_creacion: datetime
    cancha: Optional[CanchaResumen] = None
    usuario: Optional[UsuarioResumen] = None

    class Config:
        from_attributes = True