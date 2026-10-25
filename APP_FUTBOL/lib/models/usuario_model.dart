class Usuario {
  final int id;
  final String nombre;
  final String email;
  final String? telefono;
  final String? fotoUrl;
  final String rol;
  final String? direccion;
  final DateTime? fechaNacimiento;
  final DateTime? fechaRegistro;
  final bool activo;

  Usuario({
    required this.id,
    required this.nombre,
    required this.email,
    this.telefono,
    this.fotoUrl,
    required this.rol,
    this.direccion,
    this.fechaNacimiento,
    this.fechaRegistro,
    this.activo = true,
  });

  factory Usuario.fromJson(Map<String, dynamic> json) {
    return Usuario(
      id: json['id'] is int
          ? json['id']
          : int.tryParse(json['id']?.toString() ?? '') ?? 0,
      nombre: (json['nombre'] ?? '').toString(),
      email: (json['email'] ?? '').toString(),
      telefono: json['telefono']?.toString(),
      fotoUrl: (json['foto_url'] ?? json['foto'] ?? json['avatar_url'])?.toString(),
      rol: (json['rol'] ?? 'cliente').toString(),
      direccion: json['direccion']?.toString(),
      fechaNacimiento: _fecha(json['fecha_nacimiento']),
      fechaRegistro: _fecha(json['fecha_registro'] ?? json['fecha_creacion'] ?? json['created_at']),
      activo: json['activo'] == null || json['activo'] == 1 || json['activo'] == true,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'nombre': nombre,
        'email': email,
        'telefono': telefono,
        'foto_url': fotoUrl,
        'rol': rol,
        'direccion': direccion,
        'fecha_nacimiento': fechaNacimiento?.toIso8601String(),
        'fecha_registro': fechaRegistro?.toIso8601String(),
        'activo': activo,
      };

  Usuario copyWith({
    String? nombre,
    String? telefono,
    String? fotoUrl,
    String? direccion,
    DateTime? fechaNacimiento,
  }) {
    return Usuario(
      id: id,
      nombre: nombre ?? this.nombre,
      email: email,
      telefono: telefono ?? this.telefono,
      fotoUrl: fotoUrl ?? this.fotoUrl,
      rol: rol,
      direccion: direccion ?? this.direccion,
      fechaNacimiento: fechaNacimiento ?? this.fechaNacimiento,
      fechaRegistro: fechaRegistro,
      activo: activo,
    );
  }

  bool get esAdmin {
    final r = rol.toLowerCase();
    return r == 'admin' || r == 'administrador' || r == 'superadmin';
  }

  /// Iniciales para el avatar cuando no hay foto ("Juan Pérez" -> "JP").
  String get iniciales {
    final partes = nombre.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (partes.isEmpty) {
      return email.isNotEmpty ? email[0].toUpperCase() : '?';
    }
    if (partes.length == 1) return partes.first[0].toUpperCase();
    return '${partes.first[0]}${partes[1][0]}'.toUpperCase();
  }

  /// Qué tan completo está el perfil (0.0 a 1.0). Se muestra en la pantalla
  /// de perfil para animar al usuario a llenar sus datos.
  double get completitud {
    final campos = <bool>[
      nombre.trim().isNotEmpty,
      email.trim().isNotEmpty,
      (telefono ?? '').trim().isNotEmpty,
      (direccion ?? '').trim().isNotEmpty,
      fechaNacimiento != null,
      (fotoUrl ?? '').trim().isNotEmpty,
    ];
    final llenos = campos.where((c) => c).length;
    return llenos / campos.length;
  }

  static DateTime? _fecha(dynamic v) {
    if (v == null) return null;
    return DateTime.tryParse(v.toString());
  }
}
