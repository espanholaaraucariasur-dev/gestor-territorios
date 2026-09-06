class CampoFuncion {
  final String id;
  final String label;
  final String icono;

  CampoFuncion({
    required this.id,
    required this.label,
    required this.icono,
  });

  factory CampoFuncion.fromMap(Map<String, dynamic> map) {
    return CampoFuncion(
      id: map['id'] as String? ?? '',
      label: map['label'] as String? ?? '',
      icono: map['icono'] as String? ?? 'circle',
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'label': label,
      'icono': icono,
    };
  }
}

class Funcion {
  final String id;
  final String nombre;
  final String descripcion;
  final String icono;
  final String color;
  final List<CampoFuncion> campos;
  final List<String> rolesRequeridos;
  final List<String> reuniones;
  final String? gestorUid;
  final bool activa;
  final DateTime? createdAt;

  Funcion({
    required this.id,
    required this.nombre,
    required this.descripcion,
    required this.icono,
    required this.color,
    required this.campos,
    required this.rolesRequeridos,
    required this.reuniones,
    this.gestorUid,
    this.activa = true,
    this.createdAt,
  });

  factory Funcion.fromMap(String id, Map<String, dynamic> map) {
    return Funcion(
      id: id,
      nombre: map['nombre'] as String? ?? '',
      descripcion: map['descripcion'] as String? ?? '',
      icono: map['icono'] as String? ?? 'circle',
      color: map['color'] as String? ?? '#1B5E20',
      campos: (map['campos'] as List?)
              ?.map((c) => CampoFuncion.fromMap(c as Map<String, dynamic>))
              .toList() ??
          [],
      rolesRequeridos: (map['roles_requeridos'] as List?)
              ?.whereType<String>()
              .toList() ??
          [],
      reuniones: (map['reuniones'] as List?)?.whereType<String>().toList() ?? [],
      gestorUid: map['gestor_uid'] as String?,
      activa: map['activa'] as bool? ?? true,
      createdAt: map['created_at'] != null
          ? (map['created_at'] as dynamic).toDate()
          : null,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'nombre': nombre,
      'descripcion': descripcion,
      'icono': icono,
      'color': color,
      'campos': campos.map((c) => c.toMap()).toList(),
      'roles_requeridos': rolesRequeridos,
      'reuniones': reuniones,
      'gestor_uid': gestorUid,
      'activa': activa,
      'created_at': createdAt ?? DateTime.now(),
    };
  }

  Funcion copyWith({
    String? nombre,
    String? descripcion,
    String? icono,
    String? color,
    List<CampoFuncion>? campos,
    List<String>? rolesRequeridos,
    List<String>? reuniones,
    String? gestorUid,
    bool? activa,
    bool clearGestor = false,
  }) {
    return Funcion(
      id: id,
      nombre: nombre ?? this.nombre,
      descripcion: descripcion ?? this.descripcion,
      icono: icono ?? this.icono,
      color: color ?? this.color,
      campos: campos ?? this.campos,
      rolesRequeridos: rolesRequeridos ?? this.rolesRequeridos,
      reuniones: reuniones ?? this.reuniones,
      gestorUid: clearGestor ? null : (gestorUid ?? this.gestorUid),
      activa: activa ?? this.activa,
      createdAt: createdAt,
    );
  }

  bool get esGestor => gestorUid != null && gestorUid!.isNotEmpty;
}
