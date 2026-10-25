# Endpoints del backend

Estado: **todos los endpoints que usa la app ya existen y están probados.**
La app ya no necesita guardar estados localmente para compensar lo que
faltaba; el backend persiste todo en MySQL.

Backend: `F:\Proyecto de graduacion\canchas-api` (FastAPI + MySQL)

Base configurada en `lib/services/api_service.dart`:

```dart
static const String baseUrl = 'http://192.168.1.7:8000/api';
```

> Es el **único** lugar donde se define. Si cambias de red y la PC toma otra
> IP, actualiza esa línea. Para verla: `ipconfig` y busca la IPv4 del adaptador
> conectado.

Para levantar la API:

```
cd "F:\Proyecto de graduacion\canchas-api"
venv\Scripts\python.exe -m uvicorn app.main:app --host 0.0.0.0 --port 8000
```

`--host 0.0.0.0` es obligatorio: con el valor por defecto (`127.0.0.1`) la API
solo acepta conexiones de la propia PC y el celular no la ve.

Documentación interactiva: <http://192.168.1.7:8000/docs>

---

## Autenticación

| Método | Ruta | Notas |
|---|---|---|
| POST | `/auth/registro` | Devuelve `access_token` + `usuario` |
| POST | `/auth/login` | Devuelve `access_token` + `usuario` (con `rol`) |
| POST | `/auth/google` | Recibe `{ "id_token": "..." }` |
| POST | `/auth/change-password` | `email`, `old_password`, `new_password` |

El objeto `usuario` incluye `id`, `nombre`, `email`, `telefono`, `rol`,
`foto_url`, `direccion`, `fecha_nacimiento`, `fecha_registro` y `activo`.
Por eso la app sabe si mostrar el panel de administración sin una llamada extra.

## Perfil

| Método | Ruta | Notas |
|---|---|---|
| GET | `/users/me` | Perfil del dueño del token (la app lo intenta primero) |
| GET | `/users/perfil/{email}` | Requiere token; solo tu propio perfil |
| PUT | `/users/perfil/{email}` | `multipart/form-data` |

El `PUT` acepta `nombre`, `telefono`, `direccion`, `fecha_nacimiento`
(`yyyy-MM-dd`) y el archivo `foto`. Todos opcionales: solo se cambia lo que
mandes.

> Un usuario **no** puede leer ni editar el perfil de otro: responde 403.

## Canchas

| Método | Ruta | Notas |
|---|---|---|
| GET | `/canchas/` | Solo las activas |
| GET | `/canchas/{id}` | |
| GET | `/canchas/{id}/disponibilidad?fecha=yyyy-MM-dd` | Horarios ya ocupados |
| POST | `/canchas/` | Solo `admin` / `dueño_cancha` |
| PUT | `/canchas/{id}` | Parcial: manda solo los campos a cambiar |
| DELETE | `/canchas/{id}` | Desactiva (no borra) |

## Reservas

| Método | Ruta | Notas |
|---|---|---|
| GET | `/reservas/` | El cliente solo ve las suyas; acepta `?estado=` |
| GET | `/reservas/mis-reservas` | Activas (pendiente + confirmada, futuras) |
| GET | `/reservas/historial` | Cerradas o ya jugadas |
| GET | `/reservas/pendientes` | Solo admin: las que esperan aprobación |
| POST | `/reservas/` | Crear |
| POST | `/reservas/{id}/comprobante` | Subir foto del depósito |
| POST | `/reservas/{id}/pago` | Constancia del cobro con tarjeta |
| PUT | `/reservas/{id}/estado` | Solo admin: aprobar / rechazar |
| PUT | `/reservas/{id}/cancelar` | El dueño de la reserva |

### Crear una reserva

La app manda:

```json
{
  "cancha_id": 3,
  "fecha_reserva": "2026-10-01",
  "hora_inicio": "18:00:00",
  "hora_fin": "19:00:00",
  "notas": "",
  "metodo_pago": "tarjeta"
}
```

**El servidor decide el estado y el precio, no el cliente:**

- `metodo_pago: "tarjeta"` → `estado: "confirmada"`, `pagado: true`
- `metodo_pago: "transferencia"` o `"efectivo"` → `estado: "pendiente"`

El `precio_total` se calcula con el precio de la cancha (y `precio_hora_pico`
a partir de las 18:00). Si la app manda `estado` o `precio_total`, se ignoran:
si no fuera así, cualquiera podría confirmarse una reserva sin pagar.

Errores esperados:

| Código | Cuándo |
|---|---|
| 400 | Horario ocupado, fecha pasada, u `hora_fin` <= `hora_inicio` |
| 422 | `metodo_pago` que no sea `tarjeta`, `transferencia` o `efectivo` |

### Respuesta de una reserva

```json
{
  "id": 41,
  "uuid": "...",
  "cancha_id": 3,
  "usuario_id": 7,
  "fecha_reserva": "2026-10-01",
  "hora_inicio": "18:00:00",
  "hora_fin": "19:00:00",
  "estado": "pendiente",
  "precio_total": 150.0,
  "metodo_pago": "transferencia",
  "pagado": false,
  "comprobante_url": "/static/comprobantes/reserva_41.jpg",
  "referencia_pago": null,
  "notas": "",
  "motivo_cancelacion": null,
  "fecha_cancelacion": null,
  "creado_por_ia": false,
  "fecha_creacion": "2026-09-08T10:12:00",
  "cancha":  { "id": 3, "nombre": "Cancha Norte", "imagen_url": null },
  "usuario": { "id": 7, "nombre": "Juan Pérez", "email": "j@x.com", "telefono": "..." }
}
```

`cancha` viene anidada siempre, así que la app muestra el nombre real en vez
de "Cancha #3". `usuario` es lo que el administrador usa para saber a quién
aprobar.

### Comprobante del depósito

```
POST /reservas/{id}/comprobante
Content-Type: multipart/form-data
Campo del archivo: "comprobante"
```

Acepta JPG, PNG, WEBP o PDF, hasta 5 MB. Responde
`{ "comprobante_url": "...", "estado": "pendiente", "reserva_id": 41 }`.

Subir el comprobante **no** confirma la reserva: sigue pendiente hasta que el
administrador la apruebe. Solo el dueño de la reserva puede subirlo (403 si no).

### Cambiar el estado (aprobar o rechazar)

```
PUT /reservas/{id}/estado
Body: { "estado": "confirmada", "motivo": "opcional" }
```

Estados válidos: `pendiente`, `confirmada`, `rechazada`, `completada`,
`cancelada`. Cualquier otro da 422.

- `rechazada` se guarda como `rechazada` (la app la distingue de una
  cancelación del usuario) y el `motivo` queda en `motivo_cancelacion`.
- `confirmada` marca `pagado: true` y limpia el motivo.
- Solo `admin` / `dueño_cancha`. Un cliente recibe 403, así que no puede
  autoconfirmarse una reserva.

Devuelve la reserva completa ya actualizada.

### Pago con tarjeta

```
POST /reservas/{id}/pago
Body: { "metodo_pago": "tarjeta", "monto": 250.0, "referencia": "****4242" }
```

> ⚠️ **Seguridad:** la app no envía el número completo de la tarjeta, el CVV ni
> el vencimiento, y el backend no tiene dónde guardarlos. Solo se persisten los
> últimos 4 dígitos en `referencia_pago`. Para cobrar de verdad hay que
> integrar una pasarela (Recurrente, Neonet, Cybersource, Stripe) y guardar
> únicamente el token que ella devuelva.

## Chat con IA

| Método | Ruta | Notas |
|---|---|---|
| POST | `/chat/` | `{ "mensaje": "..." }` |
| GET | `/chat/historial?limite=50` | Solo las conversaciones del usuario |

El historial devuelve registros con `mensaje_usuario`, `respuesta_ia`,
`intencion_detectada`, `resultado_accion` y `fecha_creacion`, en orden
cronológico. La app parte cada registro en dos globos.

## Dashboard (solo admin)

`/dashboard/kpis`, `/dashboard/ocupacion-semanal`,
`/dashboard/reservas-recientes`, `/dashboard/ranking-canchas`.

---

## Detalles del backend que conviene recordar

**Las reservas vencidas se cierran solas.** Al consultar cualquier lista, las
reservas `confirmada` cuya hora ya pasó se marcan `completada`. No hace falta
una tarea programada.

**Los horarios cancelados se liberan.** La base tenía un índice
`uq_cancha_horario` que bloqueaba para siempre un horario cancelado (la API
respondía 500 al reintentar). Se reemplazó por `uq_cancha_slot_activo`, que
ignora las reservas canceladas y rechazadas.

**Los solapamientos se detectan bien.** Antes, una reserva de 18:00 a 21:00
no chocaba contra una existente de 19:00 a 20:00, y se podía reservar dos veces
la misma cancha. Ya está corregido.

**Archivos estáticos.** Las fotos de perfil y los comprobantes se sirven desde
`/static/...`. La app arma la URL absoluta quitando el `/api` del `baseUrl`
(`ApiService.urlAbsoluta`).

## Si algo cambia en la base de datos

```
venv\Scripts\python.exe migrate.py
```

Es idempotente: revisa qué falta antes de tocar nada, así que se puede correr
todas las veces que quieras.

## Para verificar que el backend sigue bien

```
venv\Scripts\python.exe test_integracion.py
```

Recorre el mismo flujo que hace la app (registro, login, perfil, reservas,
comprobantes, aprobación del admin, cancelación y chat), comprueba también los
permisos, y borra sus datos de prueba al terminar.
