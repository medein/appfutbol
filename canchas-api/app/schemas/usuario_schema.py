from pydantic import BaseModel, EmailStr
from datetime import datetime, date
from typing import Optional


class UsuarioBase(BaseModel):
    nombre: str
    email: EmailStr
    telefono: Optional[str] = None


class UsuarioCreate(UsuarioBase):
    password: str


class UsuarioLogin(BaseModel):
    email: EmailStr
    password: str


class UsuarioResponse(UsuarioBase):
    id: int
    rol: str
    fecha_registro: datetime
    activo: bool
    foto_url: Optional[str] = None
    direccion: Optional[str] = None
    fecha_nacimiento: Optional[date] = None
    complejo_id: Optional[int] = None      # ← NUEVO

    class Config:
        from_attributes = True


class TokenResponse(BaseModel):
    access_token: str
    token_type: str = "bearer"
    usuario: UsuarioResponse