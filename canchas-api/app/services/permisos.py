"""
app/services/permisos.py

Helpers para forzar el filtrado por complejo según el rol del usuario.
"""
from typing import Optional


def es_superadmin(usuario) -> bool:
    """True si el usuario puede ver TODOS los complejos."""
    rol = (getattr(usuario, "rol", "") or "").lower()
    return rol == "superadmin"


def complejo_efectivo(usuario, complejo_id_query: Optional[int]) -> Optional[int]:
    """
    Devuelve el ID del complejo por el que hay que filtrar, o None si
    el usuario puede ver todos (superadmin sin complejo asignado).

    Reglas:
    - superadmin SIN complejo asignado → usa el query, o None (todo).
    - cualquier otro (o superadmin CON complejo) → fuerza SU complejo.
    """
    if es_superadmin(usuario) and usuario.complejo_id is None:
        return complejo_id_query
    return usuario.complejo_id