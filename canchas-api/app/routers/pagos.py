from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session
from pydantic import BaseModel
import httpx
import os

from app.database import get_db
from app.models.reserva import Reserva 

router = APIRouter()

class PagoRequest(BaseModel):
    reserva_id: int

@router.post("/crear-pago")
async def crear_pago(pago: PagoRequest, db: Session = Depends(get_db)):
    # 1. Buscar la reserva en la base de datos
    reserva = db.query(Reserva).filter(Reserva.id == pago.reserva_id).first()
    if not reserva:
        raise HTTPException(status_code=404, detail="Reserva no encontrada")

    # 2. Convertir el precio a centavos
    monto_centavos = int(reserva.precio_total * 100)
    
    # 3. Preparar la petición a Recurrente
    secret_key = os.getenv("RECURRENTE_SECRET_KEY")
    headers = {
        "X-SECRET-KEY": secret_key,
        "Content-Type": "application/json"
    }
    
    payload = {
        "items": [
            {
                "name": f"Reserva Cancha #{reserva.id}",
                "amount_in_cents": monto_centavos,
                "currency": "GTQ",
                "quantity": 1
            }
        ],
        "metadata": {
            "reserva_id": reserva.id 
        }
    }

    # 4. Hacer la petición a Recurrente
    async with httpx.AsyncClient() as client:
        response = await client.post(
            "https://app.recurrente.com/api/checkouts",
            json=payload,
            headers=headers
        )

    # 5. Validar la respuesta de Recurrente
    if response.status_code not in (200, 201):
        print("❌ ERROR DE RECURRENTE:", response.text)
        raise HTTPException(status_code=400, detail=f"Error de Recurrente: {response.text}")

    data = response.json()
    
    # 6. Devolver el link de pago al frontend
    return {
        "checkout_url": data.get("checkout_url"),
        "checkout_id": data.get("id")
    }