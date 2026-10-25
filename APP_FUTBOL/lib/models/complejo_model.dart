class Complejo {
  final int id;
  final String nombre;
  final String? direccion;
  final String? telefono;
  final String? imagenUrl;
  final double? latitud;
  final double? longitud;

  /// Horario de atención en formato HH:MM (ej. "06:00").
  final String? horarioApertura;
  final String? horarioCierre;

  /// Calificación promedio (0 a 5).
  final double? calificacion;
  final int totalCanchas;

  /// Precio por hora más bajo entre las canchas del complejo.
  final double? precioDesde;

  /// Solo viene cuando la app envió la ubicación del usuario.
  final double? distanciaKm;

  const Complejo({
    required this.id,
    required this.nombre,
    this.direccion,
    this.telefono,
    this.imagenUrl,
    this.latitud,
    this.longitud,
    this.horarioApertura,
    this.horarioCierre,
    this.calificacion,
    this.totalCanchas = 0,
    this.precioDesde,
    this.distanciaKm,
  });

  /// "06:00 - 22:00" o null si el complejo no tiene horario registrado.
  String? get horario => (horarioApertura != null && horarioCierre != null)
      ? '$horarioApertura - $horarioCierre'
      : null;

  static double? _aDouble(dynamic v) =>
      v == null ? null : double.tryParse(v.toString());

  factory Complejo.fromJson(Map<String, dynamic> json) {
    return Complejo(
      id: (json['id'] as num).toInt(),
      nombre: (json['nombre'] ?? 'Complejo').toString(),
      direccion: json['direccion']?.toString(),
      telefono: json['telefono']?.toString(),
      imagenUrl: json['imagen_url']?.toString(),
      latitud: _aDouble(json['latitud']),
      longitud: _aDouble(json['longitud']),
      horarioApertura: json['horario_apertura']?.toString(),
      horarioCierre: json['horario_cierre']?.toString(),
      // El backend usa "calificacion_promedio", pero por si acaso aceptamos
      // también "calificacion".
      calificacion: _aDouble(
        json['calificacion_promedio'] ?? json['calificacion'],
      ),
      totalCanchas: (json['total_canchas'] as num?)?.toInt() ?? 0,
      precioDesde: _aDouble(json['precio_desde']),
      distanciaKm: _aDouble(json['distancia_km']),
    );
  }
}