from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from fastapi.staticfiles import StaticFiles
from app.routers import auth, user, canchas, reservas, dashboard, chat, complejos, pagos
import os
from dotenv import load_dotenv
load_dotenv()
from app.routers import complejos
# Base de datos y Modelos
from app.database import engine, Base
from app.models import usuario, complejo, cancha, reserva, conversacion_ia
from fastapi import Request, status
from fastapi.responses import JSONResponse
from fastapi import Request, status, Depends  # 👈 Agrega 'Depends' aquí
from fastapi.responses import JSONResponse
from sqlalchemy.orm import Session # 👈 Agrega esta línea
from app.database import get_db # 👈 Agrega esta línea
from app.models.reserva import Reserva

# Routers (Añadido 'user')
from app.routers import auth, user, canchas, reservas, dashboard, chat

# Registrar tablas en MySQL si no existen
Base.metadata.create_all(bind=engine)

# Crear directorio estático si no existe (para fotos de perfil)
os.makedirs("static", exist_ok=True)

# Inicializar FastAPI
app = FastAPI(title="Canchas Reservas API", version="1.0.0")

# Archivos estáticos
app.mount("/static", StaticFiles(directory="static"), name="static")

# Habilitar CORS
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Registrar Endpoints con prefijo /api
app.include_router(auth.router, prefix="/api")
app.include_router(user.router, prefix="/api")  
app.include_router(canchas.router, prefix="/api")
app.include_router(reservas.router, prefix="/api")
app.include_router(dashboard.router, prefix="/api")
app.include_router(chat.router, prefix="/api")
app.include_router(complejos.router, prefix="/api")
# Debe estar esta línea exacta:
app.include_router(pagos.router, prefix="/api")


@app.get("/")
def root():
    return {"message": "Canchas Reservas API funcionando", "docs": "/docs"}


@app.post("/api/webhook-recurrente")
async def webhook_recurrente(request: Request, db: Session = Depends(get_db)):
    try:
        payload = await request.json()
        
        # Recurrente usa 'event_type' o 'type'
        event_type = payload.get("event_type") or payload.get("type")
        print(f"🔔 Webhook recibido: {event_type}")

        # El evento correcto es 'intent.succeeded'
        if event_type == "intent.succeeded":
            
            # Extraer el reserva_id desde el metadata
            checkout = payload.get("checkout", {})
            metadata = checkout.get("metadata", {})
            reserva_id = metadata.get("reserva_id")

            if reserva_id:
                print(f"✅ Pago exitoso para la reserva ID: {reserva_id}")
                
                # Buscar y actualizar en la BD
                reserva = db.query(Reserva).filter(Reserva.id == reserva_id).first()
                if reserva:
                    reserva.estado = "confirmada"
                    db.commit()
                    print(f"💾 Reserva {reserva_id} actualizada en la base de datos.")
                else:
                    print(f"⚠️ Reserva {reserva_id} no encontrada en la BD.")
            else:
                print("⚠️ No se encontró reserva_id en el metadata del pago.")

        return JSONResponse(status_code=status.HTTP_200_OK, content={"status": "success"})
        
    except Exception as e:
        print(f"⚠️ Error procesando el webhook: {e}")
        return JSONResponse(status_code=status.HTTP_400_BAD_REQUEST, content={"status": "error"})