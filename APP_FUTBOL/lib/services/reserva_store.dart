import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/reserva_model.dart';

/// Guarda las reservas en el teléfono.
///
/// Cumple dos funciones:
///
/// 1. **Historial persistente / modo sin conexión.** Cada vez que el backend
///    responde, cacheamos la lista. Si más tarde no hay red, la app sigue
///    mostrando tus reservas y tu historial.
///
/// 2. **Sobreescritura de estado y método de pago.** Si tu backend todavía no
///    guarda `metodo_pago` ni distingue `pendiente`/`confirmada`/`rechazada`,
///    la app conserva localmente lo que eligió el usuario al pagar y lo
///    fusiona con lo que devuelve el servidor. Cuando el backend ya envía
///    esos campos, el valor del servidor manda.
class ReservaStore {
  static const String _keyCache = 'reservas_cache';
  static const String _keyOverlay = 'reservas_overlay';
  static const String _keyEstadosVistos = 'reservas_estados_vistos';

  // ---------------------------------------------------------------------------
  // Caché de la lista completa
  // ---------------------------------------------------------------------------

  static Future<void> guardarCache(List<Reserva> reservas) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final data = reservas.map((r) => r.toJson()).toList();
      await prefs.setString(_keyCache, jsonEncode(data));
    } catch (e) {
      debugPrint('No se pudo guardar el caché de reservas: $e');
    }
  }

  static Future<List<Reserva>> leerCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_keyCache);
      if (raw == null || raw.isEmpty) return [];
      final lista = jsonDecode(raw) as List<dynamic>;
      return lista
          .whereType<Map<String, dynamic>>()
          .map(Reserva.fromJson)
          .toList();
    } catch (e) {
      debugPrint('No se pudo leer el caché de reservas: $e');
      return [];
    }
  }

  /// Fusiona la lista del servidor con el caché: conserva las reservas que el
  /// servidor ya no devuelve (por ejemplo historial antiguo) sin duplicar.
  static Future<List<Reserva>> fusionarConCache(List<Reserva> delServidor) async {
    final cache = await leerCache();
    final porId = <int, Reserva>{};
    for (final r in cache) {
      porId[r.id] = r;
    }
    // El servidor siempre gana sobre el caché.
    for (final r in delServidor) {
      porId[r.id] = r;
    }
    final fusionadas = porId.values.toList()
      ..sort((a, b) {
        final ai = a.inicio;
        final bi = b.inicio;
        if (ai == null || bi == null) return b.id.compareTo(a.id);
        return bi.compareTo(ai);
      });
    await guardarCache(fusionadas);
    return fusionadas;
  }

  // ---------------------------------------------------------------------------
  // Sobreescritura local de estado / método de pago / comprobante
  // ---------------------------------------------------------------------------

  static Future<Map<String, dynamic>> _leerOverlay() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_keyOverlay);
      if (raw == null || raw.isEmpty) return {};
      return Map<String, dynamic>.from(jsonDecode(raw) as Map);
    } catch (e) {
      debugPrint('No se pudo leer el overlay de reservas: $e');
      return {};
    }
  }

  static Future<void> _guardarOverlay(Map<String, dynamic> overlay) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_keyOverlay, jsonEncode(overlay));
    } catch (e) {
      debugPrint('No se pudo guardar el overlay de reservas: $e');
    }
  }

  /// Registra localmente cómo se pagó una reserva y en qué estado quedó.
  static Future<void> registrarPago({
    required int reservaId,
    required MetodoPago metodoPago,
    required EstadoReserva estado,
    String? comprobanteUrl,
  }) async {
    final overlay = await _leerOverlay();
    overlay['$reservaId'] = {
      'metodo_pago': metodoPago.apiValue,
      'estado': estado.apiValue,
      if (comprobanteUrl != null) 'comprobante_url': comprobanteUrl,
    };
    await _guardarOverlay(overlay);
  }

  static Future<void> registrarEstado(int reservaId, EstadoReserva estado) async {
    final overlay = await _leerOverlay();
    final actual = Map<String, dynamic>.from(
      (overlay['$reservaId'] as Map?)?.cast<String, dynamic>() ?? {},
    );
    actual['estado'] = estado.apiValue;
    overlay['$reservaId'] = actual;
    await _guardarOverlay(overlay);
  }

  /// Aplica la información local a la lista que llegó del backend.
  /// El backend tiene prioridad: solo rellenamos lo que él no envía.
  static Future<List<Reserva>> aplicarOverlay(
    List<Reserva> reservas, {
    required Set<String> camposQueEnviaElBackend,
  }) async {
    final overlay = await _leerOverlay();
    if (overlay.isEmpty) return reservas;

    return reservas.map((r) {
      final local = overlay['${r.id}'] as Map?;
      if (local == null) return r;

      final metodoLocal = local['metodo_pago'] != null
          ? MetodoPago.desdeTexto(local['metodo_pago'].toString())
          : null;
      final estadoLocal = local['estado'] != null
          ? EstadoReserva.desdeTexto(local['estado'].toString())
          : null;

      return r.copyWith(
        metodoPago: camposQueEnviaElBackend.contains('metodo_pago')
            ? null
            : metodoLocal,
        // Si el backend ya cambió el estado a algo cerrado (canceló, rechazó,
        // aprobó), respetamos al backend. Solo usamos el local cuando el
        // backend sigue en 'pendiente' genérico.
        estado: (camposQueEnviaElBackend.contains('estado') &&
                r.estado != EstadoReserva.pendiente)
            ? null
            : estadoLocal,
        comprobanteUrl: r.comprobanteUrl ?? local['comprobante_url']?.toString(),
      );
    }).toList();
  }

  // ---------------------------------------------------------------------------
  // Detección de cambios de estado (para notificar al usuario)
  // ---------------------------------------------------------------------------

  /// Compara el estado actual de cada reserva contra el que se vio la última
  /// vez y devuelve las que cambiaron. Sirve para avisarle al usuario que el
  /// administrador ya aprobó (o rechazó) su depósito.
  static Future<List<Reserva>> detectarCambiosDeEstado(
      List<Reserva> reservas) async {
    final prefs = await SharedPreferences.getInstance();
    Map<String, dynamic> vistos = {};
    try {
      final raw = prefs.getString(_keyEstadosVistos);
      if (raw != null && raw.isNotEmpty) {
        vistos = Map<String, dynamic>.from(jsonDecode(raw) as Map);
      }
    } catch (e) {
      debugPrint('No se pudieron leer los estados vistos: $e');
    }

    final cambiadas = <Reserva>[];
    final nuevos = <String, dynamic>{};

    for (final r in reservas) {
      final estadoActual = r.estado.apiValue;
      nuevos['${r.id}'] = estadoActual;
      final anterior = vistos['${r.id}']?.toString();
      // Solo avisamos cuando ya conocíamos la reserva y su estado cambió.
      if (anterior != null && anterior != estadoActual) {
        cambiadas.add(r);
      }
    }

    await prefs.setString(_keyEstadosVistos, jsonEncode(nuevos));
    return cambiadas;
  }

  /// Limpia todo lo guardado (al cerrar sesión).
  static Future<void> limpiar() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyCache);
    await prefs.remove(_keyOverlay);
    await prefs.remove(_keyEstadosVistos);
  }
}
