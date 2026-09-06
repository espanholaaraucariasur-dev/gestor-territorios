class UsuarioEco2 {
  final String uid;
  final String nombre;
  final String email;
  final List<String> roles;
  final String? familiaId;
  final List<String> funcionesAsignadas;

  static const List<String> rolesDisponibles = [
    'publicador',
    'admin',
    'trabajador',
    'limpieza',
    'audio_video',
    'acomodador',
    'microfono',
  ];

  UsuarioEco2({
    required this.uid,
    required this.nombre,
    required this.email,
    List<String>? roles,
    this.familiaId,
    this.funcionesAsignadas = const [],
  }) : roles = roles ?? ['publicador'];

  factory UsuarioEco2.fromMap(String id, Map<String, dynamic> map) {
    final rolesRaw = (map['roles'] as List?)?.whereType<String>().toList();
    final rolLegacy = map['rol_eco2'] as String?;
    List<String> rolesFinales = rolesRaw ?? ['publicador'];
    if (rolesRaw == null && rolLegacy != null && rolLegacy.isNotEmpty) {
      rolesFinales = [rolLegacy];
    }
    if (!rolesFinales.contains('publicador')) {
      rolesFinales.add('publicador');
    }
    return UsuarioEco2(
      uid: id,
      nombre: map['nombre'] as String? ?? '',
      email: map['email'] as String? ?? '',
      roles: rolesFinales,
      familiaId: map['familia_id'] as String?,
      funcionesAsignadas:
          (map['funciones_asignadas'] as List?)?.whereType<String>().toList() ??
              [],
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'nombre': nombre,
      'email': email,
      'roles': roles,
      'familia_id': familiaId,
      'funciones_asignadas': funcionesAsignadas,
    };
  }

  UsuarioEco2 copyWith({
    String? nombre,
    String? email,
    List<String>? roles,
    String? familiaId,
    bool clearFamilia = false,
    List<String>? funcionesAsignadas,
  }) {
    return UsuarioEco2(
      uid: uid,
      nombre: nombre ?? this.nombre,
      email: email ?? this.email,
      roles: roles ?? this.roles,
      familiaId: clearFamilia ? null : (familiaId ?? this.familiaId),
      funcionesAsignadas: funcionesAsignadas ?? this.funcionesAsignadas,
    );
  }

  bool get esAdmin => roles.contains('admin');
  bool get esTrabajador => roles.contains('trabajador');
  bool get esPublicador => roles.contains('publicador');
}
