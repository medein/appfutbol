from pydantic import BaseModel, EmailStr
from app.schemas.usuario_schema import UsuarioResponse

class UsuarioLogin(BaseModel):
    email: EmailStr
    password: str

class GoogleAuthSchema(BaseModel):
    id_token: str

class ChangePasswordSchema(BaseModel):
    email: EmailStr
    old_password: str
    new_password: str

class TokenResponse(BaseModel):
    access_token: str
    token_type: str = "bearer"
    usuario: UsuarioResponse