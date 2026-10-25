from datetime import datetime, timedelta
from sqlalchemy.orm import Session
from fastapi import HTTPException, status
from app.models.reserva import Reserva
from app.models.cancha import Cancha
from app.schemas.reserva import ReservaCreate

def verificar_disponibilidad(db: Session, cancha_id: int, fecha, hora_inicio, hora_fin):
    reserva_existente = db.query(Reserva).filter(
        Reserva.cancha_id == cancha_id,
        Reserva.fecha == fecha,
        Reserva.estado != "CANCELADA",
        Reserva.hora_inicio < hora_fin,
        Reserva.hora_fin > hora_inicio
    ).first()
    
    return reserva_existente is None

def crear_nueva_reserva(db: Session, reserva_data: ReservaCreate, usuario_id: int):
    cancha = db.query(Cancha).filter(Cancha.id == reserva_data.cancha_id).first()
    if not cancha:
        raise HTTPException(status_code=404, detail="La cancha no existe")

    if reserva_data.hora_inicio >= reserva_data.hora_fin:
        raise HTTPException(status_code=400, detail="La hora de inicio debe ser menor a la hora de fin")

    disponible = verificar_disponibilidad(
        db, reserva_data.cancha_id, reserva_data.fecha, reserva_data.hora_inicio, reserva_data.hora_fin
    )
    if not disponible:
        raise HTTPException(status_code=400, detail="La cancha ya se encuentra reservada en ese horario")

    # Cálculo automático del total a pagar según la duración
    duracion = datetime.combine(reserva_data.fecha, reserva_data.hora_fin) - datetime.combine(reserva_data.fecha, reserva_data.hora_inicio)
    horas = duracion.total_seconds() / 3600
    total = horas * cancha.precio_por_hora

    nueva_reserva = Reserva(
        **reserva_data.dict(),
        usuario_id=usuario_id,
        total=total,
        estado="CONFIRMADA"
    )
    db.add(nueva_reserva)
    db.commit()
    db.refresh(nueva_reserva)
    return nueva_reserva