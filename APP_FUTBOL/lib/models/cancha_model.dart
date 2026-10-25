class Cancha {
  final int id;
  final int? complejoId;       // ← antes sedeId
  final String? complejoNombre; // ← antes sedeNombre
  final String nombre;
  final String tipoSuperficie;
  final double precioHora;
  final bool activa;
  final String estado;
  final String? descripcion;
  final int? capacidad;
  final String? imagenUrl;

  Cancha({
    required this.id,
    this.complejoId,
    this.complejoNombre,
    required this.nombre,
    required this.tipoSuperficie,
    required this.precioHora,
    required this.activa,
    required this.estado,
    this.descripcion,
    this.capacidad,
    this.imagenUrl,
  });

  factory Cancha.fromJson(Map<String, dynamic> json) {
    final estado = (json['estado'] ?? 'activa').toString().toLowerCase();

    // Acepta varias claves por si el backend cambia entre complejo_id/sede_id.
    final rawComplejoId =
        json['complejo_id'] ?? json['sede_id'] ?? json['complejoId'];
    final rawComplejoNombre =
        json['complejo_nombre'] ?? json['sede_nombre'] ?? json['complejoNombre'];

    return Cancha(
      id: json['id'] is int
          ? json['id']
          : int.tryParse(json['id']?.toString() ?? '') ?? 0,
      complejoId: rawComplejoId is int
          ? rawComplejoId
          : int.tryParse(rawComplejoId?.toString() ?? ''),
      complejoNombre: rawComplejoNombre?.toString(),
      nombre: (json['nombre'] ?? '').toString(),
      tipoSuperficie:
          (json['tipo_superficie'] ?? json['tipo_deporte'] ?? 'Sintética')
              .toString(),
      precioHora: (json['precio_hora'] as num?)?.toDouble() ??
          double.tryParse(json['precio_hora']?.toString() ?? '') ??
          0.0,
      activa: _esActiva(json['activa'], estado),
      estado: estado,
      descripcion: json['descripcion']?.toString(),
      capacidad: json['capacidad'] is int
          ? json['capacidad']
          : int.tryParse(json['capacidad']?.toString() ?? ''),
      imagenUrl: (json['imagen_url'] ?? json['foto_url'])?.toString(),
    );
  }

  static bool _esActiva(dynamic activa, String estado) {
    if (estado == 'inactiva' ||
        estado == 'mantenimiento' ||
        estado == 'ocupada') {
      return false;
    }
    if (activa == null) return true;
    if (activa is bool) return activa;
    if (activa is num) return activa != 0;
    final texto = activa.toString().toLowerCase();
    return texto != 'false' && texto != '0' && texto != 'no';
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'complejo_id': complejoId,
        'complejo_nombre': complejoNombre,
        'nombre': nombre,
        'tipo_superficie': tipoSuperficie,
        'precio_hora': precioHora,
        'activa': activa,
        'estado': estado,
        'descripcion': descripcion,
        'capacidad': capacidad,
        'imagen_url': imagenUrl,
      };
}