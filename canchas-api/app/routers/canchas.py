from fastapi import APIRouter, Depends, HTTPException, UploadFile, File
import os
import uuid
from app.config import settings
from sqlalchemy.orm import Session
from sqlalchemy import or_, func
from datetime import datetime
from typing import Optional, List

from app.database import get_db
from app.models.cancha import Cancha
from app.models.reserva import Reserva
from app.models.usuario import Usuario
from app.schemas.cancha_schema import CanchaCreate, CanchaUpdate, CanchaResponse
from app.services.auth_service import requiere_rol, get_current_user
from app.services.permisos import complejo_efectivo, es_superadmin

router = APIRouter(prefix="/canchas", tags=["Canchas"])

ROLES_ADMIN = ("admin", "dueño_cancha", "administrador", "admin_complejo")


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def _verificar_cancha_del_usuario(cancha: Cancha, usuario: Usuario) -> None:
    """Un admin de complejo solo puede tocar las canchas de SU complejo."""
    if es_superadmin(usuario) and usuario.complejo_id is None:
        return
    if cancha.complejo_id != usuario.complejo_id:
        raise HTTPException(
            status_code=403,
            detail="Esta cancha no pertenece a tu complejo",
        )


# ---------------------------------------------------------------------------
# Listar canchas
# ---------------------------------------------------------------------------

@router.get("/", response_model=List[CanchaResponse])
@router.get("", response_model=List[CanchaResponse])
def listar_canchas(
    tipo_deporte: Optional[str] = None,
    complejo_id: Optional[int] = None,
    incluir_inactivas: bool = False,
    db: Session = Depends(get_db),
    current_user: Usuario = Depends(get_current_user),
):
    """
    Lista canchas. Si el usuario es admin con complejo asignado, se fuerza
    a ese complejo aunque mande otro en el query.
    """
    query = db.query(Cancha)

    if not incluir_inactivas:
        query = query.filter(
            or_(
                Cancha.activa == True,
                Cancha.activa == 1,
                Cancha.activa.is_(None),
            )
        )

    if tipo_deporte:
        query = query.filter(Cancha.tipo_deporte == tipo_deporte)

    # Filtro por complejo:
    #   - superadmin libre → respeta el query ?complejo_id=X
    #   - admin con complejo → fuerza el suyo
    cid = complejo_efectivo(current_user, complejo_id)
    if cid is not None:
        query = query.filter(Cancha.complejo_id == cid)

    return query.order_by(Cancha.id.asc()).all()


# ---------------------------------------------------------------------------
# Obtener una cancha
# ---------------------------------------------------------------------------

@router.get("/{cancha_id}", response_model=CanchaResponse)
def obtener_cancha(
    cancha_id: int,
    db: Session = Depends(get_db),
    current_user: Usuario = Depends(get_current_user),
):
    cancha = db.query(Cancha).filter(Cancha.id == cancha_id).first()
    if not cancha:
        raise HTTPException(status_code=404, detail="Cancha no encontrada")
    _verificar_cancha_del_usuario(cancha, current_user)
    return cancha


# ---------------------------------------------------------------------------
# Disponibilidad
# ---------------------------------------------------------------------------

@router.get("/{cancha_id}/disponibilidad")
def disponibilidad_de_cancha(
    cancha_id: int,
    fecha: str,
    db: Session = Depends(get_db),
    current_user: Usuario = Depends(get_current_user),
):
    try:
        fecha_obj = datetime.strptime(fecha, "%Y-%m-%d").date()
    except ValueError:
        raise HTTPException(
            status_code=400,
            detail="La fecha debe tener el formato YYYY-MM-DD",
        )

    cancha = db.query(Cancha).filter(Cancha.id == cancha_id).first()
    if not cancha:
        raise HTTPException(status_code=404, detail="Cancha no encontrada")

    _verificar_cancha_del_usuario(cancha, current_user)

    reservas = db.query(Reserva).filter(
        Reserva.cancha_id == cancha_id,
        Reserva.fecha_reserva == fecha_obj,
        func.lower(Reserva.estado).in_(["pendiente", "confirmada", "completada"]),
    ).order_by(Reserva.hora_inicio.asc()).all()

    return [
        {
            "id": r.id,
            "cancha_id": r.cancha_id,
            "fecha_reserva": str(r.fecha_reserva),
            "hora_inicio": str(r.hora_inicio),
            "hora_fin": str(r.hora_fin),
            "estado": r.estado,
        }
        for r in reservas
    ]


# ---------------------------------------------------------------------------
# Crear cancha
# ---------------------------------------------------------------------------

@router.post("/", response_model=CanchaResponse, status_code=201)
@router.post("", response_model=CanchaResponse, status_code=201)
def crear_cancha(
    cancha: CanchaCreate,
    db: Session = Depends(get_db),
    current_user: Usuario = Depends(requiere_rol(*ROLES_ADMIN)),
):
    datos = cancha.model_dump()

    if "activa" not in datos or datos["activa"] is None:
        datos["activa"] = True

    # Forzar el complejo del admin si tiene uno asignado.
    if not (es_superadmin(current_user) and current_user.complejo_id is None):
        if current_user.complejo_id is None:
            raise HTTPException(
                status_code=400,
                detail="No tienes un complejo asignado para crear canchas",
            )
        datos["complejo_id"] = current_user.complejo_id

    nueva = Cancha(**datos)
    db.add(nueva)
    db.commit()
    db.refresh(nueva)
    return nueva


# ---------------------------------------------------------------------------
# Actualizar cancha
# ---------------------------------------------------------------------------

@router.put("/{cancha_id}", response_model=CanchaResponse)
def actualizar_cancha(
    cancha_id: int,
    datos: CanchaUpdate,
    db: Session = Depends(get_db),
    current_user: Usuario = Depends(requiere_rol(*ROLES_ADMIN)),
):
    cancha = db.query(Cancha).filter(Cancha.id == cancha_id).first()
    if not cancha:
        raise HTTPException(status_code=404, detail="Cancha no encontrada")

    _verificar_cancha_del_usuario(cancha, current_user)

    cambios = datos.model_dump(exclude_unset=True)

    # Un admin de complejo no puede mover su cancha a otro complejo.
    if "complejo_id" in cambios and not (es_superadmin(current_user) and current_user.complejo_id is None):
        cambios.pop("complejo_id")

    if not cambios:
        raise HTTPException(
            status_code=400,
            detail="No enviaste ningún campo para actualizar",
        )

    for campo, valor in cambios.items():
        setattr(cancha, campo, valor)

    db.commit()
    db.refresh(cancha)
    return cancha


# ---------------------------------------------------------------------------
# Subir imagen
# ---------------------------------------------------------------------------

@router.post("/{cancha_id}/imagen", response_model=CanchaResponse)
async def subir_imagen_cancha(
    cancha_id: int,
    archivo: UploadFile = File(...),
    db: Session = Depends(get_db),
    current_user: Usuario = Depends(requiere_rol(*ROLES_ADMIN)),
):
    cancha = db.query(Cancha).filter(Cancha.id == cancha_id).first()
    if not cancha:
        raise HTTPException(status_code=404, detail="Cancha no encontrada")

    _verificar_cancha_del_usuario(cancha, current_user)

    extensiones_validas = {".jpg", ".jpeg", ".png", ".webp"}
    extension = os.path.splitext(archivo.filename or "")[1].lower()
    if extension not in extensiones_validas:
        raise HTTPException(
            status_code=400,
            detail="Formato de imagen no válido. Usa JPG, PNG o WEBP.",
        )

    carpeta = os.path.join("static", "canchas")
    os.makedirs(carpeta, exist_ok=True)

    nombre_archivo = f"cancha_{cancha_id}_{uuid.uuid4().hex[:8]}{extension}"
    ruta_completa = os.path.join(carpeta, nombre_archivo)

    contenido = await archivo.read()
    with open(ruta_completa, "wb") as f:
        f.write(contenido)

    cancha.imagen_url = f"/static/canchas/{nombre_archivo}"

    db.commit()
    db.refresh(cancha)
    return cancha


# ---------------------------------------------------------------------------
# Desactivar cancha
# ---------------------------------------------------------------------------

@router.delete("/{cancha_id}", status_code=204)
def desactivar_cancha(
    cancha_id: int,
    db: Session = Depends(get_db),
    current_user: Usuario = Depends(requiere_rol(*ROLES_ADMIN)),
):
    cancha = db.query(Cancha).filter(Cancha.id == cancha_id).first()
    if not cancha:
        raise HTTPException(status_code=404, detail="Cancha no encontrada")

    _verificar_cancha_del_usuario(cancha, current_user)

    cancha.activa = False
    db.commit()