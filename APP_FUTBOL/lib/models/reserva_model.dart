import 'package:flutter/material.dart';

/// Estados por los que pasa una reserva.
enum EstadoReserva {
  pendiente,
  confirmada,
  rechazada,
  completada,
  cancelada;

  static EstadoReserva desdeTexto(String? valor) {
    switch ((valor ?? '').toLowerCase().trim()) {
      case 'confirmada':
      case 'confirmado':
      case 'aprobada':
      case 'aprobado':
      case 'pagada':
      case 'pagado':
        return EstadoReserva.confirmada;
      case 'rechazada':
      case 'rechazado':
      case 'denegada':
        return EstadoReserva.rechazada;
      case 'completada':
      case 'completado':
      case 'finalizada':
      case 'finalizado':
        return EstadoReserva.completada;
      case 'cancelada':
      case 'cancelado':
        return EstadoReserva.cancelada;
      case 'pendiente':
      case 'en_revision':
      case 'en revisión':
      case 'revision':
      default:
        return EstadoReserva.pendiente;
    }
  }

  String get apiValue => name;

  String get etiqueta {
    switch (this) {
      case EstadoReserva.pendiente:
        return 'Pendiente de aprobación';
      case EstadoReserva.confirmada:
        return 'Confirmada';
      case EstadoReserva.rechazada:
        return 'Rechazada';
      case EstadoReserva.completada:
        return 'Completada';
      case EstadoReserva.cancelada:
        return 'Cancelada';
    }
  }

  String get etiquetaCorta {
    switch (this) {
      case EstadoReserva.pendiente:
        return 'Pendiente';
      case EstadoReserva.confirmada:
        return 'Confirmada';
      case EstadoReserva.rechazada:
        return 'Rechazada';
      case EstadoReserva.completada:
        return 'Completada';
      case EstadoReserva.cancelada:
        return 'Cancelada';
    }
  }

  String get descripcion {
    switch (this) {
      case EstadoReserva.pendiente:
        return 'Estamos validando tu depósito. Te avisaremos en cuanto el '
            'administrador confirme el pago.';
      case EstadoReserva.confirmada:
        return 'Tu cancha está reservada. Te enviaremos un recordatorio antes '
            'de la hora del partido.';
      case EstadoReserva.rechazada:
        return 'No pudimos validar el comprobante de pago. Comunícate con '
            'nosotros o vuelve a intentar la reserva.';
      case EstadoReserva.completada:
        return 'Esta reserva ya se jugó. ¡Gracias por preferirnos!';
      case EstadoReserva.cancelada:
        return 'Esta reserva fue cancelada.';
    }
  }

  Color get color {
    switch (this) {
      case EstadoReserva.pendiente:
        return const Color(0xFFF59E0B);
      case EstadoReserva.confirmada:
        return const Color(0xFF0E9F6E);
      case EstadoReserva.rechazada:
        return const Color(0xFFE02424);
      case EstadoReserva.completada:
        return const Color(0xFF3F83F8);
      case EstadoReserva.cancelada:
        return const Color(0xFF6B7280);
    }
  }

  IconData get icono {
    switch (this) {
      case EstadoReserva.pendiente:
        return Icons.hourglass_top_rounded;
      case EstadoReserva.confirmada:
        return Icons.verified_rounded;
      case EstadoReserva.rechazada:
        return Icons.report_gmailerrorred_rounded;
      case EstadoReserva.completada:
        return Icons.sports_soccer_rounded;
      case EstadoReserva.cancelada:
        return Icons.cancel_rounded;
    }
  }

  bool get esActivo =>
      this == EstadoReserva.pendiente || this == EstadoReserva.confirmada;

  bool get esCerrado => !esActivo;
}

enum MetodoPago {
  tarjeta,
  transferencia,
  efectivo;

  static MetodoPago desdeTexto(String? valor) {
    switch ((valor ?? '').toLowerCase().trim()) {
      case 'tarjeta':
      case 'card':
      case 'credito':
      case 'crédito':
      case 'debito':
      case 'débito':
        return MetodoPago.tarjeta;
      case 'efectivo':
      case 'cash':
        return MetodoPago.efectivo;
      case 'transferencia':
      case 'deposito':
      case 'depósito':
      default:
        return MetodoPago.transferencia;
    }
  }

  String get apiValue => name;

  String get etiqueta {
    switch (this) {
      case MetodoPago.tarjeta:
        return 'Tarjeta de crédito / débito';
      case MetodoPago.transferencia:
        return 'Transferencia o depósito';
      case MetodoPago.efectivo:
        return 'Efectivo en cancha';
    }
  }

  IconData get icono {
    switch (this) {
      case MetodoPago.tarjeta:
        return Icons.credit_card_rounded;
      case MetodoPago.transferencia:
        return Icons.receipt_long_rounded;
      case MetodoPago.efectivo:
        return Icons.payments_rounded;
    }
  }

  EstadoReserva get estadoInicial => this == MetodoPago.tarjeta
      ? EstadoReserva.confirmada
      : EstadoReserva.pendiente;
}

class Reserva {
  final int id;
  final int canchaId;
  final String canchaNombre;
  final String? complejoNombre;      // ← NUEVO
  final String fecha; // yyyy-MM-dd
  final String horaInicio; // HH:mm(:ss)
  final String horaFin;
  final double montoTotal;
  final EstadoReserva estado;
  final MetodoPago metodoPago;
  final String notas;
  final String? comprobanteUrl;
  final String? motivoCancelacion;
  final DateTime? fechaCreacion;
  final String? usuarioNombre;
  final String? usuarioEmail;

  Reserva({
    required this.id,
    required this.canchaId,
    required this.canchaNombre,
    this.complejoNombre,             // ← NUEVO
    required this.fecha,
    required this.horaInicio,
    required this.horaFin,
    required this.montoTotal,
    required this.estado,
    this.metodoPago = MetodoPago.transferencia,
    this.notas = '',
    this.comprobanteUrl,
    this.motivoCancelacion,
    this.fechaCreacion,
    this.usuarioNombre,
    this.usuarioEmail,
  });

  factory Reserva.fromJson(Map<String, dynamic> json) {
    String nombreCancha = 'Cancha #${json['cancha_id'] ?? 0}';
    String? nombreComplejo;

    if (json['cancha'] is Map) {
      final cancha = json['cancha'] as Map;

      if (cancha['nombre'] != null) {
        nombreCancha = cancha['nombre'].toString();
      }

      // Acepta tanto `complejo_nombre` (property calculada en el modelo)
      // como `complejo.nombre` (relación anidada).
      if (cancha['complejo_nombre'] != null) {
        nombreComplejo = cancha['complejo_nombre'].toString();
      } else if (cancha['complejo'] is Map && cancha['complejo']['nombre'] != null) {
        nombreComplejo = cancha['complejo']['nombre'].toString();
      }
    } else if (json['cancha_nombre'] != null) {
      nombreCancha = json['cancha_nombre'].toString();
    }

    String? nombreUsuario;
    String? emailUsuario;
    if (json['usuario'] is Map) {
      nombreUsuario = json['usuario']['nombre']?.toString();
      emailUsuario = json['usuario']['email']?.toString();
    }
    nombreUsuario ??= json['usuario_nombre']?.toString();
    emailUsuario ??= json['usuario_email']?.toString();

    return Reserva(
      id: _asInt(json['id']),
      canchaId: _asInt(json['cancha_id']),
      canchaNombre: nombreCancha,
      complejoNombre: nombreComplejo,      // ← NUEVO
      fecha: (json['fecha_reserva'] ?? json['fecha'] ?? '').toString().split('T').first,
      horaInicio: _normalizarHora(json['hora_inicio']),
      horaFin: _normalizarHora(json['hora_fin']),
      montoTotal: _asDouble(json['precio_total'] ?? json['monto_total'] ?? json['total']),
      estado: EstadoReserva.desdeTexto(json['estado']?.toString()),
      metodoPago: MetodoPago.desdeTexto(json['metodo_pago']?.toString()),
      notas: (json['notas'] ?? '').toString(),
      comprobanteUrl: json['comprobante_url']?.toString(),
      motivoCancelacion:
          (json['motivo_cancelacion'] ?? json['motivo'] ?? json['motivo_rechazo'])?.toString(),
      fechaCreacion: _asFecha(json['fecha_creacion'] ?? json['created_at']),
      usuarioNombre: nombreUsuario,
      usuarioEmail: emailUsuario,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'cancha_id': canchaId,
        'cancha_nombre': canchaNombre,
        'complejo_nombre': complejoNombre,   // ← NUEVO
        'fecha_reserva': fecha,
        'hora_inicio': horaInicio,
        'hora_fin': horaFin,
        'precio_total': montoTotal,
        'estado': estado.apiValue,
        'metodo_pago': metodoPago.apiValue,
        'notas': notas,
        'comprobante_url': comprobanteUrl,
        'motivo_cancelacion': motivoCancelacion,
        'fecha_creacion': fechaCreacion?.toIso8601String(),
        'usuario_nombre': usuarioNombre,
        'usuario_email': usuarioEmail,
      };

  Reserva copyWith({
    EstadoReserva? estado,
    MetodoPago? metodoPago,
    String? comprobanteUrl,
    String? motivoCancelacion,
    String? notas,
  }) {
    return Reserva(
      id: id,
      canchaId: canchaId,
      canchaNombre: canchaNombre,
      complejoNombre: complejoNombre,    // ← se conserva
      fecha: fecha,
      horaInicio: horaInicio,
      horaFin: horaFin,
      montoTotal: montoTotal,
      estado: estado ?? this.estado,
      metodoPago: metodoPago ?? this.metodoPago,
      notas: notas ?? this.notas,
      comprobanteUrl: comprobanteUrl ?? this.comprobanteUrl,
      motivoCancelacion: motivoCancelacion ?? this.motivoCancelacion,
      fechaCreacion: fechaCreacion,
      usuarioNombre: usuarioNombre,
      usuarioEmail: usuarioEmail,
    );
  }

  // ---------------------------------------------------------------------------
  // Fechas y utilidades de presentación
  // ---------------------------------------------------------------------------

  DateTime? get inicio {
    final dia = DateTime.tryParse(fecha);
    if (dia == null) return null;
    final partes = horaInicio.split(':');
    if (partes.length < 2) return dia;
    final h = int.tryParse(partes[0]) ?? 0;
    final m = int.tryParse(partes[1]) ?? 0;
    return DateTime(dia.year, dia.month, dia.day, h, m);
  }

  DateTime? get fin {
    final dia = DateTime.tryParse(fecha);
    if (dia == null) return null;
    final partes = horaFin.split(':');
    if (partes.length < 2) return dia;
    final h = int.tryParse(partes[0]) ?? 0;
    final m = int.tryParse(partes[1]) ?? 0;
    return DateTime(dia.year, dia.month, dia.day, h, m);
  }

  bool get yaPaso {
    final f = fin;
    return f != null && f.isBefore(DateTime.now());
  }

  EstadoReserva get estadoEfectivo {
    if (estado == EstadoReserva.confirmada && yaPaso) {
      return EstadoReserva.completada;
    }
    return estado;
  }

  bool get esProxima => estadoEfectivo.esActivo && !yaPaso;

  bool get esperandoAprobacion =>
      estadoEfectivo == EstadoReserva.pendiente && !yaPaso;

  bool get admiteRecordatorio =>
      estadoEfectivo == EstadoReserva.confirmada && !yaPaso;

  bool get sePuedeCancelar => estadoEfectivo.esActivo && !yaPaso;

  String get rangoHorario => '${_hhmm(horaInicio)} - ${_hhmm(horaFin)}';

  double get horasReservadas {
    final i = inicio;
    final f = fin;
    if (i == null || f == null) return 0;
    final dif = f.difference(i).inMinutes / 60;
    return dif > 0 ? dif : 0;
  }

  String get tiempoRelativo {
    final i = inicio;
    if (i == null) return '';
    final ahora = DateTime.now();
    final dif = i.difference(ahora);

    if (dif.isNegative) {
      final abs = dif.abs();
      if (abs.inDays >= 1) return 'hace ${abs.inDays} día${abs.inDays == 1 ? '' : 's'}';
      if (abs.inHours >= 1) return 'hace ${abs.inHours} h';
      return 'hace ${abs.inMinutes} min';
    }
    if (dif.inDays >= 1) return 'en ${dif.inDays} día${dif.inDays == 1 ? '' : 's'}';
    if (dif.inHours >= 1) return 'en ${dif.inHours} h ${dif.inMinutes % 60} min';
    return 'en ${dif.inMinutes} min';
  }

  static String _hhmm(String hora) {
    final partes = hora.split(':');
    if (partes.length < 2) return hora;
    return '${partes[0].padLeft(2, '0')}:${partes[1].padLeft(2, '0')}';
  }

  static bool horaIgual(String a, String b) => _hhmm(a) == _hhmm(b);

  static String _normalizarHora(dynamic valor) {
    final texto = (valor ?? '').toString();
    if (texto.isEmpty) return '';
    if (texto.contains('T')) return texto.split('T').last;
    return texto;
  }

  static int _asInt(dynamic v) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse(v?.toString() ?? '') ?? 0;
  }

  static double _asDouble(dynamic v) {
    if (v is num) return v.toDouble();
    return double.tryParse(v?.toString() ?? '') ?? 0.0;
  }

  static DateTime? _asFecha(dynamic v) {
    if (v == null) return null;
    return DateTime.tryParse(v.toString());
  }
}