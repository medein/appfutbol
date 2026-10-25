"""
app/routers/complejos.py
"""
import math
import os
import uuid
from datetime import time, timedelta
from typing import Optional

from fastapi import APIRouter, Depends, HTTPException, Query, UploadFile, File
from sqlalchemy import func
from sqlalchemy.orm import Session

from app.config import settings
from app.database import get_db
from app.models.cancha import Cancha
from app.models.complejo import Complejo
from app.models.usuario import Usuario
from app.services.auth_service import get_current_user
from app.schemas.complejo import ComplejoCreate, ComplejoUpdate

router = APIRouter(prefix="/complejos", tags=["Complejos"])


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def _distancia_km(lat1, lng1, lat2, lng2) -> float:
    r = 6371.0
    p1, p2 = math.radians(float(lat1)), math.radians(float(lat2))
    dp = p2 - p1
    dl = math.radians(float(lng2) - float(lng1))
    a = math.sin(dp / 2) ** 2 + math.cos(p1) * math.cos(p2) * math.sin(dl / 2) ** 2
    return round(2 * r * math.asin(math.sqrt(a)), 1)


def _num(valor):
    return float(valor) if valor is not None else None


def _hora(valor) -> Optional[str]:
    if isinstance(valor, timedelta):
        total = int(valor.total_seconds())
        return f"{(total // 3600) % 24:02d}:{(total % 3600) // 60:02d}"
    if isinstance(valor, time):
        return valor.strftime("%H:%M")
    return None


def _require_superadmin(current_user: Usuario = Depends(get_current_user)) -> Usuario:
    if (current_user.rol or "").lower() not in ("superadmin", "administrador"):
        raise HTTPException(
            status_code=403,
            detail="Solo la gerencia puede realizar esta acción",
        )
    return current_user


def _serializar_complejo(c: Complejo, db: Session) -> dict:
    total = (
        db.query(func.count(Cancha.id))
        .filter(Cancha.complejo_id == c.id, Cancha.activa == 1)
        .scalar() or 0
    )
    precio_min = (
        db.query(func.min(Cancha.precio_hora))
        .filter(Cancha.complejo_id == c.id, Cancha.activa == 1)
        .scalar()
    )
    return {
        "id": c.id,
        "nombre": c.nombre,
        "direccion": getattr(c, "direccion", None),
        "telefono": getattr(c, "telefono", None),
        "imagen_url": getattr(c, "imagen_url", None),
        "horario_apertura": _hora(getattr(c, "horario_apertura", None)),
        "horario_cierre": _hora(getattr(c, "horario_cierre", None)),
        "calificacion": _num(getattr(c, "calificacion_promedio", None)),
        "latitud": _num(getattr(c, "latitud", None)),
        "longitud": _num(getattr(c, "longitud", None)),
        "total_canchas": int(total),
        "precio_desde": _num(precio_min),
        "distancia_km": None,
        "activo": bool(getattr(c, "activo", True)),
    }


# ---------------------------------------------------------------------------
# GET — listar
# ---------------------------------------------------------------------------

@router.get("/")
@router.get("")
def listar_complejos(
    lat: Optional[float] = Query(None, description="Latitud del usuario"),
    lng: Optional[float] = Query(None, description="Longitud del usuario"),
    latitud: Optional[float] = Query(None, description="Alias de lat"),
    longitud: Optional[float] = Query(None, description="Alias de lng"),
    incluir_inactivos: bool = Query(
        False, description="Si true, incluye también los complejos desactivados"
    ),
    db: Session = Depends(get_db),
    current_user: Usuario = Depends(get_current_user),
):
    if lat is None:
        lat = latitud
    if lng is None:
        lng = longitud

    q = db.query(Complejo)

    # Solo filtrar por activo si NO se piden los inactivos.
    if not incluir_inactivos:
        for nombre_col in ("activo", "activa"):
            col = getattr(Complejo, nombre_col, None)
            if col is not None:
                q = q.filter(col == 1)
                break

    complejos = q.all()

    resumen = {
        fila.complejo_id: (fila.total, fila.desde)
        for fila in db.query(
            Cancha.complejo_id,
            func.count(Cancha.id).label("total"),
            func.min(Cancha.precio_hora).label("desde"),
        )
        .filter(Cancha.activa == 1)
        .group_by(Cancha.complejo_id)
        .all()
    }

    fotos_cancha = {}
    for fila in (
        db.query(Cancha.complejo_id, Cancha.imagen_url)
        .filter(Cancha.activa == 1, Cancha.imagen_url.isnot(None))
        .order_by(Cancha.id)
        .all()
    ):
        fotos_cancha.setdefault(fila.complejo_id, fila.imagen_url)

    resultado = []
    for c in complejos:
        total, desde = resumen.get(c.id, (0, None))
        lat_c = getattr(c, "latitud", None)
        lng_c = getattr(c, "longitud", None)
        distancia = None
        if None not in (lat, lng, lat_c, lng_c):
            distancia = _distancia_km(lat, lng, lat_c, lng_c)

        imagen = getattr(c, "imagen_url", None) or fotos_cancha.get(c.id)

        resultado.append({
            "id": c.id,
            "nombre": c.nombre,
            "direccion": getattr(c, "direccion", None),
            "telefono": getattr(c, "telefono", None),
            "imagen_url": imagen,
            "horario_apertura": _hora(getattr(c, "horario_apertura", None)),
            "horario_cierre": _hora(getattr(c, "horario_cierre", None)),
            "calificacion": _num(getattr(c, "calificacion_promedio", None)),
            "latitud": _num(lat_c),
            "longitud": _num(lng_c),
            "total_canchas": int(total),
            "precio_desde": _num(desde),
            "distancia_km": distancia,
            "activo": bool(getattr(c, "activo", True)),
        })

    if lat is not None and lng is not None:
        resultado.sort(key=lambda x: (x["distancia_km"] is None, x["distancia_km"] or 0))
    else:
        resultado.sort(key=lambda x: (x["nombre"] or "").lower())

    return resultado


# ---------------------------------------------------------------------------
# POST — crear
# ---------------------------------------------------------------------------

@router.post("", status_code=201)
def crear_complejo(
    datos: ComplejoCreate,
    db: Session = Depends(get_db),
    _: Usuario = Depends(_require_superadmin),
):
    nuevo = Complejo(
        nombre=datos.nombre,
        direccion=datos.direccion,
        telefono=datos.telefono,
        latitud=datos.latitud,
        longitud=datos.longitud,
        horario_apertura=datos.horario_apertura or "07:00",
        horario_cierre=datos.horario_cierre or "23:00",
        calificacion_promedio=datos.calificacion_promedio or 0.0,
        activo=datos.activo,
        imagen_url=datos.imagen_url,
    )
    db.add(nuevo)
    db.commit()
    db.refresh(nuevo)
    return _serializar_complejo(nuevo, db)


# ---------------------------------------------------------------------------
# PUT — actualizar
# ---------------------------------------------------------------------------

@router.put("/{complejo_id}")
def actualizar_complejo(
    complejo_id: int,
    datos: ComplejoUpdate,
    db: Session = Depends(get_db),
    _: Usuario = Depends(_require_superadmin),
):
    complejo = db.query(Complejo).filter(Complejo.id == complejo_id).first()
    if not complejo:
        raise HTTPException(status_code=404, detail="Complejo no encontrado")

    for campo, valor in datos.dict(exclude_unset=True).items():
        if valor is not None:
            setattr(complejo, campo, valor)

    db.commit()
    db.refresh(complejo)
    return _serializar_complejo(complejo, db)


# ---------------------------------------------------------------------------
# PUT — reactivar complejo (deshacer el soft delete)
# ---------------------------------------------------------------------------

@router.put("/{complejo_id}/reactivar")
def reactivar_complejo(
    complejo_id: int,
    db: Session = Depends(get_db),
    _: Usuario = Depends(_require_superadmin),
):
    complejo = db.query(Complejo).filter(Complejo.id == complejo_id).first()
    if not complejo:
        raise HTTPException(status_code=404, detail="Complejo no encontrado")

    complejo.activo = True
    db.commit()
    db.refresh(complejo)
    return _serializar_complejo(complejo, db)


# ---------------------------------------------------------------------------
# DELETE — desactivar (soft delete)
# ---------------------------------------------------------------------------

@router.delete("/{complejo_id}", status_code=204)
def eliminar_complejo(
    complejo_id: int,
    db: Session = Depends(get_db),
    _: Usuario = Depends(_require_superadmin),
):
    complejo = db.query(Complejo).filter(Complejo.id == complejo_id).first()
    if not complejo:
        raise HTTPException(status_code=404, detail="Complejo no encontrado")

    complejo.activo = False
    db.commit()
    return None


# ---------------------------------------------------------------------------
# POST — subir imagen
# ---------------------------------------------------------------------------

@router.post("/{complejo_id}/imagen")
async def subir_imagen_complejo(
    complejo_id: int,
    archivo: UploadFile = File(...),
    db: Session = Depends(get_db),
    _: Usuario = Depends(_require_superadmin),
):
    complejo = db.query(Complejo).filter(Complejo.id == complejo_id).first()
    if not complejo:
        raise HTTPException(status_code=404, detail="Complejo no encontrado")

    extensiones_validas = {".jpg", ".jpeg", ".png", ".webp"}
    extension = os.path.splitext(archivo.filename or "")[1].lower()
    if extension not in extensiones_validas:
        raise HTTPException(
            status_code=400,
            detail="Formato de imagen no válido. Usa JPG, PNG o WEBP.",
        )

    carpeta = os.path.join("static", "complejos")
    os.makedirs(carpeta, exist_ok=True)

    nombre_archivo = f"complejo_{complejo_id}_{uuid.uuid4().hex[:8]}{extension}"
    ruta_completa = os.path.join(carpeta, nombre_archivo)

    contenido = await archivo.read()
    with open(ruta_completa, "wb") as f:
        f.write(contenido)

    # URL relativa: el frontend la convierte a absoluta con urlAbsoluta().
    complejo.imagen_url = f"/static/complejos/{nombre_archivo}"
    db.commit()
    db.refresh(complejo)

    return {
        "id": complejo.id,
        "imagen_url": complejo.imagen_url,
    }