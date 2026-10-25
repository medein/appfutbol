import os
import re
import json
from datetime import date, datetime, time, timedelta, timezone
from typing import List
from zoneinfo import ZoneInfo, ZoneInfoNotFoundError
from pathlib import Path

from dotenv import load_dotenv
from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy import desc
from sqlalchemy.orm import Session
from groq import Groq

from app.database import get_db
from app.models.cancha import Cancha
from app.models.conversacion_ia import ConversacionIA
from app.models.reserva import Reserva
from app.models.usuario import Usuario
from app.schemas.chat_schema import ConversacionResponse, MensajeChat, RespuestaChat
from app.services.auth_service import get_current_user

# ---------------------------------------------------------------------------
# Configuración de Variables de Entorno (Búsqueda explícita en la raíz)
# ---------------------------------------------------------------------------
BASE_DIR = Path(__file__).resolve().parent.parent.parent # Sube 3 niveles: routers -> app -> raíz
env_path = BASE_DIR / '.env'
load_dotenv(dotenv_path=env_path)

GROQ_API_KEY = os.getenv("GROQ_API_KEY")

if not GROQ_API_KEY:
    print("⚠️ ALERTA: No se encontró GROQ_API_KEY en el archivo .env")
else:
    print(f"✅ LLAVE DE GROQ CARGADA CORRECTAMENTE (Inicia con: {GROQ_API_KEY[:5]}...)")

groq_client = Groq(api_key=GROQ_API_KEY) if GROQ_API_KEY else None
MODELO_GROQ = "openai/gpt-oss-120b"

router = APIRouter(prefix="/chat", tags=["Chat IA"])

# ---------------------------------------------------------------------------
# Reglas del negocio
# ---------------------------------------------------------------------------
try:
    TZ = ZoneInfo("America/Guatemala")
except ZoneInfoNotFoundError:
    TZ = timezone(timedelta(hours=-6))

APERTURA = time(6, 0)
CIERRE = time(22, 0)
HORA_PICO_DESDE = 18            
ESTADOS_LIBRES = ("cancelada", "rechazada")  

SYSTEM = """Eres el asistente de reservas de canchas sintéticas. Hablas en español,
con tono amable y breve (máximo 4 líneas por respuesta). La moneda es el quetzal (Q).
Fecha y hora actual: {ahora} (America/Guatemala).
Horario de atención: {apertura} a {cierre}. Las reservas son en horas completas.

USUARIO: ya inició sesión y está identificado: {usuario}.
Las herramientas usan automáticamente su cuenta. NUNCA pidas nombre, teléfono,
correo ni datos personales. Solo necesitas fecha, hora y duración.
{propuesta}
REGLAS ESTRICTAS:
1. Si preguntan por PRECIOS, usa listar_canchas_y_precios.
2. Para RESERVAR, averigua fecha (YYYY-MM-DD), hora (HH:MM) y duración. Luego usa consultar_disponibilidad.
3. Muestra cancha, precio y pregunta si confirma terminando con: [[opciones: Sí, confirmar | No, cambiar]]
4. Llama a crear_reserva SOLO cuando el usuario diga "Sí, confirmar".
5. Para "mis reservas" usa ver_mis_reservas."""

_AFIRMATIVO = re.compile(r"^\s*(s[ií]|confirm\w*|dale|ok|okay|va|claro|de acuerdo|listo)\b", re.IGNORECASE)

# ---------------------------------------------------------------------------
# Utilidades de fecha y disponibilidad
# ---------------------------------------------------------------------------
def _parsear_fecha(fecha_str: str) -> str:
    """Convierte 'hoy', 'mañana' o 'DD/MM/YYYY' a 'YYYY-MM-DD'."""
    hoy = datetime.now(TZ).date()
    s = fecha_str.lower().strip()
    if s in ("hoy", "el día de hoy"): return hoy.isoformat()
    if s in ("mañana", "el día de mañana"): return (hoy + timedelta(days=1)).isoformat()
    
    match = re.match(r"(\d{1,2})/(\d{1,2})/(\d{4})", s)
    if match: return f"{match.group(3)}-{match.group(2).zfill(2)}-{match.group(1).zfill(2)}"
    if re.match(r"\d{4}-\d{2}-\d{2}", s): return s
    return fecha_str

def _parsear(fecha: str, hora_inicio: str, duracion_horas: float):
    fecha_limpia = _parsear_fecha(fecha)
    f = date.fromisoformat(fecha_limpia)
    partes = (hora_inicio.split(":") + ["0"])[:2]
    ini = time(int(partes[0]), int(partes[1]))
    horas = int(duracion_horas)
    if horas != duracion_horas or horas < 1: raise ValueError("Las reservas son en horas completas.")
    fin_dt = datetime.combine(f, ini) + timedelta(hours=horas)
    return f, ini, fin_dt.time(), horas

def _precio_total(c: Cancha, ini: time, horas: int) -> float:
    total = 0.0
    for i in range(horas):
        pico = c.precio_hora_pico is not None and (ini.hour + i) >= HORA_PICO_DESDE
        total += float(c.precio_hora_pico if pico else c.precio_hora or 0)
    return round(total, 2)

def _hay_choque(db: Session, cancha_id: int, f: date, ini: time, fin: time) -> bool:
    return (
        db.query(Reserva)
        .filter(Reserva.cancha_id == cancha_id, Reserva.fecha_reserva == f, Reserva.estado.notin_(ESTADOS_LIBRES), Reserva.hora_inicio < fin, Reserva.hora_fin > ini)
        .first() is not None
    )

def _canchas_activas(db: Session, cancha_id: int = 0):
    q = db.query(Cancha).filter(Cancha.activa == 1)
    if cancha_id: q = q.filter(Cancha.id == cancha_id)
    return q.all()

def _extraer_opciones(texto: str):
    m = re.search(r"\[\[opciones:\s*(.+?)\]\]", texto, re.IGNORECASE | re.DOTALL)
    if not m: return texto.strip(), []
    opciones = [o.strip() for o in m.group(1).split("|") if o.strip()]
    return (texto[: m.start()] + texto[m.end():]).strip(), opciones


@router.get("/historial", response_model=List[ConversacionResponse])
def historial_chat(limite: int = Query(50, ge=1, le=200), db: Session = Depends(get_db), current_user: Usuario = Depends(get_current_user)):
    recientes = db.query(ConversacionIA).filter(ConversacionIA.usuario_id == current_user.id).order_by(desc(ConversacionIA.fecha_creacion), desc(ConversacionIA.id)).limit(limite).all()
    return list(reversed(recientes))


@router.post("/", response_model=RespuestaChat)
@router.post("", response_model=RespuestaChat)
def chat_con_ia(mensaje: MensajeChat, db: Session = Depends(get_db), current_user: Usuario = Depends(get_current_user)):
    if not groq_client:
        raise HTTPException(500, "La API Key de Groq no está configurada en el .env")

    recientes = list(reversed(db.query(ConversacionIA).filter(ConversacionIA.usuario_id == current_user.id).order_by(desc(ConversacionIA.id)).limit(10).all()))
    propuesta_previa = None
    for fila in reversed(recientes):
        ra = fila.resultado_accion if isinstance(fila.resultado_accion, dict) else {}
        if ra.get("reserva_id"): break
        if ra.get("propuesta"): propuesta_previa = ra["propuesta"]; break

    estado = {"intencion": "consulta_general", "propuesta": None, "accion": None}

    # -----------------------------------------------------------------------
    # Herramientas (Python)
    # -----------------------------------------------------------------------
    def consultar_disponibilidad(fecha: str, hora_inicio: str, duracion_horas: int, cancha_id: int = 0) -> dict:
        estado["intencion"] = "reservar"
        try: f, ini, fin, horas = _parsear(fecha, hora_inicio, duracion_horas)
        except Exception as e: return {"disponible": False, "error": str(e)}
        
        canchas = _canchas_activas(db, cancha_id)
        libres = [{"cancha_id": c.id, "nombre": c.nombre, "precio_total": _precio_total(c, ini, horas)} for c in canchas if not _hay_choque(db, c.id, f, ini, fin)]
        if libres:
            estado["propuesta"] = {"fecha": str(f), "hora_inicio": ini.strftime("%H:%M"), "duracion_horas": horas, "canchas_libres": libres}
            return {"disponible": True, "fecha": str(f), "hora_inicio": ini.strftime("%H:%M"), "canchas_libres": libres}
        
        return {"disponible": False, "mensaje": "No hay canchas libres a esa hora."}

    def crear_reserva(cancha_id: int, fecha: str, hora_inicio: str, duracion_horas: int) -> dict:
        estado["intencion"] = "reservar"
        if not _AFIRMATIVO.match(mensaje.mensaje): return {"ok": False, "error": "Falta confirmación."}
        try: f, ini, fin, horas = _parsear(fecha, hora_inicio, duracion_horas)
        except Exception as e: return {"ok": False, "error": str(e)}
        
        cancha = db.query(Cancha).filter(Cancha.id == cancha_id, Cancha.activa == 1).with_for_update().first()
        if not cancha or _hay_choque(db, cancha.id, f, ini, fin):
            db.rollback(); return {"ok": False, "error": "Horario ocupado."}

        total = _precio_total(cancha, ini, horas)
        reserva = Reserva(cancha_id=cancha.id, usuario_id=current_user.id, fecha_reserva=f, hora_inicio=ini, hora_fin=fin, estado="pendiente", precio_total=total, metodo_pago="transferencia", pagado=False, notas="Reservado desde el asistente", creado_por_ia=True)
        db.add(reserva); db.commit(); db.refresh(reserva)
        estado["accion"] = {"mensaje": f"Reserva #{reserva.id} creada. Sube tu comprobante.", "reserva_id": reserva.id}
        return {"ok": True, "reserva_id": reserva.id, "cancha": cancha.nombre, "precio_total": total}

    def ver_mis_reservas() -> dict:
        estado["intencion"] = "mis_reservas"
        filas = db.query(Reserva).filter(Reserva.usuario_id == current_user.id, Reserva.fecha_reserva >= datetime.now(TZ).date(), Reserva.estado.notin_(ESTADOS_LIBRES)).order_by(Reserva.fecha_reserva).limit(10).all()
        return {"reservas": [{"id": r.id, "cancha": r.cancha.nombre, "fecha": str(r.fecha_reserva), "hora": str(r.hora_inicio)[:5], "estado": r.estado} for r in filas]}

    def listar_canchas_y_precios() -> dict:
        estado["intencion"] = "consultar_precio"
        return {"hora_pico_desde": f"{HORA_PICO_DESDE}:00", "canchas": [{"id": c.id, "nombre": c.nombre, "precio_hora": float(c.precio_hora or 0), "precio_hora_pico": float(c.precio_hora_pico) if c.precio_hora_pico else None} for c in _canchas_activas(db)]}

    funciones_disponibles = {
        "consultar_disponibilidad": consultar_disponibilidad,
        "crear_reserva": crear_reserva,
        "ver_mis_reservas": ver_mis_reservas,
        "listar_canchas_y_precios": listar_canchas_y_precios,
    }

    # -----------------------------------------------------------------------
    # Esquema de herramientas para Groq (Formato OpenAI)
    # -----------------------------------------------------------------------
    herramientas_groq = [
        {"type": "function", "function": {"name": "consultar_disponibilidad", "description": "Consulta disponibilidad y precio.", "parameters": {"type": "object", "properties": {"fecha": {"type": "string", "description": "YYYY-MM-DD"}, "hora_inicio": {"type": "string", "description": "HH:MM"}, "duracion_horas": {"type": "integer"}, "cancha_id": {"type": "integer"}}, "required": ["fecha", "hora_inicio", "duracion_horas"]}}},
        {"type": "function", "function": {"name": "crear_reserva", "description": "Crea la reserva.", "parameters": {"type": "object", "properties": {"cancha_id": {"type": "integer"}, "fecha": {"type": "string"}, "hora_inicio": {"type": "string"}, "duracion_horas": {"type": "integer"}}, "required": ["cancha_id", "fecha", "hora_inicio", "duracion_horas"]}}},
        {"type": "function", "function": {"name": "ver_mis_reservas", "description": "Reservas del usuario.", "parameters": {"type": "object", "properties": {}}}},
        {"type": "function", "function": {"name": "listar_canchas_y_precios", "description": "Lista precios.", "parameters": {"type": "object", "properties": {}}}}
    ]

    # -----------------------------------------------------------------------
    # Contexto y Llamada a Groq
    # -----------------------------------------------------------------------
    bloque_propuesta = f"\nÚltima propuesta: {propuesta_previa}\n" if propuesta_previa else ""
    mensajes = [{"role": "system", "content": SYSTEM.format(ahora=datetime.now(TZ).strftime("%Y-%m-%d %H:%M"), apertura=APERTURA.strftime("%H:%M"), cierre=CIERRE.strftime("%H:%M"), usuario=current_user.nombre or "cliente", propuesta=bloque_propuesta)}]
    
    for fila in recientes:
        mensajes.append({"role": "user", "content": fila.mensaje_usuario})
        if fila.respuesta_ia: mensajes.append({"role": "assistant", "content": fila.respuesta_ia})
    mensajes.append({"role": "user", "content": mensaje.mensaje})

    try:
        respuesta = groq_client.chat.completions.create(model=MODELO_GROQ, messages=mensajes, tools=herramientas_groq, temperature=0.1)
        mensaje_respuesta = respuesta.choices[0].message
        iteraciones = 0

        while mensaje_respuesta.tool_calls and iteraciones < 3:
            iteraciones += 1
            mensajes.append(mensaje_respuesta)
            
            for tool_call in mensaje_respuesta.tool_calls:
                nombre = tool_call.function.name
                try:
                    args = json.loads(tool_call.function.arguments)
                except:
                    args = {}
                    
                print(f"🛠️ Groq ejecutando: {nombre} con {args}")
                
                if nombre in funciones_disponibles:
                    resultado = funciones_disponibles[nombre](**args)
                else:
                    resultado = {"error": "Función no encontrada"}
                    
                mensajes.append({"role": "tool", "tool_call_id": tool_call.id, "name": nombre, "content": json.dumps(resultado)})
            
            respuesta = groq_client.chat.completions.create(model=MODELO_GROQ, messages=mensajes, tools=herramientas_groq)
            mensaje_respuesta = respuesta.choices[0].message

        texto = mensaje_respuesta.content.strip()
    except Exception as e:
        db.rollback()
        texto = estado["accion"]["mensaje"] if estado["accion"] else "Error interno. Intenta de nuevo."
        print("❌ ERROR EN GROQ:", repr(e))

    texto, opciones = _extraer_opciones(texto)
    
    guardado = {}
    if estado["propuesta"]: guardado["propuesta"] = estado["propuesta"]
    if estado["accion"]: guardado.update(estado["accion"])
    if opciones: guardado["opciones"] = opciones

    db.add(ConversacionIA(usuario_id=current_user.id, mensaje_usuario=mensaje.mensaje, respuesta_ia=texto, intencion_detectada=estado["intencion"], resultado_accion=guardado or None, fecha_creacion=datetime.now()))
    db.commit()
    
    return RespuestaChat(respuesta=texto, intencion=estado["intencion"], opciones=opciones, accion_resultado=estado["accion"])