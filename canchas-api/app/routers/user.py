import os
from datetime import datetime
from typing import Optional
from fastapi import APIRouter, Depends, HTTPException, status, UploadFile, File, Form
from sqlalchemy import func
from sqlalchemy.orm import Session
from pydantic import BaseModel, EmailStr
from passlib.context import CryptContext

from app.database import get_db
from app.models.usuario import Usuario
from app.schemas.usuario_schema import UsuarioResponse
from app.services.auth_service import get_current_user

router = APIRouter(prefix="/users", tags=["Usuarios"])

# Contexto de encriptación de contraseñas seguro
pwd_context = CryptContext(schemes=["bcrypt"], deprecated="auto")

UPLOAD_DIR = "static/profile_pictures"
os.makedirs(UPLOAD_DIR, exist_ok=True)

EXTENSIONES_FOTO = {".jpg", ".jpeg", ".png", ".webp"}
MAX_FOTO_BYTES = 5 * 1024 * 1024  # 5 MB

# Incluye todos los roles administrativos de tu base de datos
ROLES_STAFF = {"admin", "administrador", "superadmin", "dueño_cancha", "admin_complejo"}


def _es_staff(usuario: Usuario) -> bool:
    rol_actual = (getattr(usuario, "rol", "") or "").strip().lower()
    return rol_actual in ROLES_STAFF


# --- Esquema Pydantic para crear usuarios/admins desde la web ---
class UsuarioCreateAdmin(BaseModel):
    nombre: str
    email: EmailStr
    password: str
    telefono: Optional[str] = None
    rol: str = "admin_complejo"
    complejo_id: Optional[int] = None


# 1. Endpoint para LISTAR usuarios
@router.get("/", response_model=list[UsuarioResponse])
def listar_usuarios(
    db: Session = Depends(get_db),
    current_user: Usuario = Depends(get_current_user)
):
    if not _es_staff(current_user):
        raise HTTPException(status_code=403, detail="No tienes permisos para ver los usuarios")
    
    return db.query(Usuario).all()


# 2. Endpoint para CREAR usuarios/admins desde la web
# 2. Endpoint para CREAR usuarios desde la web
@router.post("/", response_model=UsuarioResponse, status_code=status.HTTP_201_CREATED)
def crear_usuario_admin(
    datos: UsuarioCreateAdmin,
    db: Session = Depends(get_db),
    current_user: Usuario = Depends(get_current_user)
):
    if not _es_staff(current_user):
        raise HTTPException(status_code=403, detail="No tienes permisos para crear usuarios")

    rol_creador = (getattr(current_user, "rol", "") or "").strip().lower()
    rol_nuevo = (datos.rol or "").strip().lower()

    # Si NO es superadmin, solo se le permite crear usuarios con rol 'cliente'
    if rol_creador != "superadmin" and rol_nuevo != "cliente":
        raise HTTPException(
            status_code=403, 
            detail="Solo un superadmin puede crear cuentas administrativas. Tu rol solo permite crear clientes."
        )

    # Verificar si el correo ya existe
    existe = db.query(Usuario).filter(func.lower(Usuario.email) == datos.email.lower()).first()
    if existe:
        raise HTTPException(status_code=400, detail="El correo ya se encuentra registrado")

    nuevo_usuario = Usuario(
        nombre=datos.nombre,
        email=datos.email.lower(),
        password_hash=pwd_context.hash(datos.password),
        telefono=datos.telefono,
        rol=rol_nuevo,
        complejo_id=datos.complejo_id if rol_creador == "superadmin" else getattr(current_user, "complejo_id", None)
    )

    db.add(nuevo_usuario)
    db.commit()
    db.refresh(nuevo_usuario)
    return nuevo_usuario

def _usuario_autorizado(email: str, db: Session, current_user: Usuario) -> Usuario:
    if email.lower() != (current_user.email or "").lower() and not _es_staff(current_user):
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Solo puedes consultar o modificar tu propio perfil"
        )

    usuario = db.query(Usuario).filter(func.lower(Usuario.email) == email.lower()).first()
    if not usuario:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Usuario no encontrado"
        )
    return usuario


@router.get("/me", response_model=UsuarioResponse)
def mi_perfil(current_user: Usuario = Depends(get_current_user)):
    return current_user


@router.get("/perfil/{email}", response_model=UsuarioResponse)
def obtener_perfil(
    email: str,
    db: Session = Depends(get_db),
    current_user: Usuario = Depends(get_current_user)
):
    return _usuario_autorizado(email, db, current_user)


@router.put("/perfil/{email}", response_model=UsuarioResponse)
async def actualizar_perfil(
    email: str,
    nombre: Optional[str] = Form(None),
    telefono: Optional[str] = Form(None),
    direccion: Optional[str] = Form(None),
    fecha_nacimiento: Optional[str] = Form(None),
    foto: Optional[UploadFile] = File(None),
    db: Session = Depends(get_db),
    current_user: Usuario = Depends(get_current_user)
):
    usuario = _usuario_autorizado(email, db, current_user)

    if nombre and nombre.strip():
        usuario.nombre = nombre.strip()
    if telefono is not None:
        usuario.telefono = telefono.strip() or None
    if direccion is not None:
        usuario.direccion = direccion.strip() or None

    if fecha_nacimiento is not None:
        texto = fecha_nacimiento.strip()
        if not texto:
            usuario.fecha_nacimiento = None
        else:
            try:
                usuario.fecha_nacimiento = datetime.strptime(texto, "%Y-%m-%d").date()
            except ValueError:
                raise HTTPException(
                    status_code=400,
                    detail="La fecha de nacimiento debe tener el formato YYYY-MM-DD"
                )

    if foto and foto.filename:
        extension = os.path.splitext(foto.filename)[1].lower()
        if extension not in EXTENSIONES_FOTO:
            raise HTTPException(
                status_code=400,
                detail="La foto debe ser JPG, PNG o WEBP"
            )

        contenido = await foto.read()
        if len(contenido) > MAX_FOTO_BYTES:
            raise HTTPException(
                status_code=400,
                detail="La foto no puede pesar más de 5 MB"
            )

        nombre_archivo = f"user_{usuario.id}{extension}"
        ruta_guardado = os.path.join(UPLOAD_DIR, nombre_archivo)
        with open(ruta_guardado, "wb") as destino:
            destino.write(contenido)

        usuario.foto_url = f"/{UPLOAD_DIR}/{nombre_archivo}"

    db.commit()
    db.refresh(usuario)
    return usuario

# Esquema para actualización de usuarios
class UsuarioUpdateAdmin(BaseModel):
    nombre: Optional[str] = None
    email: Optional[EmailStr] = None
    password: Optional[str] = None
    telefono: Optional[str] = None
    rol: Optional[str] = None
    complejo_id: Optional[int] = None

# Endpoint para actualizar cualquier usuario desde el panel admin
@router.put("/{user_id}", response_model=UsuarioResponse)
def actualizar_usuario_admin(
    user_id: int,
    datos: UsuarioUpdateAdmin,
    db: Session = Depends(get_db),
    current_user: Usuario = Depends(get_current_user)
):
    if not _es_staff(current_user):
        raise HTTPException(status_code=403, detail="No tienes permisos para modificar usuarios")

    usuario = db.query(Usuario).filter(Usuario.id == user_id).first()
    if not usuario:
        raise HTTPException(status_code=404, detail="Usuario no encontrado")

    if datos.nombre:
        usuario.nombre = datos.nombre
    if datos.email:
        usuario.email = datos.email.lower()
    if datos.telefono is not None:
        usuario.telefono = datos.telefono
    if datos.rol:
        usuario.rol = datos.rol
    if datos.complejo_id is not None:
        usuario.complejo_id = datos.complejo_id

    # Actualizar la contraseña solo si enviaron un nuevo valor
    if datos.password and datos.password.strip():
        usuario.password_hash = pwd_context.hash(datos.password)

    db.commit()
    db.refresh(usuario)
    return usuario