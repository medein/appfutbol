import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../models/cancha_model.dart';
import '../models/complejo_model.dart';
import '../models/mensaje_chat.dart';
import '../models/reserva_model.dart';
import '../models/usuario_model.dart';
import 'reserva_store.dart';


/// Resultado uniforme de las operaciones que pueden fallar.
class Resultado<T> {
  final bool exito;
  final String? mensaje;
  final T? datos;

  const Resultado.ok(this.datos, {this.mensaje}) : exito = true;
  const Resultado.error(this.mensaje) : exito = false, datos = null;
}

class ApiService {
  /// IP local del backend FastAPI.
  static const String baseUrl = 'http://192.168.1.5:8000/api';

  /// Host sin el sufijo /api, para las imágenes servidas como archivos estáticos.
  static String get hostBase => baseUrl.replaceAll('/api', '');

  static const Duration _timeout = Duration(seconds: 120);

  static final GoogleSignIn _googleSignIn = GoogleSignIn(
    scopes: ['email', 'profile'],
  );

  // ---------------------------------------------------------------------------
  // Sesión
  // ---------------------------------------------------------------------------

  static Future<String?> getToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('token');
  }

  static Future<String?> getEmail() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('email');
  }

  static Future<bool> haySesion() async {
    final token = await getToken();
    return token != null && token.isNotEmpty;
  }

  static Future<void> _guardarSesion({
    required String token,
    String? email,
    String? nombre,
    String? rol,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('token', token);
    if (email != null && email.isNotEmpty) {
      await prefs.setString('email', email);
    }
    if (nombre != null && nombre.isNotEmpty) {
      await prefs.setString('nombre', nombre);
    }
    if (rol != null && rol.isNotEmpty) {
      await prefs.setString('rol', rol);
    }
  }

  static Future<String> getRol() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('rol') ?? 'cliente';
  }

  static Future<bool> esAdmin() async {
    final rol = (await getRol()).toLowerCase();
    return rol == 'admin' || rol == 'administrador' || rol == 'superadmin';
  }

  static Future<void> cerrarSesion() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('token');
    await prefs.remove('email');
    await prefs.remove('nombre');
    await prefs.remove('rol');
    await ReservaStore.limpiar();
    try {
      await _googleSignIn.signOut();
    } catch (e) {
      debugPrint('Google signOut: $e');
    }
  }

  static Future<Map<String, String>> _getHeaders() async {
    final token = await getToken();
    return {
      'Content-Type': 'application/json',
      'Accept': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }

  /// Extrae el mensaje de error que manda FastAPI en `detail`.
  static String _mensajeError(http.Response response, String porDefecto) {
    try {
      final data = jsonDecode(response.body);
      if (data is Map) {
        final detail = data['detail'] ?? data['message'] ?? data['mensaje'];
        if (detail is String && detail.isNotEmpty) return detail;
        if (detail is List && detail.isNotEmpty) {
          final primero = detail.first;
          if (primero is Map && primero['msg'] != null) {
            return primero['msg'].toString();
          }
        }
      }
    } catch (_) {
      // El cuerpo no era JSON; usamos el mensaje por defecto.
    }
    return '$porDefecto (código ${response.statusCode})';
  }

  // ---------------------------------------------------------------------------
  // Autenticación
  // ---------------------------------------------------------------------------

  static Future<Resultado<void>> login(String email, String password) async {
    try {
      final response = await http
          .post(
            Uri.parse('$baseUrl/auth/login'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'email': email, 'password': password}),
          )
          .timeout(_timeout);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final usuario = data['usuario'] ?? data['user'];
        await _guardarSesion(
          token: data['access_token']?.toString() ?? '',
          email: (usuario is Map ? usuario['email']?.toString() : null) ?? email,
          nombre: usuario is Map ? usuario['nombre']?.toString() : null,
          rol: usuario is Map ? usuario['rol']?.toString() : null,
        );
        return const Resultado.ok(null);
      }
      return Resultado.error(_mensajeError(response, 'Credenciales incorrectas'));
    } on SocketException {
      return const Resultado.error(
          'No pudimos conectar con el servidor. Revisa tu conexión.');
    } catch (e) {
      debugPrint('ERROR EN LOGIN: $e');
      return const Resultado.error('Ocurrió un error al iniciar sesión.');
    }
  }

  static Future<Resultado<void>> register({
    required String nombre,
    required String email,
    required String password,
    String? telefono,
  }) async {
    try {
      final response = await http
          .post(
            Uri.parse('$baseUrl/auth/registro'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'nombre': nombre,
              'email': email,
              'password': password,
              if (telefono != null && telefono.isNotEmpty) 'telefono': telefono,
            }),
          )
          .timeout(_timeout);

      if (response.statusCode == 200 || response.statusCode == 201) {
        final data = jsonDecode(response.body);
        if (data is Map && data['access_token'] != null) {
          await _guardarSesion(
            token: data['access_token'].toString(),
            email: email,
            nombre: nombre,
          );
        }
        return const Resultado.ok(null);
      }
      return Resultado.error(_mensajeError(response, 'No se pudo crear la cuenta'));
    } on SocketException {
      return const Resultado.error(
          'No pudimos conectar con el servidor. Revisa tu conexión.');
    } catch (e) {
      debugPrint('ERROR EN REGISTRO: $e');
      return const Resultado.error('Ocurrió un error al registrarte.');
    }
  }

  static Future<Resultado<void>> loginConGoogle() async {
    try {
      await _googleSignIn.signOut();
      final googleUser = await _googleSignIn.signIn();
      if (googleUser == null) {
        return const Resultado.error('Inicio de sesión cancelado');
      }

      final googleAuth = await googleUser.authentication;
      final idToken = googleAuth.idToken;
      if (idToken == null) {
        return const Resultado.error('Google no devolvió un token válido');
      }

      final response = await http
          .post(
            Uri.parse('$baseUrl/auth/google'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'id_token': idToken}),
          )
          .timeout(_timeout);

      if (response.statusCode == 200 || response.statusCode == 201) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final usuario = data['usuario'] ?? data['user'];
        await _guardarSesion(
          token: data['access_token']?.toString() ?? '',
          email: (usuario is Map ? usuario['email']?.toString() : null) ??
              googleUser.email,
          nombre: (usuario is Map ? usuario['nombre']?.toString() : null) ??
              googleUser.displayName,
          rol: usuario is Map ? usuario['rol']?.toString() : null,
        );
        return const Resultado.ok(null);
      }
      return Resultado.error(
          _mensajeError(response, 'No se pudo iniciar sesión con Google'));
    } on SocketException {
      return const Resultado.error('No pudimos conectar con el servidor.');
    } catch (e) {
      debugPrint('ERROR EN GOOGLE SIGN-IN: $e');
      return const Resultado.error('Ocurrió un error con Google Sign-In.');
    }
  }

  static Future<Resultado<void>> cambiarPassword({
    required String email,
    required String oldPassword,
    required String newPassword,
  }) async {
    try {
      final response = await http
          .post(
            Uri.parse('$baseUrl/auth/change-password'),
            headers: await _getHeaders(),
            body: jsonEncode({
              'email': email,
              'old_password': oldPassword,
              'new_password': newPassword,
            }),
          )
          .timeout(_timeout);

      if (response.statusCode == 200) {
        return const Resultado.ok(null, mensaje: 'Contraseña actualizada');
      }
      return Resultado.error(
          _mensajeError(response, 'No se pudo actualizar la contraseña'));
    } on SocketException {
      return const Resultado.error('No pudimos conectar con el servidor.');
    } catch (e) {
      debugPrint('ERROR EN CAMBIAR PASSWORD: $e');
      return const Resultado.error('Ocurrió un error al cambiar la contraseña.');
    }
  }

  // ---------------------------------------------------------------------------
  // Canchas
  // ---------------------------------------------------------------------------

  /// Lista las canchas. Si se pasa [complejoId], el backend filtra por complejo.
  static Future<List<Cancha>> getCanchas({int? complejoId}) async {
    try {
      final query =
          complejoId != null ? '?complejo_id=$complejoId' : '';
      final response = await http
          .get(
            Uri.parse('$baseUrl/canchas/$query'),
            headers: await _getHeaders(),
          )
          .timeout(_timeout);

      if (response.statusCode == 401) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.remove('token');
        return [];
      }

      if (response.statusCode == 200) {
        final body = jsonDecode(response.body);
        // Puede venir como List directa o envuelto en {data: [...]}.
        final lista = body is List ? body : (body['data'] ?? body['items']);
        if (lista is List) {
          return lista
              .whereType<Map<String, dynamic>>()
              .map(Cancha.fromJson)
              .toList();
        }
      }
    } catch (e) {
      debugPrint('ERROR EN GET CANCHAS: $e');
    }
    return [];
  }

  /// Horarios ya ocupados de una cancha en una fecha (yyyy-MM-dd).
  static Future<List<Reserva>> getDisponibilidad({
    required int canchaId,
    required String fecha,
  }) async {
    try {
      final response = await http
          .get(
            Uri.parse('$baseUrl/canchas/$canchaId/disponibilidad?fecha=$fecha'),
            headers: await _getHeaders(),
          )
          .timeout(_timeout);

      if (response.statusCode == 200) {
        final body = jsonDecode(response.body);
        final lista =
            body is List ? body : (body['ocupados'] ?? body['reservas']);
        if (lista is List) {
          return lista
              .whereType<Map<String, dynamic>>()
              .map(Reserva.fromJson)
              .toList();
        }
      }
    } catch (e) {
      debugPrint('Disponibilidad no disponible: $e');
    }
    return [];
  }

  // ---------------------------------------------------------------------------
  // Complejos (antes "sedes")
  // ---------------------------------------------------------------------------

  /// Lista todos los complejos activos.
  static Future<Resultado<List<Complejo>>> getComplejos({
  double? latitud,
  double? longitud,
}) async {
  try {
    final params = <String, String>{};
    if (latitud != null && longitud != null) {
      params['latitud'] = latitud.toString();
      params['longitud'] = longitud.toString();
    }
    final uri = Uri.parse('$baseUrl/complejos').replace(
      queryParameters: params.isEmpty ? null : params,
    );

    final response = await http
        .get(uri, headers: await _getHeaders())
        .timeout(_timeout);

    if (response.statusCode != 200) {
      return Resultado.error(
          _mensajeError(response, 'No se pudieron cargar los complejos'));
    }

    final data = jsonDecode(response.body);
    final lista = data is Map ? (data['data'] ?? data['items']) : data;
    if (lista is! List) {
      return const Resultado.error('Respuesta inesperada del servidor');
    }
    final complejos = lista
        .whereType<Map<String, dynamic>>()
        .map(Complejo.fromJson)
        .toList();
    return Resultado.ok(complejos);
  } on SocketException {
    return const Resultado.error(
        'No pudimos conectar con el servidor. Revisa tu conexión.');
  } catch (e) {
    debugPrint('ERROR EN GET COMPLEJOS: $e');
    return const Resultado.error('Ocurrió un error al cargar los complejos.');
  }
}

  /// Recuerda el complejo elegido para no pedirlo en cada apertura de la app.
  static Future<void> guardarComplejo(Complejo complejo) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('complejo_id', complejo.id);
    await prefs.setString('complejo_nombre', complejo.nombre);
  }

  static Future<int?> getComplejoGuardadoId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt('complejo_id');
  }

  static Future<String?> getComplejoGuardadoNombre() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('complejo_nombre');
  }

  static Future<void> olvidarComplejo() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('complejo_id');
    await prefs.remove('complejo_nombre');
  }

  // ---------------------------------------------------------------------------
  // Reservas
  // ---------------------------------------------------------------------------

  /// Trae las reservas activas y el historial, las fusiona con el caché local
  /// y aplica el estado / método de pago guardado en el dispositivo.
  static Future<List<Reserva>> getTodasMisReservas() async {
    final activas = await _getLista('$baseUrl/reservas/mis-reservas');
    final historial = await _getLista('$baseUrl/reservas/historial');

    final crudas = [...activas.reservas, ...historial.reservas];

    if (crudas.isEmpty && !activas.respondio && !historial.respondio) {
      return ReservaStore.leerCache();
    }

    final porId = <int, Reserva>{};
    for (final r in crudas) {
      porId[r.id] = r;
    }

    final campos = {...activas.campos, ...historial.campos};
    var lista = await ReservaStore.aplicarOverlay(
      porId.values.toList(),
      camposQueEnviaElBackend: campos,
    );

    lista = await ReservaStore.fusionarConCache(lista);
    return lista;
  }

  static Future<_RespuestaLista> _getLista(String url) async {
    try {
      final response = await http
          .get(Uri.parse(url), headers: await _getHeaders())
          .timeout(_timeout);

      if (response.statusCode == 200) {
        final body = jsonDecode(response.body);
        final lista = body is List ? body : (body['items'] ?? body['reservas']);
        if (lista is List) {
          final mapas = lista.whereType<Map<String, dynamic>>().toList();
          final campos = mapas.isEmpty ? <String>{} : mapas.first.keys.toSet();
          return _RespuestaLista(
            reservas: mapas.map(Reserva.fromJson).toList(),
            campos: campos,
            respondio: true,
          );
        }
      }
      return _RespuestaLista(
        reservas: const [],
        campos: const {},
        respondio: response.statusCode == 404,
      );
    } catch (e) {
      debugPrint('ERROR AL LEER $url: $e');
      return const _RespuestaLista(
          reservas: [], campos: {}, respondio: false);
    }
  }

  /// Solo las reservas que siguen vigentes (pendientes + confirmadas futuras).
  static Future<List<Reserva>> getReservasProximas() async {
    final todas = await getTodasMisReservas();
    final proximas = todas.where((r) => r.esProxima).toList()
      ..sort((a, b) {
        final ai = a.inicio, bi = b.inicio;
        if (ai == null || bi == null) return 0;
        return ai.compareTo(bi);
      });
    return proximas;
  }

  static Future<Resultado<Reserva>> crearReserva({
    required int canchaId,
    required String canchaNombre,
    required String fecha,
    required String horaInicio,
    required String horaFin,
    required double montoTotal,
    required MetodoPago metodoPago,
    String notas = '',
  }) async {
    try {
      final horaInicioFmt = _formatearHora(horaInicio);
      final horaFinFmt = _formatearHora(horaFin);
      final estadoInicial = metodoPago.estadoInicial;

      final response = await http
          .post(
            Uri.parse('$baseUrl/reservas/'),
            headers: await _getHeaders(),
            body: jsonEncode({
              'cancha_id': canchaId,
              'fecha_reserva': fecha,
              'hora_inicio': horaInicioFmt,
              'hora_fin': horaFinFmt,
              'notas': notas,
              'metodo_pago': metodoPago.apiValue,
              'estado': estadoInicial.apiValue,
              'precio_total': montoTotal,
            }),
          )
          .timeout(_timeout);

      if (response.statusCode == 200 || response.statusCode == 201) {
        Reserva? reserva;
        try {
          final data = jsonDecode(response.body);
          final mapa = data is Map<String, dynamic>
              ? (data['reserva'] is Map<String, dynamic>
                  ? data['reserva'] as Map<String, dynamic>
                  : data)
              : null;
          if (mapa != null && mapa['id'] != null) {
            reserva = Reserva.fromJson(mapa);
          }
        } catch (e) {
          debugPrint('La respuesta de crearReserva no traía la reserva: $e');
        }

        reserva ??= await _buscarReservaRecien(
          canchaId: canchaId,
          fecha: fecha,
          horaInicio: horaInicioFmt,
        );

        reserva ??= Reserva(
          id: DateTime.now().millisecondsSinceEpoch.remainder(1000000),
          canchaId: canchaId,
          canchaNombre: canchaNombre,
          fecha: fecha,
          horaInicio: horaInicioFmt,
          horaFin: horaFinFmt,
          montoTotal: montoTotal,
          estado: estadoInicial,
          metodoPago: metodoPago,
          notas: notas,
          fechaCreacion: DateTime.now(),
        );

        final normalizada = reserva.copyWith(
          estado: estadoInicial,
          metodoPago: metodoPago,
        );

        await ReservaStore.registrarPago(
          reservaId: normalizada.id,
          metodoPago: metodoPago,
          estado: estadoInicial,
        );

        return Resultado.ok(normalizada);
      }

      return Resultado.error(
          _mensajeError(response, 'No se pudo crear la reserva'));
    } on SocketException {
      return const Resultado.error(
          'No pudimos conectar con el servidor. Revisa tu conexión.');
    } catch (e) {
      debugPrint('ERROR AL CREAR RESERVA: $e');
      return const Resultado.error('Ocurrió un error al crear la reserva.');
    }
  }

  static Future<Reserva?> _buscarReservaRecien({
    required int canchaId,
    required String fecha,
    required String horaInicio,
  }) async {
    try {
      final respuesta = await _getLista('$baseUrl/reservas/mis-reservas');
      final coincidencias = respuesta.reservas.where((r) =>
          r.canchaId == canchaId &&
          r.fecha == fecha &&
          Reserva.horaIgual(r.horaInicio, horaInicio));
      if (coincidencias.isEmpty) return null;
      return coincidencias.reduce((a, b) => a.id >= b.id ? a : b);
    } catch (e) {
      debugPrint('No se pudo localizar la reserva creada: $e');
      return null;
    }
  }

  static Future<Resultado<String?>> subirComprobante({
    required int reservaId,
    required File imagen,
  }) async {
    try {
      final token = await getToken();
      final request = http.MultipartRequest(
        'POST',
        Uri.parse('$baseUrl/reservas/$reservaId/comprobante'),
      );
      if (token != null) {
        request.headers['Authorization'] = 'Bearer $token';
      }
      request.files
          .add(await http.MultipartFile.fromPath('comprobante', imagen.path));

      final streamed = await request.send().timeout(_timeout);
      final response = await http.Response.fromStream(streamed);

      if (response.statusCode == 200 || response.statusCode == 201) {
        String? url;
        try {
          final data = jsonDecode(response.body);
          if (data is Map) {
            url = (data['comprobante_url'] ?? data['url'])?.toString();
          }
        } catch (_) {}
        await ReservaStore.registrarPago(
          reservaId: reservaId,
          metodoPago: MetodoPago.transferencia,
          estado: EstadoReserva.pendiente,
          comprobanteUrl: url,
        );
        return Resultado.ok(url);
      }

      if (response.statusCode == 404 || response.statusCode == 405) {
        debugPrint(
            'El backend aún no expone /reservas/{id}/comprobante; la reserva '
            'queda pendiente de validación manual.');
        return const Resultado.ok(null);
      }

      return Resultado.error(
          _mensajeError(response, 'No se pudo subir el comprobante'));
    } on SocketException {
      return const Resultado.error(
          'No pudimos subir el comprobante. Revisa tu conexión.');
    } catch (e) {
      debugPrint('ERROR AL SUBIR COMPROBANTE: $e');
      return const Resultado.error('Ocurrió un error al subir el comprobante.');
    }
  }

  static Future<Resultado<void>> registrarPagoTarjeta({
    required int reservaId,
    required double monto,
    required String ultimos4,
  }) async {
    try {
      final response = await http
          .post(
            Uri.parse('$baseUrl/reservas/$reservaId/pago'),
            headers: await _getHeaders(),
            body: jsonEncode({
              'metodo_pago': MetodoPago.tarjeta.apiValue,
              'monto': monto,
              'referencia': '****$ultimos4',
              'estado': EstadoReserva.confirmada.apiValue,
            }),
          )
          .timeout(_timeout);

      await ReservaStore.registrarPago(
        reservaId: reservaId,
        metodoPago: MetodoPago.tarjeta,
        estado: EstadoReserva.confirmada,
      );

      if (response.statusCode == 200 ||
          response.statusCode == 201 ||
          response.statusCode == 404 ||
          response.statusCode == 405) {
        return const Resultado.ok(null);
      }
      return Resultado.error(
          _mensajeError(response, 'No se pudo registrar el pago'));
    } catch (e) {
      debugPrint('ERROR AL REGISTRAR PAGO CON TARJETA: $e');
      return const Resultado.ok(null);
    }
  }

  // ---------------------------------------------------------------------------
  // NUEVO: Pasarela de pagos Recurrente
  // ---------------------------------------------------------------------------

  /// Llama a FastAPI para generar el link de pago de Recurrente.
  static Future<String?> generarLinkPago(int reservaId) async {
    try {
      final response = await http
          .post(
            Uri.parse('$baseUrl/crear-pago'), // Nota: baseUrl ya incluye /api
            headers: await _getHeaders(),
            body: jsonEncode({'reserva_id': reservaId}),
          )
          .timeout(_timeout);

      if (response.statusCode == 200 || response.statusCode == 201) {
        final data = jsonDecode(response.body);
        return data['checkout_url']; // Retorna la URL de Recurrente
      }
      
      debugPrint('Error al generar link de pago: ${response.body}');
      return null;
    } catch (e) {
      debugPrint('Error de red al generar pago: $e');
      return null;
    }
  }

  // ---------------------------------------------------------------------------

  static Future<Resultado<void>> cancelarReserva(
      int reservaId, String motivo) async {
    try {
      final texto =
          motivo.trim().isEmpty ? 'Cancelado por el usuario' : motivo.trim();
      final response = await http
          .put(
            Uri.parse(
                '$baseUrl/reservas/$reservaId/cancelar?motivo=${Uri.encodeComponent(texto)}'),
            headers: await _getHeaders(),
            body: jsonEncode({'motivo': texto}),
          )
          .timeout(_timeout);

      if (response.statusCode == 200) {
        await ReservaStore.registrarEstado(reservaId, EstadoReserva.cancelada);
        return const Resultado.ok(null, mensaje: 'Reserva cancelada');
      }
      return Resultado.error(
          _mensajeError(response, 'No se pudo cancelar la reserva'));
    } on SocketException {
      return const Resultado.error('No pudimos conectar con el servidor.');
    } catch (e) {
      debugPrint('ERROR AL CANCELAR RESERVA: $e');
      return const Resultado.error('Ocurrió un error al cancelar la reserva.');
    }
  }

  // ---------------------------------------------------------------------------
  // Administración de reservas
  // ---------------------------------------------------------------------------

  static Future<List<Reserva>> getReservasPorAprobar() async {
    for (final url in [
      '$baseUrl/admin/reservas?estado=pendiente',
      '$baseUrl/reservas/pendientes',
      '$baseUrl/reservas/',
    ]) {
      final respuesta = await _getLista(url);
      if (respuesta.reservas.isNotEmpty) {
        final pendientes = respuesta.reservas
            .where((r) => r.estado == EstadoReserva.pendiente)
            .toList()
          ..sort((a, b) {
            final ai = a.inicio, bi = b.inicio;
            if (ai == null || bi == null) return 0;
            return ai.compareTo(bi);
          });
        return pendientes;
      }
    }
    return [];
  }

  static Future<Resultado<void>> aprobarReserva(int reservaId) =>
      _cambiarEstado(reservaId, EstadoReserva.confirmada);

  static Future<Resultado<void>> rechazarReserva(int reservaId,
          {String motivo = 'Comprobante no válido'}) =>
      _cambiarEstado(reservaId, EstadoReserva.rechazada, motivo: motivo);

  static Future<Resultado<void>> _cambiarEstado(
    int reservaId,
    EstadoReserva estado, {
    String? motivo,
  }) async {
    final cuerpo = jsonEncode({
      'estado': estado.apiValue,
      if (motivo != null) 'motivo': motivo,
    });

    for (final url in [
      '$baseUrl/reservas/$reservaId/estado',
      '$baseUrl/admin/reservas/$reservaId/estado',
    ]) {
      try {
        final response = await http
            .put(Uri.parse(url), headers: await _getHeaders(), body: cuerpo)
            .timeout(_timeout);

        if (response.statusCode == 200) {
          await ReservaStore.registrarEstado(reservaId, estado);
          return Resultado.ok(null,
              mensaje: 'Reserva ${estado.etiquetaCorta.toLowerCase()}');
        }
        if (response.statusCode != 404 && response.statusCode != 405) {
          return Resultado.error(
              _mensajeError(response, 'No se pudo actualizar el estado'));
        }
      } catch (e) {
        debugPrint('ERROR AL CAMBIAR ESTADO en $url: $e');
      }
    }

    await ReservaStore.registrarEstado(reservaId, estado);
    return Resultado.ok(null,
        mensaje: 'Estado actualizado en la app (el backend aún no expone '
            'el endpoint de estados)');
  }

  // ---------------------------------------------------------------------------
  // Perfil de usuario
  // ---------------------------------------------------------------------------

  static Future<Resultado<Usuario>> obtenerPerfil([String? email]) async {
    final correo = email ?? await getEmail();

    final rutas = <String>[
      '$baseUrl/users/me',
      '$baseUrl/auth/me',
      if (correo != null && correo.isNotEmpty) '$baseUrl/users/perfil/$correo',
    ];

    for (final url in rutas) {
      try {
        final response = await http
            .get(Uri.parse(url), headers: await _getHeaders())
            .timeout(_timeout);

        if (response.statusCode == 200) {
          final data = jsonDecode(response.body);
          final mapa = data is Map<String, dynamic>
              ? (data['usuario'] is Map<String, dynamic>
                  ? data['usuario'] as Map<String, dynamic>
                  : data)
              : null;
          if (mapa != null) {
            final usuario = Usuario.fromJson(mapa);
            await _guardarSesion(
              token: await getToken() ?? '',
              email: usuario.email,
              nombre: usuario.nombre,
              rol: usuario.rol,
            );
            return Resultado.ok(usuario);
          }
        }
        if (response.statusCode == 401) {
          return const Resultado.error(
              'Tu sesión expiró. Inicia sesión otra vez.');
        }
      } catch (e) {
        debugPrint('ERROR AL OBTENER PERFIL en $url: $e');
      }
    }

    final prefs = await SharedPreferences.getInstance();
    final nombreLocal = prefs.getString('nombre');
    if (correo != null && correo.isNotEmpty) {
      return Resultado.ok(
        Usuario(
          id: 0,
          nombre: nombreLocal ?? correo.split('@').first,
          email: correo,
          rol: prefs.getString('rol') ?? 'cliente',
        ),
        mensaje: 'Mostrando datos guardados en el dispositivo',
      );
    }
    return const Resultado.error('No pudimos cargar tu perfil.');
  }

  static Future<Resultado<Usuario>> actualizarPerfil({
    required String email,
    String? nombre,
    String? telefono,
    String? direccion,
    DateTime? fechaNacimiento,
    File? fotoFile,
  }) async {
    try {
      final token = await getToken();
      final request = http.MultipartRequest(
        'PUT',
        Uri.parse('$baseUrl/users/perfil/$email'),
      );

      if (token != null) {
        request.headers['Authorization'] = 'Bearer $token';
      }

      if (nombre != null && nombre.trim().isNotEmpty) {
        request.fields['nombre'] = nombre.trim();
      }
      if (telefono != null) request.fields['telefono'] = telefono.trim();
      if (direccion != null) request.fields['direccion'] = direccion.trim();
      if (fechaNacimiento != null) {
        request.fields['fecha_nacimiento'] =
            fechaNacimiento.toIso8601String().split('T').first;
      }
      if (fotoFile != null) {
        request.files
            .add(await http.MultipartFile.fromPath('foto', fotoFile.path));
      }

      final streamed = await request.send().timeout(_timeout);
      final response = await http.Response.fromStream(streamed);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final mapa = data is Map<String, dynamic>
            ? (data['usuario'] is Map<String, dynamic>
                ? data['usuario'] as Map<String, dynamic>
                : data)
            : <String, dynamic>{};
        final usuario = Usuario.fromJson({'email': email, ...mapa});
        await _guardarSesion(
          token: token ?? '',
          email: usuario.email,
          nombre: usuario.nombre,
          rol: usuario.rol,
        );
        return Resultado.ok(usuario, mensaje: 'Perfil actualizado');
      }
      return Resultado.error(
          _mensajeError(response, 'No se pudo actualizar el perfil'));
    } on SocketException {
      return const Resultado.error('No pudimos conectar con el servidor.');
    } catch (e) {
      debugPrint('ERROR AL ACTUALIZAR PERFIL: $e');
      return const Resultado.error('Ocurrió un error al actualizar el perfil.');
    }
  }

  static String? urlAbsoluta(String? ruta) {
    if (ruta == null || ruta.trim().isEmpty) return null;

    if (ruta.startsWith('http://') || ruta.startsWith('https://')) {
      return ruta;
    }

    return '$hostBase${ruta.startsWith('/') ? '' : '/'}$ruta';
  }

  // ---------------------------------------------------------------------------
  // Chatbot
  // ---------------------------------------------------------------------------

  static Future<Map<String, dynamic>> enviarMensaje(
    String mensaje, {
    double? latitud,
    double? longitud,
  }) async {
    try {
      final response = await http
          .post(
            Uri.parse('$baseUrl/chat/'),
            headers: await _getHeaders(),
            body: jsonEncode({
              'mensaje': mensaje,
              if (latitud != null && longitud != null) ...{
                'latitud': latitud,
                'longitud': longitud,
              },
            }),
          )
          .timeout(_timeout);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return {
          'respuesta': data['respuesta'] ?? 'Sin respuesta.',
          'intencion': data['intencion'],
          'accion_resultado': data['accion_resultado'],
          'opciones': data['opciones'] ?? const [],
        };
      }
      throw Exception(_mensajeError(response, 'El asistente no respondió'));
    } on SocketException {
      throw Exception('Sin conexión con el servidor');
    } catch (e) {
      debugPrint('ERROR EN ENVIAR MENSAJE CHAT: $e');
      rethrow;
    }
  }

  static Future<List<MensajeChat>> getHistorialChat() async {
    try {
      final response = await http
          .get(Uri.parse('$baseUrl/chat/historial'),
              headers: await _getHeaders())
          .timeout(_timeout);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as List<dynamic>;
        final mensajes = <MensajeChat>[];
        for (final item in data.whereType<Map<String, dynamic>>()) {
          mensajes.addAll(MensajeChat.fromConversacion(item));
        }
        mensajes.sort((a, b) => a.fecha.compareTo(b.fecha));
        return mensajes;
      }
    } catch (e) {
      debugPrint('ERROR AL OBTENER HISTORIAL DE CHAT: $e');
    }
    return [];
  }

  // ---------------------------------------------------------------------------

  static String _formatearHora(String hora) {
    final partes = hora.split(':');
    final h = (partes.isNotEmpty ? partes[0] : '0').padLeft(2, '0');
    final m = (partes.length > 1 ? partes[1] : '00').padLeft(2, '0');
    return '$h:$m:00';
  }
}

class _RespuestaLista {
  final List<Reserva> reservas;
  final Set<String> campos;

  /// true si el servidor contestó (aunque fuera 404). false si hubo error de red.
  final bool respondio;

  const _RespuestaLista({
    required this.reservas,
    required this.campos,
    required this.respondio,
  });
}