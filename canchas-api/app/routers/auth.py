from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.orm import Session
from pydantic import BaseModel
from google.oauth2 import id_token
from google.auth.transport import requests
from pydantic import BaseModel, EmailStr
from app.schemas.auth_schema import GoogleAuthSchema, ChangePasswordSchema, TokenResponse, UsuarioLogin
from app.schemas.usuario_schema import UsuarioCreate

from app.database import get_db
from app.models.usuario import Usuario
from app.schemas.usuario_schema import UsuarioCreate, UsuarioLogin, TokenResponse
from app.services.auth_service import hashear_password, verificar_password, crear_token_acceso

router = APIRouter(prefix="/auth", tags=["Autenticación"])

# ⚠️ Coloca el "ID de cliente Web" obtenido desde Google Cloud Console / Firebase
GOOGLE_CLIENT_ID = "187277252854-b78tfnght5npg19dsgb0s11pjgi74mq1.apps.googleusercontent.com"


class GoogleAuthSchema(BaseModel):
    id_token: str

class ChangePasswordSchema(BaseModel):
    email: EmailStr
    old_password: str
    new_password: str

@router.post("/change-password")
def cambiar_contrasena(data: ChangePasswordSchema, db: Session = Depends(get_db)):
    # 1. Buscar usuario
    usuario = db.query(Usuario).filter(Usuario.email == data.email).first()
    if not usuario:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND, 
            detail="Usuario no encontrado"
        )
    
    # 2. Verificar si es un usuario que se registró solo con Google (password_hash es NULL)
    if usuario.password_hash is None:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST, 
            detail="Los usuarios registrados con Google no tienen una contraseña que cambiar."
        )

    # 3. Validar contraseña actual
    if not verificar_password(data.old_password, usuario.password_hash):
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST, 
            detail="La contraseña actual es incorrecta"
        )
    
    # 4. Actualizar y guardar la nueva contraseña
    usuario.password_hash = hashear_password(data.new_password)
    db.commit()
    
    return {"message": "Contraseña actualizada exitosamente"}

@router.post("/registro", response_model=TokenResponse, status_code=status.HTTP_201_CREATED)
def registro(usuario: UsuarioCreate, db: Session = Depends(get_db)):
    existente = db.query(Usuario).filter(Usuario.email == usuario.email).first()
    if existente:
        raise HTTPException(status_code=400, detail="El correo ya está registrado")

    nuevo_usuario = Usuario(
        nombre=usuario.nombre,
        email=usuario.email,
        telefono=usuario.telefono,
        password_hash=hashear_password(usuario.password),
        rol="cliente"
    )
    db.add(nuevo_usuario)
    db.commit()
    db.refresh(nuevo_usuario)

    token = crear_token_acceso({"sub": str(nuevo_usuario.id)})
    return {"access_token": token, "usuario": nuevo_usuario}


@router.post("/login", response_model=TokenResponse)
def login(credenciales: UsuarioLogin, db: Session = Depends(get_db)):
    usuario = db.query(Usuario).filter(Usuario.email == credenciales.email).first()

    if not usuario or not verificar_password(credenciales.password, usuario.password_hash):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Correo o contraseña incorrectos"
        )

    if not usuario.activo:
        raise HTTPException(status_code=400, detail="Usuario inactivo")

    token = crear_token_acceso({"sub": str(usuario.id)})
    return {"access_token": token, "usuario": usuario}


# 👇 NUEVO ENDPOINT INTEGRADOR DE GOOGLE OAUTH 2.0
@router.post("/google", response_model=TokenResponse)
def login_con_google(datos: GoogleAuthSchema, db: Session = Depends(get_db)):
    try:
        # 1. Validar id_token criptográficamente contra los servidores de Google
        id_info = id_token.verify_oauth2_token(
            datos.id_token, 
            requests.Request(), 
            GOOGLE_CLIENT_ID
        )

        email = id_info.get("email")
        nombre = id_info.get("name", "Usuario Google")
        email_verified = id_info.get("email_verified", False)

        if not email or not email_verified:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="El correo de Google no se encuentra verificado"
            )

        # 2. Buscar si ya existe el usuario o crearlo en MySQL/PostgreSQL
        usuario = db.query(Usuario).filter(Usuario.email == email).first()

        if not usuario:
            usuario = Usuario(
                nombre=nombre,
                email=email,
                telefono=None,
                password_hash=None, # No requiere contraseña por autenticarse con OAuth
                rol="cliente",
                activo=True
            )
            db.add(usuario)
            db.commit()
            db.refresh(usuario)

        if not usuario.activo:
            raise HTTPException(status_code=400, detail="Usuario inactivo")

        # 3. Generar token de acceso idéntico al del login convencional
        token = crear_token_acceso({"sub": str(usuario.id)})
        return {"access_token": token, "usuario": usuario}

    except ValueError:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Token de Google inválido o caducado"
        )