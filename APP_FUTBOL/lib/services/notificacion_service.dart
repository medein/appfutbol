import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show PlatformException;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../models/reserva_model.dart';

/// Recordatorios locales de reservas.
///
/// Programa dos avisos por reserva confirmada:
///   * 24 horas antes  (id = reservaId * 10 + 1)
///   * 2 horas antes   (id = reservaId * 10 + 2)
/// Y avisa cuando el administrador aprueba o rechaza una reserva pagada
/// por transferencia.
class NotificacionService {
  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  static const String _canalRecordatorios = 'reservas_recordatorios';
  static const String _canalEstados = 'reservas_estados';
  static const String _prefAnticipacionHoras = 'notif_anticipacion_horas';
  static const String _prefActivas = 'notif_activas';

  static bool _inicializado = false;

  /// Llamar una sola vez en main() antes de runApp().
  static Future<void> init() async {
    if (_inicializado) return;

    tzdata.initializeTimeZones();
    try {
      final nombreZona = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(nombreZona));
    } catch (e) {
      // Guatemala como respaldo si el dispositivo no reporta su zona.
      debugPrint('No se pudo leer la zona horaria del dispositivo: $e');
      tz.setLocalLocation(tz.getLocation('America/Guatemala'));
    }

    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosInit = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );

    await _plugin.initialize(
      const InitializationSettings(android: androidInit, iOS: iosInit),
    );

    // Crea los canales en Android para que el usuario pueda administrarlos
    // desde los ajustes del sistema.
    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    await android?.createNotificationChannel(
      const AndroidNotificationChannel(
        _canalRecordatorios,
        'Recordatorios de reservas',
        description: 'Avisos antes de que empiece tu partido',
        importance: Importance.max,
      ),
    );
    await android?.createNotificationChannel(
      const AndroidNotificationChannel(
        _canalEstados,
        'Estado de reservas',
        description: 'Avisos cuando el administrador aprueba o rechaza tu pago',
        importance: Importance.high,
      ),
    );

    _inicializado = true;
  }

  /// Pide el permiso de notificaciones (Android 13+ e iOS).
  static Future<bool> pedirPermisos() async {
    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    if (android != null) {
      final concedido = await android.requestNotificationsPermission();
      // Necesario para que las alarmas exactas funcionen en Android 12+.
      await android.requestExactAlarmsPermission();
      return concedido ?? false;
    }

    final ios = _plugin.resolvePlatformSpecificImplementation<
        IOSFlutterLocalNotificationsPlugin>();
    final concedidoIos = await ios?.requestPermissions(
      alert: true,
      badge: true,
      sound: true,
    );
    return concedidoIos ?? true;
  }

  // ---------------------------------------------------------------------------
  // Preferencias del usuario
  // ---------------------------------------------------------------------------

  static Future<bool> notificacionesActivas() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_prefActivas) ?? true;
  }

  static Future<void> setNotificacionesActivas(bool valor) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefActivas, valor);
    if (!valor) await cancelarTodo();
  }

  /// Horas de anticipación del recordatorio principal (por defecto 2 h).
  static Future<int> anticipacionHoras() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_prefAnticipacionHoras) ?? 2;
  }

  static Future<void> setAnticipacionHoras(int horas) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_prefAnticipacionHoras, horas);
  }

  // ---------------------------------------------------------------------------
  // Programación de recordatorios
  // ---------------------------------------------------------------------------

  static int _idRecordatorioLargo(int reservaId) => reservaId * 10 + 1;
  static int _idRecordatorioCorto(int reservaId) => reservaId * 10 + 2;

  /// Programa (o reprograma) los recordatorios de una reserva.
  /// Solo lo hace si la reserva está confirmada y aún no ha pasado.
  static Future<void> programarRecordatorio(Reserva reserva) async {
    await init();
    if (!await notificacionesActivas()) return;

    // Siempre limpiamos primero para no duplicar avisos al recargar la lista.
    await cancelarRecordatorio(reserva.id);

    if (!reserva.admiteRecordatorio) return;

    final inicio = reserva.inicio;
    if (inicio == null) return;

    final horas = await anticipacionHoras();

    // Aviso del día anterior (24 h antes).
    await _agendar(
      id: _idRecordatorioLargo(reserva.id),
      cuando: inicio.subtract(const Duration(hours: 24)),
      titulo: '⚽ Tu partido es mañana',
      cuerpo: '${reserva.canchaNombre} · ${_fechaLegible(inicio)} a las '
          '${reserva.rangoHorario.split(' - ').first}',
      canal: _canalRecordatorios,
      payload: 'reserva:${reserva.id}',
    );

    // Aviso cercano, configurable por el usuario.
    await _agendar(
      id: _idRecordatorioCorto(reserva.id),
      cuando: inicio.subtract(Duration(hours: horas)),
      titulo: '⏰ ¡Ya casi es tu hora!',
      cuerpo: 'Tu reserva en ${reserva.canchaNombre} empieza en '
          '$horas ${horas == 1 ? 'hora' : 'horas'} '
          '(${reserva.rangoHorario}).',
      canal: _canalRecordatorios,
      payload: 'reserva:${reserva.id}',
    );
  }

  /// Reprograma los recordatorios de toda la lista de reservas activas.
  static Future<void> sincronizarRecordatorios(List<Reserva> reservas) async {
    await init();
    for (final r in reservas) {
      if (r.admiteRecordatorio) {
        await programarRecordatorio(r);
      } else {
        await cancelarRecordatorio(r.id);
      }
    }
  }

  static Future<void> cancelarRecordatorio(int reservaId) async {
    await init();
    await _plugin.cancel(_idRecordatorioLargo(reservaId));
    await _plugin.cancel(_idRecordatorioCorto(reservaId));
  }

  static Future<void> cancelarTodo() async {
    await init();
    await _plugin.cancelAll();
  }

  /// Aviso inmediato de cambio de estado (aprobación / rechazo del depósito).
  static Future<void> avisarCambioEstado(Reserva reserva) async {
    await init();
    if (!await notificacionesActivas()) return;

    String titulo;
    String cuerpo;
    switch (reserva.estadoEfectivo) {
      case EstadoReserva.confirmada:
        titulo = '✅ Reserva confirmada';
        cuerpo = 'Tu pago fue validado. ${reserva.canchaNombre} te espera el '
            '${_fechaLegible(reserva.inicio)} (${reserva.rangoHorario}).';
        break;
      case EstadoReserva.rechazada:
        titulo = '❌ No pudimos validar tu pago';
        cuerpo = 'Revisa el comprobante de tu reserva en '
            '${reserva.canchaNombre} e inténtalo de nuevo.';
        break;
      case EstadoReserva.pendiente:
        titulo = '🕓 Reserva en revisión';
        cuerpo = 'Recibimos tu comprobante de ${reserva.canchaNombre}. '
            'Te avisaremos al confirmar el depósito.';
        break;
      case EstadoReserva.cancelada:
        titulo = 'Reserva cancelada';
        cuerpo = 'Cancelamos tu reserva en ${reserva.canchaNombre}.';
        break;
      case EstadoReserva.completada:
        return; // no vale la pena notificar esto
    }

    await _plugin.show(
      DateTime.now().millisecondsSinceEpoch.remainder(100000),
      titulo,
      cuerpo,
      NotificationDetails(
        android: AndroidNotificationDetails(
          _canalEstados,
          'Estado de reservas',
          channelDescription:
              'Avisos cuando el administrador aprueba o rechaza tu pago',
          importance: Importance.high,
          priority: Priority.high,
          styleInformation: BigTextStyleInformation(cuerpo),
        ),
        iOS: const DarwinNotificationDetails(),
      ),
      payload: 'reserva:${reserva.id}',
    );
  }

  /// Notificación de prueba, para que el usuario confirme que todo funciona.
  static Future<void> notificacionDePrueba() async {
    await init();
    await _plugin.show(
      99999,
      '🔔 Notificaciones activas',
      'Así te avisaremos cuando se acerque la hora de tu reserva.',
      const NotificationDetails(
        android: AndroidNotificationDetails(
          _canalRecordatorios,
          'Recordatorios de reservas',
          importance: Importance.max,
          priority: Priority.high,
        ),
        iOS: DarwinNotificationDetails(),
      ),
    );
  }

  /// Lista los recordatorios que quedaron agendados (útil para depurar).
  static Future<List<PendingNotificationRequest>> pendientes() async {
    await init();
    return _plugin.pendingNotificationRequests();
  }

  // ---------------------------------------------------------------------------
  // Internos
  // ---------------------------------------------------------------------------

  static Future<void> _agendar({
    required int id,
    required DateTime cuando,
    required String titulo,
    required String cuerpo,
    required String canal,
    String? payload,
  }) async {
    // No tiene sentido agendar algo en el pasado.
    if (!cuando.isAfter(DateTime.now())) return;

    final fechaTz = tz.TZDateTime.from(cuando, tz.local);

    try {
      await _plugin.zonedSchedule(
        id,
        titulo,
        cuerpo,
        fechaTz,
        NotificationDetails(
          android: AndroidNotificationDetails(
            canal,
            canal == _canalRecordatorios
                ? 'Recordatorios de reservas'
                : 'Estado de reservas',
            channelDescription: 'Avisos antes de que empiece tu partido',
            importance: Importance.max,
            priority: Priority.high,
            styleInformation: BigTextStyleInformation(cuerpo),
          ),
          iOS: const DarwinNotificationDetails(),
        ),
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
        payload: payload,
      );
    } on PlatformException catch (e) {
      // Si el usuario no concedió el permiso de alarmas exactas, reintentamos
      // en modo inexacto para no perder el recordatorio.
      debugPrint('Alarma exacta no disponible ($e); se agenda inexacta.');
      await _plugin.zonedSchedule(
        id,
        titulo,
        cuerpo,
        fechaTz,
        NotificationDetails(
          android: AndroidNotificationDetails(
            canal,
            'Recordatorios de reservas',
            importance: Importance.max,
            priority: Priority.high,
          ),
          iOS: const DarwinNotificationDetails(),
        ),
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
        payload: payload,
      );
    }
  }

  static String _fechaLegible(DateTime? fecha) {
    if (fecha == null) return '';
    const meses = [
      'ene', 'feb', 'mar', 'abr', 'may', 'jun',
      'jul', 'ago', 'sep', 'oct', 'nov', 'dic',
    ];
    return '${fecha.day} ${meses[fecha.month - 1]}';
  }
}
