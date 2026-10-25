class MensajeChat {
  final int? id;
  final String mensajeUsuario;
  final bool esUsuario;
  final DateTime fecha;
  final String? intencion;
  final Map<String, dynamic>? accionResultado;

  /// Botones de respuesta rápida que sugiere el asistente
  /// (por ejemplo: "Sí, confirmar" / "No, cambiar").
  final List<String> opciones;

  MensajeChat({
    this.id,
    required this.mensajeUsuario,
    required this.esUsuario,
    required this.fecha,
    this.intencion,
    this.accionResultado,
    this.opciones = const [],
  });

  /// Convierte cualquier valor del JSON en una lista de textos.
  static List<String> _listaTextos(dynamic valor) {
    if (valor is List) {
      return valor.map((e) => e.toString()).toList();
    }
    return const [];
  }

  /// Convierte cualquier valor del JSON en un mapa (o null).
  static Map<String, dynamic>? _mapa(dynamic valor) {
    if (valor is Map) return Map<String, dynamic>.from(valor);
    return null;
  }

  /// Deserializa un mensaje estándar enviado desde la app
  factory MensajeChat.fromJson(Map<String, dynamic> json) {
    final accion = _mapa(json['accion_resultado']);
    return MensajeChat(
      id: json['id'],
      mensajeUsuario: json['mensaje_usuario'] ?? json['respuesta'] ?? '',
      esUsuario: json['es_usuario'] ?? false,
      fecha: json['fecha_creacion'] != null
          ? DateTime.parse(json['fecha_creacion'])
          : DateTime.now(),
      intencion: json['intencion'] ?? json['intencion_detectada'],
      accionResultado: accion,
      opciones: _listaTextos(json['opciones'] ?? accion?['opciones']),
    );
  }

  /// Método estático especial para mapear un registro de historial del backend
  /// Convierte UN registro de 'ConversacionIA' en DOS mensajes independientes:
  /// uno para la pregunta del usuario y otro para la respuesta de la IA.
  static List<MensajeChat> fromConversacion(Map<String, dynamic> json) {
    List<MensajeChat> mensajes = [];
    final fechaBase = json['fecha_creacion'] != null
        ? DateTime.parse(json['fecha_creacion'])
        : DateTime.now();

    // 1. Mensaje enviado por el usuario
    if (json['mensaje_usuario'] != null &&
        json['mensaje_usuario'].toString().isNotEmpty) {
      mensajes.add(
        MensajeChat(
          id: json['id'],
          mensajeUsuario: json['mensaje_usuario'],
          esUsuario: true,
          fecha: fechaBase,
        ),
      );
    }

    // 2. Respuesta generada por la IA
    if (json['respuesta_ia'] != null &&
        json['respuesta_ia'].toString().isNotEmpty) {
      final accion = _mapa(json['resultado_accion'] ?? json['accion_resultado']);
      mensajes.add(
        MensajeChat(
          id: json['id'],
          mensajeUsuario: json['respuesta_ia'],
          esUsuario: false,
          fecha: fechaBase.add(const Duration(milliseconds: 100)), // Ligero desfase para ordenación
          intencion: json['intencion'] ?? json['intencion_detectada'],
          accionResultado: accion,
          // El backend guarda las opciones dentro de resultado_accion.
          opciones: _listaTextos(accion?['opciones']),
        ),
      );
    }

    return mensajes;
  }

  /// Convierte el mensaje a JSON por si requiere almacenamiento local
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'mensaje_usuario': mensajeUsuario,
      'es_usuario': esUsuario,
      'fecha_creacion': fecha.toIso8601String(),
      'intencion': intencion,
      'accion_resultado': accionResultado,
      'opciones': opciones,
    };
  }
}