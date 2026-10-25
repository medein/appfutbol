from fastapi import APIRouter, Depends, Query
from sqlalchemy.orm import Session
from typing import Optional
from sqlalchemy import func, extract
from datetime import date, timedelta

from app.database import get_db
from app.models.reserva import Reserva
from app.models.cancha import Cancha
from app.models.usuario import Usuario
from app.services.auth_service import get_current_user, requiere_rol
from app.services.permisos import complejo_efectivo

router = APIRouter(prefix="/dashboard", tags=["Dashboard Admin"])

ROLES_ADMIN = ("admin", "dueño_cancha", "administrador", "admin_complejo")


def _filtrar_por_complejo(q, complejo_id, usuario):
    """
    Aplica el filtro por complejo según el usuario.
    - superadmin libre → filtra por lo que llegue en el query (o nada).
    - admin con complejo → fuerza SU complejo.
    """
    cid = complejo_efectivo(usuario, complejo_id)
    if cid is not None:
        q = q.filter(Cancha.complejo_id == cid)
    return q


# ---------------------------------------------------------------------------
# KPIs
# ---------------------------------------------------------------------------

@router.get("/kpis", dependencies=[Depends(requiere_rol(*ROLES_ADMIN))])
def obtener_kpis(
    complejo_id: Optional[int] = Query(None),
    db: Session = Depends(get_db),
    current_user: Usuario = Depends(get_current_user),
):
    hoy = date.today()

    q = db.query(func.count(Reserva.id)).join(
        Cancha, Reserva.cancha_id == Cancha.id
    ).filter(
        Reserva.fecha_reserva == hoy,
        Reserva.estado != "cancelada",
    )
    q = _filtrar_por_complejo(q, complejo_id, current_user)
    reservas_hoy = q.scalar() or 0

    q = db.query(func.sum(Reserva.precio_total)).join(
        Cancha, Reserva.cancha_id == Cancha.id
    ).filter(
        extract('month', Reserva.fecha_reserva) == hoy.month,
        extract('year', Reserva.fecha_reserva) == hoy.year,
        Reserva.estado.in_(["confirmada", "completada"]),
    )
    q = _filtrar_por_complejo(q, complejo_id, current_user)
    ingresos_mes = q.scalar() or 0

    q = db.query(func.count(Cancha.id)).filter(Cancha.activa == True)
    q = _filtrar_por_complejo(q, complejo_id, current_user)
    total_canchas = q.scalar() or 0

    q = db.query(func.count(Reserva.id)).join(
        Cancha, Reserva.cancha_id == Cancha.id
    ).filter(Reserva.estado == "pendiente")
    q = _filtrar_por_complejo(q, complejo_id, current_user)
    reservas_pendientes = q.scalar() or 0

    return {
        "reservas_hoy": reservas_hoy,
        "ingresos_mes": float(ingresos_mes),
        "total_canchas": total_canchas,
        "reservas_pendientes": reservas_pendientes,
    }


# ---------------------------------------------------------------------------
# Ocupación semanal
# ---------------------------------------------------------------------------

@router.get("/ocupacion-semanal", dependencies=[Depends(requiere_rol(*ROLES_ADMIN))])
def ocupacion_semanal(
    complejo_id: Optional[int] = Query(None),
    db: Session = Depends(get_db),
    current_user: Usuario = Depends(get_current_user),
):
    hoy = date.today()
    inicio = hoy - timedelta(days=hoy.weekday())
    resultados = []
    for i in range(7):
        dia = inicio + timedelta(days=i)
        q = db.query(func.count(Reserva.id)).join(
            Cancha, Reserva.cancha_id == Cancha.id
        ).filter(
            Reserva.fecha_reserva == dia,
            Reserva.estado.in_(["pendiente", "confirmada", "completada"]),
        )
        q = _filtrar_por_complejo(q, complejo_id, current_user)
        resultados.append({
            "dia": dia.strftime("%A"),
            "fecha": str(dia),
            "reservas": q.scalar() or 0,
        })
    return resultados


# ---------------------------------------------------------------------------
# Reservas recientes
# ---------------------------------------------------------------------------

@router.get("/reservas-recientes", dependencies=[Depends(requiere_rol(*ROLES_ADMIN))])
def reservas_recientes(
    limit: int = Query(10),
    complejo_id: Optional[int] = Query(None),
    db: Session = Depends(get_db),
    current_user: Usuario = Depends(get_current_user),
):
    q = db.query(Reserva).join(
        Cancha, Reserva.cancha_id == Cancha.id
    ).filter(Reserva.estado != "cancelada")
    q = _filtrar_por_complejo(q, complejo_id, current_user)
    return q.order_by(Reserva.id.desc()).limit(limit).all()


# ---------------------------------------------------------------------------
# Ranking canchas
# ---------------------------------------------------------------------------

@router.get("/ranking-canchas", dependencies=[Depends(requiere_rol(*ROLES_ADMIN))])
def ranking_canchas(
    complejo_id: Optional[int] = Query(None),
    db: Session = Depends(get_db),
    current_user: Usuario = Depends(get_current_user),
):
    q = db.query(
        Cancha.nombre,
        func.count(Reserva.id).label("total_reservas"),
        func.sum(Reserva.precio_total).label("ingresos_generados"),
    ).join(Reserva, Reserva.cancha_id == Cancha.id).filter(
        Reserva.estado != "cancelada"
    )
    q = _filtrar_por_complejo(q, complejo_id, current_user)
    resultado = q.group_by(Cancha.id, Cancha.nombre).order_by(
        func.count(Reserva.id).desc()
    ).all()
    return [
        {"cancha": r[0], "total_reservas": r[1], "ingresos": float(r[2] or 0)}
        for r in resultado
    ]


# ---------------------------------------------------------------------------
# Recaudo
# ---------------------------------------------------------------------------

@router.get("/recaudo", dependencies=[Depends(requiere_rol(*ROLES_ADMIN))])
def recaudo_por_mes(
    mes: Optional[int] = Query(None, ge=1, le=12),
    anio: Optional[int] = Query(None),
    complejo_id: Optional[int] = Query(None),
    db: Session = Depends(get_db),
    current_user: Usuario = Depends(get_current_user),
):
    hoy = date.today()
    mes = mes or hoy.month
    anio = anio or hoy.year
    q = db.query(func.sum(Reserva.precio_total)).join(
        Cancha, Reserva.cancha_id == Cancha.id
    ).filter(
        extract('month', Reserva.fecha_reserva) == mes,
        extract('year', Reserva.fecha_reserva) == anio,
        Reserva.estado.in_(["confirmada", "completada"]),
    )
    q = _filtrar_por_complejo(q, complejo_id, current_user)
    return {"mes": mes, "anio": anio, "total": float(q.scalar() or 0)}


@router.get("/recaudo-total", dependencies=[Depends(requiere_rol(*ROLES_ADMIN))])
def recaudo_total(
    complejo_id: Optional[int] = Query(None),
    db: Session = Depends(get_db),
    current_user: Usuario = Depends(get_current_user),
):
    q = db.query(func.sum(Reserva.precio_total)).join(
        Cancha, Reserva.cancha_id == Cancha.id
    ).filter(Reserva.estado.in_(["confirmada", "completada"]))
    q = _filtrar_por_complejo(q, complejo_id, current_user)
    return {"total": float(q.scalar() or 0)}


# ---------------------------------------------------------------------------
# Clientes
# ---------------------------------------------------------------------------

@router.get("/clientes", dependencies=[Depends(requiere_rol(*ROLES_ADMIN))])
def resumen_clientes(
    mes: Optional[int] = Query(None, ge=1, le=12),
    anio: Optional[int] = Query(None),
    complejo_id: Optional[int] = Query(None),
    db: Session = Depends(get_db),
    current_user: Usuario = Depends(get_current_user),
):
    q = db.query(
        Usuario.id,
        Usuario.nombre,
        Usuario.email,
        func.count(Reserva.id).label("total_reservas"),
        func.sum(Reserva.precio_total).label("total_gastado"),
    ).join(Reserva, Reserva.usuario_id == Usuario.id).join(
        Cancha, Reserva.cancha_id == Cancha.id
    ).filter(Reserva.estado != "cancelada")

    if mes is not None and anio is not None:
        q = q.filter(
            extract('month', Reserva.fecha_reserva) == mes,
            extract('year', Reserva.fecha_reserva) == anio,
        )

    q = _filtrar_por_complejo(q, complejo_id, current_user)

    resultado = q.group_by(Usuario.id, Usuario.nombre, Usuario.email).order_by(
        func.count(Reserva.id).desc()
    ).all()

    return [
        {
            "id": r[0],
            "nombre": r[1],
            "email": r[2],
            "total_reservas": r[3],
            "total_gastado": float(r[4] or 0),
        }
        for r in resultado
    ]