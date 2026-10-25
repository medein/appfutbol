"""Crea (o promueve) un usuario administrador.

El rol `admin` es el que habilita el panel de aprobación de depósitos en la
app Flutter y los endpoints de /dashboard.

    venv\\Scripts\\python.exe create_admin.py
    venv\\Scripts\\python.exe create_admin.py correo@dominio.com mi-clave "Mi Nombre"

Si el correo ya existe, no lo duplica: le cambia el rol a admin.
"""

import sys

from app.database import SessionLocal
from app.models.usuario import Usuario
from app.services.auth_service import hashear_password


def crear_administrador(email: str, password: str, nombre: str) -> None:
    db = SessionLocal()
    try:
        existente = db.query(Usuario).filter(Usuario.email == email).first()

        if existente:
            if existente.rol == "admin":
                print(f"El usuario {email} ya era administrador. No se cambió nada.")
                return
            existente.rol = "admin"
            db.commit()
            print(f"El usuario {email} ya existía: ahora tiene el rol admin.")
            return

        nuevo_admin = Usuario(
            nombre=nombre,
            email=email,
            password_hash=hashear_password(password),
            rol="admin",
            activo=True,
        )
        db.add(nuevo_admin)
        db.commit()

        print("Usuario administrador creado con éxito.")
        print(f"  Correo:     {email}")
        print(f"  Contraseña: {password}")
        print("Cámbiala después de iniciar sesión por primera vez.")
    finally:
        db.close()


if __name__ == "__main__":
    email = sys.argv[1] if len(sys.argv) > 1 else "admin@ejemplo.com"
    password = sys.argv[2] if len(sys.argv) > 2 else "admin123"
    nombre = sys.argv[3] if len(sys.argv) > 3 else "Administrador General"
    crear_administrador(email, password, nombre)
