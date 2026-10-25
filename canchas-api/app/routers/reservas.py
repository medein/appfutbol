import os
from fastapi import APIRouter, Depends, HTTPException, status, UploadFile, File
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session, joinedload
from sqlalchemy import and_, or_, func
from datetime import datetime, time as time_type
from typing import List, Optional
from pydantic import BaseModel

from app.database import get_db
from app.models.reserva import Reserva
from app.models.cancha import Cancha
from app.models.usuario import Usuario
from app.schemas.reserva_schema import (
    ReservaCreate,
    ReservaResponse,
    EstadoUpdate,
    PagoCreate,
)
from app.services.auth_service import get_current_user
from app.services.permisos import complejo_efectivo, es_superadmin

router = APIRouter(prefix="/reservas", tags=["Reservas"])

COMPROBANTES_DIR = "static/comprobantes"
os.makedirs(COMPROBANTES_DIR, exist_ok=True)

EXTENSIONES_COMPROBANTE = {".jpg", ".jpeg", ".png", ".webp", ".pdf"}
MAX_COMPROBANTE_BYTES = 5 * 1024 * 1024

ESTADOS_OCUPAN = ["pendiente", "confirmada", "completada"]

ROLES_STAFF = {"admin", "administrador", "superadmin", "dueño_cancha", "admin_complejo"}


class CancelarReservaSchema(BaseModel):
    motivo: str = "Cancelado por el usuario"


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def _es_staff(usuario: Usuario) -> bool:
    return (getattr(usuario, "rol", "") or "").lower() in ROLES_STAFF


def _con_relaciones(db: Session):
    """Trae cancha + complejo + usuario en la misma consulta.

    El `joinedload(Cancha.complejo)` es lo que permite que la app reciba el
    nombre del complejo dentro del objeto `cancha` de la reserva.
    """
    return db.query(Reserva).options(
        joinedload(Reserva.cancha).joinedload(Cancha.complejo),
        joinedload(Reserva.usuario),
    )


def _filtrar_reservas_por_complejo(query, usuario: Usuario, complejo_id_query: Optional[int]):
    """
    Aplica filtro por complejo solo a usuarios staff.
    - Clientes → no se filtran aquí (ya se filtran por usuario_id).
    - Superadmin libre → respeta el query.
    - Admin con complejo → fuerza el suyo.
    """
    if not _es_staff(usuario):
        return query

    cid = complejo_efectivo(usuario, complejo_id_query)
    if cid is not None:
        query = query.join(Cancha, Reserva.cancha_id == Cancha.id).filter(
            Cancha.complejo_id == cid
        )
    return query


def _verificar_reserva_en_complejo(reserva: Reserva, usuario: Usuario) -> None:
    """Si el usuario es admin con complejo, la reserva debe ser de su complejo."""
    if not _es_staff(usuario):
        return
    if es_superadmin(usuario) and usuario.complejo_id is None:
        return
    if reserva.cancha is None or reserva.cancha.complejo_id != usuario.complejo_id:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Esta reserva no pertenece a tu complejo",
        )


def _cerrar_vencidas(db: Session) -> None:
    ahora = datetime.now()
    actualizadas = db.query(Reserva).filter(
        func.lower(Reserva.estado) == "confirmada",
        or_(
            Reserva.fecha_reserva < ahora.date(),
            and_(
                Reserva.fecha_reserva == ahora.date(),
                Reserva.hora_fin <= ahora.time(),
            ),
        ),
    ).update({"estado": "completada"}, synchronize_session=False)

    if actualizadas:
        db.commit()


def _obtener_reserva(db: Session, reserva_id: int) -> Reserva:
    reserva = _con_relaciones(db).filter(Reserva.id == reserva_id).first()
    if not reserva:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Reserva no encontrada",
        )
    return reserva


def _verificar_acceso(reserva: Reserva, usuario: Usuario) -> None:
    """Un cliente solo puede tocar sus propias reservas."""
    if not _es_staff(usuario) and reserva.usuario_id != usuario.id:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="No puedes modificar una reserva de otro usuario",
        )


def _exigir_staff(usuario: Usuario) -> None:
    if not _es_staff(usuario):
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Solo el administrador puede realizar esta acción",
        )


# ---------------------------------------------------------------------------
# 0. Listar todas las reservas
# ---------------------------------------------------------------------------

@router.get("/", response_model=List[ReservaResponse])
@router.get("", response_model=List[ReservaResponse])
def obtener_todas_las_reservas(
    estado: Optional[str] = None,
    complejo_id: Optional[int] = None,
    db: Session = Depends(get_db),
    current_user: Usuario = Depends(get_current_user),
):
    _cerrar_vencidas(db)
    query = _con_relaciones(db)

    if not _es_staff(current_user):
        query = query.filter(Reserva.usuario_id == current_user.id)
    else:
        query = _filtrar_reservas_por_complejo(query, current_user, complejo_id)

    if estado:
        query = query.filter(func.lower(Reserva.estado) == estado.strip().lower())

    return query.order_by(
        Reserva.fecha_reserva.desc(), Reserva.hora_inicio.desc()
    ).all()


# ---------------------------------------------------------------------------
# 1. Crear reserva
# ---------------------------------------------------------------------------

@router.post("/", response_model=ReservaResponse, status_code=status.HTTP_201_CREATED)
@router.post("", response_model=ReservaResponse, status_code=status.HTTP_201_CREATED)
def crear_reserva(
    reserva: ReservaCreate,
    db: Session = Depends(get_db),
    current_user: Usuario = Depends(get_current_user),
):
    ahora = datetime.now()

    if reserva.hora_fin <= reserva.hora_inicio:
        raise HTTPException(400, "La hora de fin debe ser posterior a la hora de inicio")

    if reserva.fecha_reserva < ahora.date():
        raise HTTPException(400, "No puedes crear una reserva en una fecha pasada")

    if reserva.fecha_reserva == ahora.date() and reserva.hora_inicio <= ahora.time():
        raise HTTPException(400, "Esa hora ya pasó. Elige un horario posterior.")

    cancha = db.query(Cancha).filter(Cancha.id == reserva.cancha_id).first()
    if not cancha:
        raise HTTPException(404, "Cancha no encontrada")

    if _es_staff(current_user) and not (es_superadmin(current_user) and current_user.complejo_id is None):
        if cancha.complejo_id != current_user.complejo_id:
            raise HTTPException(403, "Esta cancha no pertenece a tu complejo")

    conflicto = db.query(Reserva).filter(
        Reserva.cancha_id == reserva.cancha_id,
        Reserva.fecha_reserva == reserva.fecha_reserva,
        func.lower(Reserva.estado).in_(ESTADOS_OCUPAN),
        Reserva.hora_inicio < reserva.hora_fin,
        Reserva.hora_fin > reserva.hora_inicio,
    ).first()

    if conflicto:
        raise HTTPException(400, "Ese horario ya no está disponible")

    duracion_horas = (
        datetime.combine(ahora.date(), reserva.hora_fin) -
        datetime.combine(ahora.date(), reserva.hora_inicio)
    ).total_seconds() / 3600

    es_hora_pico = reserva.hora_inicio >= time_type(18, 0)
    precio_unitario = (
        cancha.precio_hora_pico
        if (es_hora_pico and cancha.precio_hora_pico)
        else cancha.precio_hora
    )
    precio_total = round(float(precio_unitario) * duracion_horas, 2)

    metodo_pago = reserva.metodo_pago or "transferencia"
    pagado = metodo_pago == "tarjeta"
    estado_inicial = "confirmada" if pagado else "pendiente"

    nueva_reserva = Reserva(
        cancha_id=reserva.cancha_id,
        usuario_id=current_user.id,
        fecha_reserva=reserva.fecha_reserva,
        hora_inicio=reserva.hora_inicio,
        hora_fin=reserva.hora_fin,
        precio_total=precio_total,
        notas=reserva.notas,
        metodo_pago=metodo_pago,
        pagado=pagado,
        estado=estado_inicial,
    )

    db.add(nueva_reserva)
    try:
        db.commit()
    except IntegrityError:
        db.rollback()
        raise HTTPException(400, "Ese horario ya no está disponible")

    db.refresh(nueva_reserva)
    return _obtener_reserva(db, nueva_reserva.id)


# ---------------------------------------------------------------------------
# 2. Reservas activas
# ---------------------------------------------------------------------------

@router.get("/mis-reservas", response_model=List[ReservaResponse])
def mis_reservas_activas(
    db: Session = Depends(get_db),
    current_user: Usuario = Depends(get_current_user),
):
    _cerrar_vencidas(db)
    ahora = datetime.now()

    query = _con_relaciones(db).filter(
        func.lower(Reserva.estado).in_(["pendiente", "confirmada"])
    )

    if not _es_staff(current_user):
        query = query.filter(Reserva.usuario_id == current_user.id)
    else:
        query = _filtrar_reservas_por_complejo(query, current_user, None)

    return query.filter(
        or_(
            Reserva.fecha_reserva > ahora.date(),
            and_(
                Reserva.fecha_reserva == ahora.date(),
                Reserva.hora_fin > ahora.time(),
            ),
        )
    ).order_by(Reserva.fecha_reserva.asc(), Reserva.hora_inicio.asc()).all()


# ---------------------------------------------------------------------------
# 3. Historial
# ---------------------------------------------------------------------------

@router.get("/historial", response_model=List[ReservaResponse])
def historial_reservas(
    db: Session = Depends(get_db),
    current_user: Usuario = Depends(get_current_user),
):
    _cerrar_vencidas(db)
    ahora = datetime.now()

    query = _con_relaciones(db)

    if not _es_staff(current_user):
        query = query.filter(Reserva.usuario_id == current_user.id)
    else:
        query = _filtrar_reservas_por_complejo(query, current_user, None)

    return query.filter(
        or_(
            func.lower(Reserva.estado).in_(["cancelada", "rechazada", "completada"]),
            Reserva.fecha_reserva < ahora.date(),
            and_(
                Reserva.fecha_reserva == ahora.date(),
                Reserva.hora_fin <= ahora.time(),
            ),
        )
    ).order_by(Reserva.fecha_reserva.desc(), Reserva.hora_inicio.desc()).all()


# ---------------------------------------------------------------------------
# 4. Reservas pendientes
# ---------------------------------------------------------------------------

@router.get("/pendientes", response_model=List[ReservaResponse])
def reservas_pendientes(
    db: Session = Depends(get_db),
    current_user: Usuario = Depends(get_current_user),
):
    _exigir_staff(current_user)
    _cerrar_vencidas(db)

    query = _con_relaciones(db).filter(
        func.lower(Reserva.estado) == "pendiente"
    )
    query = _filtrar_reservas_por_complejo(query, current_user, None)

    return query.order_by(Reserva.fecha_reserva.asc(), Reserva.hora_inicio.asc()).all()


# ---------------------------------------------------------------------------
# 5. Disponibilidad pública
# ---------------------------------------------------------------------------

@router.get("/disponibilidad")
def consultar_disponibilidad(
    cancha_id: int,
    fecha: str,
    db: Session = Depends(get_db),
):
    try:
        fecha_obj = datetime.strptime(fecha, "%Y-%m-%d").date()
    except ValueError:
        raise HTTPException(400, "La fecha debe tener el formato YYYY-MM-DD")

    ahora = datetime.now()

    reservas = db.query(Reserva).filter(
        Reserva.cancha_id == cancha_id,
        Reserva.fecha_reserva == fecha_obj,
        func.lower(Reserva.estado).in_(ESTADOS_OCUPAN),
    ).all()

    horarios_ocupados = [
        {"hora_inicio": str(r.hora_inicio), "hora_fin": str(r.hora_fin), "motivo": "reservado"}
        for r in reservas
    ]

    if fecha_obj == ahora.date():
        horarios_ocupados.append({
            "hora_inicio": "00:00:00",
            "hora_fin": ahora.strftime("%H:%M:%S"),
            "motivo": "tiempo_transcurrido",
        })

    return {
        "cancha_id": cancha_id,
        "fecha": fecha,
        "horarios_ocupados": horarios_ocupados,
    }


# ---------------------------------------------------------------------------
# 6. Subir comprobante
# ---------------------------------------------------------------------------

@router.post("/{reserva_id}/comprobante")
async def subir_comprobante(
    reserva_id: int,
    comprobante: UploadFile = File(...),
    db: Session = Depends(get_db),
    current_user: Usuario = Depends(get_current_user),
):
    reserva = _obtener_reserva(db, reserva_id)
    _verificar_acceso(reserva, current_user)

    extension = os.path.splitext(comprobante.filename or "")[1].lower()
    if extension not in EXTENSIONES_COMPROBANTE:
        raise HTTPException(400, "El comprobante debe ser imagen o PDF")

    contenido = await comprobante.read()
    if len(contenido) > MAX_COMPROBANTE_BYTES:
        raise HTTPException(400, "El comprobante no puede pesar más de 5 MB")
    if not contenido:
        raise HTTPException(400, "El archivo llegó vacío")

    nombre_archivo = f"reserva_{reserva.id}{extension}"
    ruta = os.path.join(COMPROBANTES_DIR, nombre_archivo)
    with open(ruta, "wb") as destino:
        destino.write(contenido)

    reserva.comprobante_url = f"/{COMPROBANTES_DIR}/{nombre_archivo}"
    reserva.metodo_pago = reserva.metodo_pago or "transferencia"
    if (reserva.estado or "").lower() not in ["confirmada", "completada"]:
        reserva.estado = "pendiente"

    db.commit()
    db.refresh(reserva)

    return {
        "comprobante_url": reserva.comprobante_url,
        "estado": reserva.estado,
        "reserva_id": reserva.id,
    }


# ---------------------------------------------------------------------------
# 7. Registrar pago con tarjeta
# ---------------------------------------------------------------------------

@router.post("/{reserva_id}/pago")
def registrar_pago(
    reserva_id: int,
    datos: PagoCreate,
    db: Session = Depends(get_db),
    current_user: Usuario = Depends(get_current_user),
):
    reserva = _obtener_reserva(db, reserva_id)
    _verificar_acceso(reserva, current_user)

    metodo = (datos.metodo_pago or "tarjeta").strip().lower()
    reserva.metodo_pago = metodo

    if datos.referencia:
        reserva.referencia_pago = datos.referencia[:50]

    if metodo == "tarjeta":
        reserva.pagado = True
        if (reserva.estado or "").lower() not in ["cancelada", "rechazada", "completada"]:
            reserva.estado = "confirmada"

    db.commit()
    db.refresh(reserva)

    return {
        "mensaje": "Pago registrado",
        "reserva_id": reserva.id,
        "estado": reserva.estado,
        "pagado": reserva.pagado,
    }


# ---------------------------------------------------------------------------
# 8. Cambiar estado (aprobar/rechazar)
# ---------------------------------------------------------------------------

@router.put("/{reserva_id}/estado", response_model=ReservaResponse)
def cambiar_estado_reserva(
    reserva_id: int,
    datos: EstadoUpdate,
    db: Session = Depends(get_db),
    current_user: Usuario = Depends(get_current_user),
):
    _exigir_staff(current_user)
    reserva = _obtener_reserva(db, reserva_id)
    _verificar_reserva_en_complejo(reserva, current_user)

    reserva.estado = datos.estado

    if datos.estado in ["cancelada", "rechazada"]:
        reserva.fecha_cancelacion = datetime.now()
        reserva.motivo_cancelacion = datos.motivo or (
            "Comprobante no válido" if datos.estado == "rechazada"
            else "Cancelado por el administrador"
        )
        reserva.pagado = False
    else:
        reserva.fecha_cancelacion = None
        reserva.motivo_cancelacion = None
        if datos.estado in ["confirmada", "completada"]:
            reserva.pagado = True

    db.commit()
    db.refresh(reserva)
    return _obtener_reserva(db, reserva.id)


# ---------------------------------------------------------------------------
# 9. Cancelar reserva
# ---------------------------------------------------------------------------

@router.put("/{reserva_id}/cancelar")
def cancelar_reserva(
    reserva_id: int,
    motivo: Optional[str] = None,
    datos: Optional[CancelarReservaSchema] = None,
    db: Session = Depends(get_db),
    current_user: Usuario = Depends(get_current_user),
):
    reserva = _obtener_reserva(db, reserva_id)
    _verificar_acceso(reserva, current_user)
    _verificar_reserva_en_complejo(reserva, current_user)

    estado_actual = (reserva.estado or "").lower()
    if estado_actual == "cancelada":
        raise HTTPException(400, "La reserva ya se encuentra cancelada")
    if estado_actual == "completada":
        raise HTTPException(400, "No se puede cancelar una reserva que ya se jugó")

    motivo_final = "Cancelado por el usuario"
    if motivo and motivo.strip():
        motivo_final = motivo.strip()
    elif datos and datos.motivo:
        motivo_final = datos.motivo

    reserva.estado = "cancelada"
    reserva.pagado = False
    reserva.fecha_cancelacion = datetime.now()
    reserva.motivo_cancelacion = motivo_final

    db.commit()
    db.refresh(reserva)

    return {
        "mensaje": "Reserva cancelada exitosamente",
        "reserva_id": reserva.id,
        "estado": reserva.estado,
    }


# ---------------------------------------------------------------------------
# 10. Confirmar reserva
# ---------------------------------------------------------------------------

@router.put("/{reserva_id}/confirmar", response_model=ReservaResponse)
def confirmar_reserva(
    reserva_id: int,
    db: Session = Depends(get_db),
    current_user: Usuario = Depends(get_current_user),
):
    _exigir_staff(current_user)
    reserva = _obtener_reserva(db, reserva_id)
    _verificar_reserva_en_complejo(reserva, current_user)

    reserva.estado = "confirmada"
    reserva.pagado = True
    reserva.fecha_cancelacion = None
    reserva.motivo_cancelacion = None

    db.commit()
    db.refresh(reserva)
    return _obtener_reserva(db, reserva.id)