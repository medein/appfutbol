from datetime import datetime, timedelta
from jose import JWTError, jwt
from passlib.context import CryptContext
from fastapi import Depends, HTTPException, status
from fastapi.security import OAuth2PasswordBearer
from sqlalchemy.orm import Session
from app.database import get_db
from app.models.usuario import Usuario
from app.config import settings

pwd_context = CryptContext(schemes=["bcrypt"], deprecated="auto")
oauth2_scheme = OAuth2PasswordBearer(tokenUrl="api/auth/login")

# Roles que SIEMPRE pueden pasar cualquier verificación de rol.
# Si mañana quieres agregar otro "super rol", solo añádelo aquí.
ROLES_SUPER = {"superadmin", "administrador"}


def verificar_password(password_plano: str, password_hash: str) -> bool:
    return pwd_context.verify(password_plano, password_hash)


def hashear_password(password: str) -> str:
    return pwd_context.hash(password)


def crear_token_acceso(data: dict) -> str:
    to_encode = data.copy()
    expire = datetime.utcnow() + timedelta(
        minutes=settings.access_token_expire_minutes
    )
    to_encode.update({"exp": expire})
    return jwt.encode(
        to_encode, settings.secret_key, algorithm=settings.algorithm
    )


def get_current_user(
    token: str = Depends(oauth2_scheme),
    db: Session = Depends(get_db),
) -> Usuario:
    credentials_exception = HTTPException(
        status_code=status.HTTP_401_UNAUTHORIZED,
        detail="No se pudo validar las credenciales",
        headers={"WWW-Authenticate": "Bearer"},
    )
    try:
        payload = jwt.decode(
            token, settings.secret_key, algorithms=[settings.algorithm]
        )
        user_id: str = payload.get("sub")
        if user_id is None:
            raise credentials_exception
    except JWTError:
        raise credentials_exception

    usuario = db.query(Usuario).filter(Usuario.id == int(user_id)).first()
    if usuario is None:
        raise credentials_exception
    if not usuario.activo:
        raise HTTPException(status_code=400, detail="Usuario inactivo")
    return usuario


def requiere_rol(*roles_permitidos):
    """
    Dependencia que verifica que el usuario tenga uno de los roles indicados.

    - Los roles se comparan en minúsculas (evita problemas con 'Admin' vs 'admin').
    - 'superadmin' y 'administrador' SIEMPRE tienen acceso, sin importar qué
      roles se listen en el endpoint. Así la gerencia ve todo.
    """
    permitidos = {r.lower() for r in roles_permitidos} | ROLES_SUPER

    def verificador(current_user: Usuario = Depends(get_current_user)):
        rol = (current_user.rol or "").lower()
        if rol not in permitidos:
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail="No tienes permisos para realizar esta acción",
            )
        return current_user

    return verificador