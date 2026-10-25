# Reserva Tu Cancha — App Flutter

App móvil para reservar canchas sintéticas, con pagos, estados de reserva,
historial y recordatorios locales.

## Cómo funciona una reserva

```
Elegir cancha → fecha y horario → método de pago
                                        │
        ┌───────────────────────────────┴──────────────────────────────┐
        │ TARJETA                                    TRANSFERENCIA     │
        │ Se cobra el total                          Sube comprobante  │
        │        ↓                                          ↓          │
        │  CONFIRMADA (al instante)                    PENDIENTE       │
        │  + recordatorio programado          (espera al administrador)│
        └───────────────────────────────┬──────────────────────────────┘
                                        ↓
                        El administrador revisa el depósito
                                 ↙            ↘
                          CONFIRMADA        RECHAZADA
                       + recordatorio      (notificación
                                            con el motivo)
                                 ↓
                     Pasa la fecha → COMPLETADA (historial)
```

En cualquier momento antes de jugarse, el usuario puede cancelar → **CANCELADA**.

## Estados

| Estado | Cuándo ocurre | Dónde se ve |
|---|---|---|
| **Pendiente** | Pagó por transferencia y falta que el admin valide el depósito | Pestaña *Pendientes* |
| **Confirmada** | Pagó con tarjeta, o el admin aprobó el depósito | Pestaña *Próximas* |
| **Rechazada** | El admin no pudo validar el comprobante | Pestaña *Historial* |
| **Completada** | Ya pasó la hora del partido | Pestaña *Historial* |
| **Cancelada** | El usuario la canceló | Pestaña *Historial* |

## Recordatorios

Se programan en el teléfono (no necesitan servidor) para cada reserva
**confirmada** y futura:

- **24 horas antes** — "Tu partido es mañana"
- **X horas antes** — configurable en *Perfil → Recordatorios* (1, 2, 3, 6 o 12 h; por defecto 2)

Además hay avisos inmediatos cuando el administrador aprueba o rechaza un pago.
Todo se puede apagar desde el perfil, y hay un botón para enviar una
notificación de prueba.

Los recordatorios se reprograman solos al abrir la app, al refrescar la lista de
reservas y después de reiniciar el teléfono.

## Estructura del proyecto

```
lib/
├── main.dart                        Arranque, sesión persistente, notificaciones
├── theme/app_theme.dart             Colores, tipografía y estilo de todos los widgets
├── utils/formato.dart               Fechas y montos en español
├── models/
│   ├── reserva_model.dart           Reserva + EstadoReserva + MetodoPago
│   ├── cancha_model.dart
│   ├── usuario_model.dart
│   └── mensaje_chat.dart
├── services/
│   ├── api_service.dart             Todas las llamadas al backend
│   ├── notificacion_service.dart    Programación de recordatorios
│   └── reserva_store.dart           Caché local del historial y de los estados
├── widgets/
│   ├── app_widgets.dart             Tarjetas, encabezados, chips, avisos
│   └── reserva_card.dart            Tarjeta de una reserva
└── screens/
    ├── login_screen.dart
    ├── register_screen.dart
    ├── main_shell.dart              Navegación inferior
    ├── home_screen.dart             Canchas + próxima reserva
    ├── pantalla_pago_screen.dart    Tarjeta / transferencia
    ├── mis_reservas_screen.dart     Próximas · Pendientes · Historial
    ├── detalle_reserva_screen.dart  Seguimiento paso a paso
    ├── profile_screen.dart          Perfil, estadísticas y ajustes
    ├── editar_perfil_screen.dart
    ├── admin_reservas_screen.dart   Aprobar / rechazar depósitos
    └── chat_screen.dart
```

## Configuración

**1. Dirección del servidor.** Se define en un solo lugar,
[lib/services/api_service.dart](lib/services/api_service.dart):

```dart
static const String baseUrl = 'http://192.168.1.7:8000/api';
```

Con un emulador Android usa `http://10.0.2.2:8000/api`; en un teléfono físico,
la IP de tu computadora en la red local.

**2. Endpoints del backend.** La app funciona con lo que ya tienes, pero para
que los estados queden guardados en la base de datos hay que añadir dos o tres
rutas. Está todo explicado en
[BACKEND_ENDPOINTS.md](BACKEND_ENDPOINTS.md).

**3. Acceso de administrador.** El panel de aprobaciones aparece cuando el
backend devuelve `"rol": "admin"` en el usuario al iniciar sesión.

## Correr el proyecto

```bash
flutter pub get
flutter run

flutter analyze     # revisión estática
flutter test        # pruebas de la lógica de estados
```

## Modo sin conexión

Las reservas se guardan en el teléfono (`shared_preferences`). Si el servidor no
responde, la app sigue mostrando tu historial y tus reservas pendientes con los
datos de la última sincronización.

## Nota sobre los pagos con tarjeta

El formulario valida el número con el algoritmo de Luhn, la fecha de
vencimiento y el CVV, pero **no realiza un cobro real** y no envía los datos de
la tarjeta a ningún servidor: solo los últimos 4 dígitos como referencia. Para
cobrar de verdad hay que integrar una pasarela (Recurrente, Neonet,
Cybersource, Stripe) y guardar únicamente el token que devuelve. El punto de
integración está marcado en `ApiService.registrarPagoTarjeta`.
