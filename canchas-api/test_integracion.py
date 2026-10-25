"""Prueba de integracion: recorre el mismo flujo que hace la app Flutter.

Requiere que la API este corriendo:
    venv\\Scripts\\python.exe -m uvicorn app.main:app --host 0.0.0.0 --port 8000

Uso:
    venv\\Scripts\\python.exe test_integracion.py
"""

import io
import sys
import time
from datetime import date, timedelta

import requests

BASE = "http://127.0.0.1:8000/api"

ok_total = 0
fallos = []


def check(nombre, condicion, detalle=""):
    global ok_total
    if condicion:
        ok_total += 1
        print(f"  OK    {nombre}")
    else:
        fallos.append(f"{nombre} -> {detalle}")
        print(f"  FALLO {nombre}  {detalle}")


def h(token):
    return {"Authorization": f"Bearer {token}"}


# PNG de 1x1 pixel, para probar la subida de archivos
PNG_1X1 = bytes.fromhex(
    "89504e470d0a1a0a0000000d49484452000000010000000108060000001f15c4"
    "890000000a49444154789c63000100000500010d0a2db40000000049454e44ae"
    "426082"
)

print("=" * 70)
print("1. SERVIDOR")
print("=" * 70)
r = requests.get("http://127.0.0.1:8000/", timeout=10)
check("GET / responde 200", r.status_code == 200, r.text[:120])

print()
print("=" * 70)
print("2. AUTENTICACION Y PERFIL")
print("=" * 70)
sufijo = str(int(time.time()))
email_cliente = f"cliente{sufijo}@test.com"
email_otro = f"otro{sufijo}@test.com"
PASS = "clave12345"

r = requests.post(BASE + "/auth/registro", json={
    "nombre": "Cliente Prueba",
    "email": email_cliente,
    "password": PASS,
    "telefono": "50212345678",
}, timeout=10)
check("POST /auth/registro crea el usuario", r.status_code == 201, r.text[:200])
token_cliente = r.json().get("access_token", "") if r.status_code == 201 else ""

r = requests.post(BASE + "/auth/registro", json={
    "nombre": "Otro Cliente", "email": email_otro, "password": PASS,
}, timeout=10)
token_otro = r.json().get("access_token", "") if r.status_code == 201 else ""
check("Segundo usuario creado (para probar permisos)", bool(token_otro), r.text[:150])

r = requests.post(BASE + "/auth/login", json={
    "email": email_cliente, "password": PASS,
}, timeout=10)
check("POST /auth/login responde 200", r.status_code == 200, r.text[:200])
data = r.json()
token_cliente = data.get("access_token", token_cliente)
usuario = data.get("usuario", {})
check("El login devuelve el objeto 'usuario'", isinstance(usuario, dict) and usuario.get("email") == email_cliente, str(usuario)[:200])
check("El usuario incluye 'rol' (la app lo usa para el panel admin)", usuario.get("rol") == "cliente", str(usuario.get("rol")))
for campo in ["foto_url", "direccion", "fecha_nacimiento"]:
    check(f"El usuario incluye '{campo}'", campo in usuario, str(list(usuario.keys())))

r = requests.get(BASE + "/users/me", headers=h(token_cliente), timeout=10)
check("GET /users/me responde 200", r.status_code == 200, r.text[:200])
check("GET /users/me devuelve al dueno del token", r.json().get("email") == email_cliente, r.text[:150])

r = requests.get(BASE + f"/users/perfil/{email_cliente}", headers=h(token_cliente), timeout=10)
check("GET /users/perfil/{email} responde 200", r.status_code == 200, r.text[:200])

r = requests.get(BASE + f"/users/perfil/{email_cliente}", headers=h(token_otro), timeout=10)
check("Un usuario NO puede leer el perfil de otro (403)", r.status_code == 403, f"dio {r.status_code}")

r = requests.get(BASE + f"/users/perfil/{email_cliente}", timeout=10)
check("Sin token no se puede leer un perfil (401)", r.status_code == 401, f"dio {r.status_code}")

r = requests.put(
    BASE + f"/users/perfil/{email_cliente}",
    headers=h(token_cliente),
    data={
        "nombre": "Cliente Actualizado",
        "telefono": "50287654321",
        "direccion": "Zona 10, Guatemala",
        "fecha_nacimiento": "1999-05-20",
    },
    files={"foto": ("avatar.png", io.BytesIO(PNG_1X1), "image/png")},
    timeout=15,
)
check("PUT /users/perfil actualiza nombre/telefono/direccion/fecha/foto", r.status_code == 200, r.text[:250])
if r.status_code == 200:
    p = r.json()
    check("  guardo 'direccion'", p.get("direccion") == "Zona 10, Guatemala", str(p.get("direccion")))
    check("  guardo 'fecha_nacimiento'", str(p.get("fecha_nacimiento")) == "1999-05-20", str(p.get("fecha_nacimiento")))
    check("  guardo 'foto_url'", (p.get("foto_url") or "").endswith(".png"), str(p.get("foto_url")))
    ruta_foto = p.get("foto_url")
    if ruta_foto:
        rf = requests.get("http://127.0.0.1:8000" + ruta_foto, timeout=10)
        check("  la foto se sirve como archivo estatico", rf.status_code == 200, f"dio {rf.status_code}")

r = requests.put(BASE + f"/users/perfil/{email_cliente}", headers=h(token_cliente),
                 data={"fecha_nacimiento": "20-05-1999"}, timeout=10)
check("Rechaza una fecha de nacimiento mal formada (400)", r.status_code == 400, f"dio {r.status_code}")

print()
print("=" * 70)
print("3. CANCHAS")
print("=" * 70)
r = requests.get(BASE + "/canchas/", headers=h(token_cliente), timeout=10)
check("GET /canchas/ responde 200", r.status_code == 200, r.text[:200])
canchas = r.json() if r.status_code == 200 else []
check("Hay al menos una cancha registrada", len(canchas) > 0, f"{len(canchas)} canchas")

if not canchas:
    print("\nSin canchas no se puede probar el flujo de reservas. Abortando.")
    sys.exit(1)

cancha = canchas[0]
cancha_id = cancha["id"]
print(f"  (usando la cancha #{cancha_id} '{cancha.get('nombre')}' a {cancha.get('precio_hora')}/hora)")

print()
print("=" * 70)
print("4. CREAR RESERVAS Y DETECTAR CHOQUES DE HORARIO")
print("=" * 70)
manana = str(date.today() + timedelta(days=1))

r = requests.post(BASE + "/reservas/", headers=h(token_cliente), json={
    "cancha_id": cancha_id, "fecha_reserva": manana,
    "hora_inicio": "19:00:00", "hora_fin": "20:00:00",
    "notas": "Partido de prueba", "metodo_pago": "transferencia",
}, timeout=10)
check("POST /reservas/ crea la reserva (201)", r.status_code == 201, r.text[:250])
reserva = r.json() if r.status_code == 201 else {}
reserva_id = reserva.get("id")
check("La respuesta trae el 'id' de la reserva", bool(reserva_id), str(reserva)[:150])
check("Con transferencia el estado queda 'pendiente'", reserva.get("estado") == "pendiente", str(reserva.get("estado")))
check("La respuesta trae 'metodo_pago'", reserva.get("metodo_pago") == "transferencia", str(reserva.get("metodo_pago")))
check("La respuesta trae la cancha anidada con su nombre",
      isinstance(reserva.get("cancha"), dict) and reserva["cancha"].get("nombre"),
      str(reserva.get("cancha")))
check("La respuesta trae el usuario anidado",
      isinstance(reserva.get("usuario"), dict) and reserva["usuario"].get("email") == email_cliente,
      str(reserva.get("usuario")))
for campo in ["comprobante_url", "motivo_cancelacion", "notas", "fecha_creacion", "precio_total"]:
    check(f"La respuesta incluye '{campo}'", campo in reserva, str(list(reserva.keys())))
check("El servidor calculo el precio (no lo tomo del cliente)",
      isinstance(reserva.get("precio_total"), (int, float)) and reserva["precio_total"] > 0,
      str(reserva.get("precio_total")))

# El caso que la version anterior dejaba pasar: la reserva existente (19-20)
# queda contenida dentro del horario nuevo (18-21).
r = requests.post(BASE + "/reservas/", headers=h(token_otro), json={
    "cancha_id": cancha_id, "fecha_reserva": manana,
    "hora_inicio": "18:00:00", "hora_fin": "21:00:00", "metodo_pago": "transferencia",
}, timeout=10)
check("Detecta el choque cuando la reserva existente queda DENTRO del horario nuevo",
      r.status_code == 400, f"dio {r.status_code}: {r.text[:150]}")

r = requests.post(BASE + "/reservas/", headers=h(token_otro), json={
    "cancha_id": cancha_id, "fecha_reserva": manana,
    "hora_inicio": "19:30:00", "hora_fin": "20:30:00", "metodo_pago": "transferencia",
}, timeout=10)
check("Detecta el choque parcial", r.status_code == 400, f"dio {r.status_code}")

r = requests.post(BASE + "/reservas/", headers=h(token_otro), json={
    "cancha_id": cancha_id, "fecha_reserva": manana,
    "hora_inicio": "20:00:00", "hora_fin": "21:00:00", "metodo_pago": "transferencia",
}, timeout=10)
check("Permite reservar justo despues (20-21 no choca con 19-20)", r.status_code == 201, r.text[:200])
reserva_otro_id = r.json().get("id") if r.status_code == 201 else None

r = requests.post(BASE + "/reservas/", headers=h(token_cliente), json={
    "cancha_id": cancha_id, "fecha_reserva": manana,
    "hora_inicio": "20:00:00", "hora_fin": "19:00:00", "metodo_pago": "transferencia",
}, timeout=10)
check("Rechaza hora_fin anterior a hora_inicio (400)", r.status_code == 400, f"dio {r.status_code}")

r = requests.post(BASE + "/reservas/", headers=h(token_cliente), json={
    "cancha_id": cancha_id, "fecha_reserva": str(date.today() - timedelta(days=2)),
    "hora_inicio": "10:00:00", "hora_fin": "11:00:00", "metodo_pago": "transferencia",
}, timeout=10)
check("Rechaza una fecha pasada (400)", r.status_code == 400, f"dio {r.status_code}")

r = requests.post(BASE + "/reservas/", headers=h(token_cliente), json={
    "cancha_id": cancha_id, "fecha_reserva": manana,
    "hora_inicio": "10:00:00", "hora_fin": "11:00:00", "metodo_pago": "bitcoin",
}, timeout=10)
check("Rechaza un metodo de pago invalido (422)", r.status_code == 422, f"dio {r.status_code}")

print()
print("=" * 70)
print("5. COMPROBANTE DE DEPOSITO")
print("=" * 70)
r = requests.post(
    BASE + f"/reservas/{reserva_id}/comprobante",
    headers=h(token_cliente),
    files={"comprobante": ("deposito.png", io.BytesIO(PNG_1X1), "image/png")},
    timeout=15,
)
check("POST /reservas/{id}/comprobante responde 200", r.status_code == 200, r.text[:250])
comprobante_url = r.json().get("comprobante_url") if r.status_code == 200 else None
check("Devuelve 'comprobante_url'", bool(comprobante_url), str(r.text[:150]))
if comprobante_url:
    rc = requests.get("http://127.0.0.1:8000" + comprobante_url, timeout=10)
    check("El comprobante se sirve como archivo estatico", rc.status_code == 200, f"dio {rc.status_code}")

r = requests.post(
    BASE + f"/reservas/{reserva_id}/comprobante",
    headers=h(token_otro),
    files={"comprobante": ("x.png", io.BytesIO(PNG_1X1), "image/png")},
    timeout=10,
)
check("Otro usuario NO puede subir comprobante a una reserva ajena (403)", r.status_code == 403, f"dio {r.status_code}")

r = requests.post(
    BASE + f"/reservas/{reserva_id}/comprobante",
    headers=h(token_cliente),
    files={"comprobante": ("virus.exe", io.BytesIO(b"MZ"), "application/octet-stream")},
    timeout=10,
)
check("Rechaza un archivo que no es imagen ni PDF (400)", r.status_code == 400, f"dio {r.status_code}")

print()
print("=" * 70)
print("6. DISPONIBILIDAD")
print("=" * 70)
r = requests.get(BASE + f"/canchas/{cancha_id}/disponibilidad?fecha={manana}",
                 headers=h(token_cliente), timeout=10)
check("GET /canchas/{id}/disponibilidad responde 200", r.status_code == 200, r.text[:200])
ocupados = r.json() if r.status_code == 200 else []
check("Devuelve una lista de horarios ocupados", isinstance(ocupados, list) and len(ocupados) >= 1, str(ocupados)[:200])
if isinstance(ocupados, list) and ocupados:
    check("Cada bloque trae hora_inicio y hora_fin",
          "hora_inicio" in ocupados[0] and "hora_fin" in ocupados[0], str(ocupados[0]))

r = requests.get(BASE + f"/canchas/{cancha_id}/disponibilidad?fecha=01-10-2026",
                 headers=h(token_cliente), timeout=10)
check("Rechaza una fecha con formato invalido (400)", r.status_code == 400, f"dio {r.status_code}")

print()
print("=" * 70)
print("7. LISTAS DEL CLIENTE")
print("=" * 70)
r = requests.get(BASE + "/reservas/mis-reservas", headers=h(token_cliente), timeout=10)
check("GET /reservas/mis-reservas responde 200", r.status_code == 200, r.text[:200])
mis = r.json() if r.status_code == 200 else []
check("Aparece la reserva creada", any(x["id"] == reserva_id for x in mis), f"{len(mis)} reservas")
check("El cliente solo ve SUS reservas",
      all(x["usuario_id"] == usuario.get("id") for x in mis), "hay reservas de otros usuarios")

r = requests.get(BASE + "/reservas/historial", headers=h(token_cliente), timeout=10)
check("GET /reservas/historial responde 200", r.status_code == 200, r.text[:200])

r = requests.get(BASE + "/reservas/", headers=h(token_cliente), timeout=10)
check("GET /reservas/ responde 200", r.status_code == 200, r.text[:200])
todas_cliente = r.json() if r.status_code == 200 else []
check("Un cliente en GET /reservas/ solo obtiene las suyas",
      all(x["usuario_id"] == usuario.get("id") for x in todas_cliente), "se filtraron mal")

print()
print("=" * 70)
print("8. PANEL DEL ADMINISTRADOR")
print("=" * 70)
r = requests.get(BASE + "/reservas/pendientes", headers=h(token_cliente), timeout=10)
check("Un cliente NO puede ver /reservas/pendientes (403)", r.status_code == 403, f"dio {r.status_code}")

r = requests.put(BASE + f"/reservas/{reserva_id}/estado", headers=h(token_cliente),
                 json={"estado": "confirmada"}, timeout=10)
check("Un cliente NO puede autoconfirmarse la reserva (403)", r.status_code == 403, f"dio {r.status_code}")

r = requests.post(BASE + "/auth/login", json={"email": "admin@ejemplo.com", "password": "admin123"}, timeout=10)
check("Login del administrador", r.status_code == 200, r.text[:200])
token_admin = r.json().get("access_token", "") if r.status_code == 200 else ""
if r.status_code == 200:
    check("El admin tiene rol 'admin'", r.json()["usuario"]["rol"] == "admin", str(r.json()["usuario"]["rol"]))

if token_admin:
    r = requests.get(BASE + "/reservas/pendientes", headers=h(token_admin), timeout=10)
    check("GET /reservas/pendientes responde 200 para el admin", r.status_code == 200, r.text[:200])
    pendientes = r.json() if r.status_code == 200 else []
    check("La reserva pendiente aparece en la lista", any(x["id"] == reserva_id for x in pendientes), f"{len(pendientes)} pendientes")
    mia = next((x for x in pendientes if x["id"] == reserva_id), None)
    if mia:
        check("  el admin ve quien reservo (usuario anidado)",
              isinstance(mia.get("usuario"), dict) and mia["usuario"].get("nombre"), str(mia.get("usuario")))
        check("  el admin ve el comprobante_url", bool(mia.get("comprobante_url")), str(mia.get("comprobante_url")))

    r = requests.get(BASE + "/reservas/?estado=pendiente", headers=h(token_admin), timeout=10)
    check("GET /reservas/?estado=pendiente filtra por estado", r.status_code == 200, r.text[:150])
    if r.status_code == 200:
        check("  todas las devueltas estan pendientes",
              all(x["estado"] == "pendiente" for x in r.json()), "vino otro estado")

    # RECHAZAR: la app necesita que 'rechazada' se guarde como 'rechazada'
    r = requests.put(BASE + f"/reservas/{reserva_otro_id}/estado", headers=h(token_admin),
                     json={"estado": "rechazada", "motivo": "El comprobante no se ve"}, timeout=10)
    check("PUT /estado con 'rechazada' responde 200", r.status_code == 200, r.text[:250])
    if r.status_code == 200:
        rr = r.json()
        check("  el estado se guarda como 'rechazada' (antes se volvia 'cancelada')",
              rr.get("estado") == "rechazada", str(rr.get("estado")))
        check("  guarda el motivo", rr.get("motivo_cancelacion") == "El comprobante no se ve", str(rr.get("motivo_cancelacion")))

    # APROBAR
    r = requests.put(BASE + f"/reservas/{reserva_id}/estado", headers=h(token_admin),
                     json={"estado": "confirmada"}, timeout=10)
    check("PUT /estado con 'confirmada' responde 200", r.status_code == 200, r.text[:250])
    if r.status_code == 200:
        rr = r.json()
        check("  el estado queda 'confirmada'", rr.get("estado") == "confirmada", str(rr.get("estado")))
        check("  marca la reserva como pagada", rr.get("pagado") is True, str(rr.get("pagado")))
        check("  limpia el motivo de cancelacion", rr.get("motivo_cancelacion") is None, str(rr.get("motivo_cancelacion")))

    r = requests.put(BASE + f"/reservas/{reserva_id}/estado", headers=h(token_admin),
                     json={"estado": "inventado"}, timeout=10)
    check("Rechaza un estado que no existe (422)", r.status_code == 422, f"dio {r.status_code}")

    r = requests.get(BASE + "/dashboard/kpis", headers=h(token_admin), timeout=10)
    check("GET /dashboard/kpis responde 200 para el admin", r.status_code == 200, r.text[:200])

    r = requests.get(BASE + "/dashboard/kpis", headers=h(token_cliente), timeout=10)
    check("Un cliente NO puede ver /dashboard/kpis (403)", r.status_code == 403, f"dio {r.status_code}")

    # Edicion parcial de canchas: es lo que manda el panel web-admin al
    # cambiar solo el precio o al poner una cancha en mantenimiento.
    campos_cancha = ("nombre", "tipo_deporte", "tipo_superficie",
                     "capacidad_jugadores", "precio_hora", "activa")
    original = requests.get(BASE + f"/canchas/{cancha_id}", headers=h(token_admin), timeout=10).json()

    r = requests.put(BASE + f"/canchas/{cancha_id}", headers=h(token_admin),
                     json={"precio_hora": 175.0}, timeout=10)
    check("PUT /canchas/{id} acepta solo un campo (antes daba 422)", r.status_code == 200, r.text[:200])
    if r.status_code == 200:
        d = r.json()
        check("  aplica el precio nuevo", d["precio_hora"] == 175.0, str(d["precio_hora"]))
        check("  no borra los campos que no se enviaron",
              all(d[k] == original[k] for k in campos_cancha if k != "precio_hora"),
              str({k: d[k] for k in campos_cancha}))

    r = requests.put(BASE + f"/canchas/{cancha_id}", headers=h(token_admin),
                     json={"activa": 0}, timeout=10)
    check("PUT /canchas/{id} desactiva la cancha", r.status_code == 200 and r.json()["activa"] == 0, r.text[:150])
    listado = requests.get(BASE + "/canchas/", headers=h(token_admin), timeout=10).json()
    check("  la cancha desactivada sale del listado", all(c["id"] != cancha_id for c in listado), "sigue apareciendo")

    r = requests.put(BASE + f"/canchas/{cancha_id}", headers=h(token_admin), json={}, timeout=10)
    check("PUT /canchas/{id} con cuerpo vacio da 400", r.status_code == 400, f"dio {r.status_code}")

    # Dejar la cancha exactamente como estaba
    requests.put(BASE + f"/canchas/{cancha_id}", headers=h(token_admin),
                 json={k: original[k] for k in campos_cancha}, timeout=10)
    restaurada = requests.get(BASE + f"/canchas/{cancha_id}", headers=h(token_admin), timeout=10).json()
    check("La cancha queda restaurada como estaba",
          all(restaurada[k] == original[k] for k in campos_cancha),
          str({k: restaurada[k] for k in campos_cancha}))

print()
print("=" * 70)
print("9. PAGO CON TARJETA")
print("=" * 70)
r = requests.post(BASE + "/reservas/", headers=h(token_cliente), json={
    "cancha_id": cancha_id, "fecha_reserva": manana,
    "hora_inicio": "08:00:00", "hora_fin": "09:00:00", "metodo_pago": "tarjeta",
}, timeout=10)
check("Reserva pagada con tarjeta se crea (201)", r.status_code == 201, r.text[:250])
tarjeta = r.json() if r.status_code == 201 else {}
tarjeta_id = tarjeta.get("id")
check("Con tarjeta el estado queda 'confirmada' de una vez", tarjeta.get("estado") == "confirmada", str(tarjeta.get("estado")))
check("Con tarjeta queda marcada como pagada", tarjeta.get("pagado") is True, str(tarjeta.get("pagado")))

r = requests.post(BASE + f"/reservas/{tarjeta_id}/pago", headers=h(token_cliente), json={
    "metodo_pago": "tarjeta", "monto": 250.0, "referencia": "****4242", "estado": "confirmada",
}, timeout=10)
check("POST /reservas/{id}/pago responde 200", r.status_code == 200, r.text[:250])

r = requests.get(BASE + "/reservas/mis-reservas", headers=h(token_cliente), timeout=10)
si_hay = next((x for x in r.json() if x["id"] == tarjeta_id), None) if r.status_code == 200 else None
check("Guarda la referencia del pago (solo los ultimos 4 digitos)",
      si_hay is not None and si_hay.get("referencia_pago") == "****4242",
      str(si_hay.get("referencia_pago") if si_hay else None))

print()
print("=" * 70)
print("10. CANCELACION")
print("=" * 70)
r = requests.put(BASE + f"/reservas/{tarjeta_id}/cancelar?motivo=Ya%20no%20puedo%20ir",
                 headers=h(token_otro), timeout=10)
check("Otro usuario NO puede cancelar una reserva ajena (403)", r.status_code == 403, f"dio {r.status_code}")

r = requests.put(BASE + f"/reservas/{tarjeta_id}/cancelar?motivo=Ya%20no%20puedo%20ir",
                 headers=h(token_cliente), timeout=10)
check("PUT /reservas/{id}/cancelar responde 200", r.status_code == 200, r.text[:250])
if r.status_code == 200:
    check("  el estado queda 'cancelada'", r.json().get("estado") == "cancelada", r.text[:150])

r = requests.put(BASE + f"/reservas/{tarjeta_id}/cancelar", headers=h(token_cliente), timeout=10)
check("No se puede cancelar dos veces (400)", r.status_code == 400, f"dio {r.status_code}")

r = requests.get(BASE + "/reservas/historial", headers=h(token_cliente), timeout=10)
if r.status_code == 200:
    check("La reserva cancelada aparece en el historial",
          any(x["id"] == tarjeta_id for x in r.json()), f"{len(r.json())} en historial")

# El horario 08:00-09:00 acaba de quedar libre al cancelarse. Antes, el indice
# uq_cancha_horario lo dejaba bloqueado para siempre y la API respondia 500.
r = requests.post(BASE + "/reservas/", headers=h(token_otro), json={
    "cancha_id": cancha_id, "fecha_reserva": manana,
    "hora_inicio": "08:00:00", "hora_fin": "09:00:00", "metodo_pago": "transferencia",
}, timeout=10)
check("Un horario cancelado se puede volver a reservar (antes daba error 500)",
      r.status_code == 201, f"dio {r.status_code}: {r.text[:200]}")

# Y el horario rechazado por el admin (20:00-21:00) tambien debe liberarse.
r = requests.post(BASE + "/reservas/", headers=h(token_cliente), json={
    "cancha_id": cancha_id, "fecha_reserva": manana,
    "hora_inicio": "20:00:00", "hora_fin": "21:00:00", "metodo_pago": "transferencia",
}, timeout=10)
check("Un horario rechazado por el admin se puede volver a reservar",
      r.status_code == 201, f"dio {r.status_code}: {r.text[:200]}")

print()
print("=" * 70)
print("11. CHAT")
print("=" * 70)
r = requests.post(BASE + "/chat/", headers=h(token_cliente),
                  json={"mensaje": f"hay disponibilidad el {manana}?"}, timeout=45)
check("POST /chat/ responde 200", r.status_code == 200, r.text[:250])
if r.status_code == 200:
    check("  devuelve 'respuesta'", bool(r.json().get("respuesta")), r.text[:150])
    check("  detecta la intencion de disponibilidad",
          r.json().get("intencion") == "consultar_disponibilidad", str(r.json().get("intencion")))

r = requests.get(BASE + "/chat/historial", headers=h(token_cliente), timeout=10)
check("GET /chat/historial responde 200 (antes daba 404)", r.status_code == 200, r.text[:250])
if r.status_code == 200:
    hist = r.json()
    check("  devuelve una lista", isinstance(hist, list) and len(hist) >= 1, str(hist)[:150])
    if isinstance(hist, list) and hist:
        m = hist[0]
        for campo in ["mensaje_usuario", "respuesta_ia", "fecha_creacion", "intencion_detectada"]:
            check(f"  cada registro trae '{campo}'", campo in m, str(list(m.keys())))

r = requests.get(BASE + "/chat/historial", headers=h(token_otro), timeout=10)
check("El historial de chat es privado por usuario", r.status_code == 200 and len(r.json()) == 0,
      f"dio {r.status_code} con {len(r.json()) if r.status_code == 200 else '?'} mensajes")

print()
print("=" * 70)
print("12. LIMPIEZA")
print("=" * 70)
# Los usuarios y reservas de prueba se borran para no dejar horarios
# ocupados ni cuentas basura en la base de datos.
try:
    from sqlalchemy import text
    from app.database import engine

    with engine.begin() as cx:
        ids = [fila[0] for fila in cx.execute(
            text("SELECT id FROM usuarios WHERE email IN (:a, :b)"),
            {"a": email_cliente, "b": email_otro},
        )]
        if ids:
            marcadores = ", ".join(f":u{i}" for i in range(len(ids)))
            params = {f"u{i}": v for i, v in enumerate(ids)}
            n_res = cx.execute(
                text(f"DELETE FROM reservas WHERE usuario_id IN ({marcadores})"), params
            ).rowcount
            cx.execute(
                text(f"DELETE FROM conversaciones_ia WHERE usuario_id IN ({marcadores})"), params
            )
            n_usr = cx.execute(
                text(f"DELETE FROM usuarios WHERE id IN ({marcadores})"), params
            ).rowcount
            print(f"  Borradas {n_res} reservas y {n_usr} usuarios de prueba.")
        else:
            print("  Nada que borrar.")
except Exception as e:
    print(f"  AVISO: no se pudo limpiar automaticamente ({e}).")
    print(f"  Borra a mano los usuarios {email_cliente} y {email_otro}.")

print()
print("=" * 70)
print(f"RESULTADO: {ok_total} pruebas OK, {len(fallos)} fallos")
print("=" * 70)
if fallos:
    for f in fallos:
        print("  FALLO:", f)
    sys.exit(1)
print("Todo el flujo que usa la app Flutter funciona contra el backend.")
