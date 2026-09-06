class SlotArreglo {
  final String slotId;
  final String campoId;
  final String reunionTipo;
  final String diaSemana;
  final String hora;
  final String? usuarioUid;
  final String estado;
  final String? motivoRecusa;
  final int semanaNumero;

  SlotArreglo({
    required this.slotId,
    required this.campoId,
    required this.reunionTipo,
    required this.diaSemana,
    required this.hora,
    this.usuarioUid,
    this.estado = 'asignado',
    this.motivoRecusa,
    required this.semanaNumero,
  });

  factory SlotArreglo.fromMap(Map<String, dynamic> map) {
    return SlotArreglo(
      slotId: map['slot_id'] as String? ?? '',
      campoId: map['campo_id'] as String? ?? '',
      reunionTipo: map['reunion_tipo'] as String? ?? '',
      diaSemana: map['dia_semana'] as String? ?? '',
      hora: map['hora'] as String? ?? '',
      usuarioUid: map['usuario_uid'] as String?,
      estado: map['estado'] as String? ?? 'asignado',
      motivoRecusa: map['motivo_recusa'] as String?,
      semanaNumero: map['semana_numero'] as int? ?? 1,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'slot_id': slotId,
      'campo_id': campoId,
      'reunion_tipo': reunionTipo,
      'dia_semana': diaSemana,
      'hora': hora,
      'usuario_uid': usuarioUid,
      'estado': estado,
      'motivo_recusa': motivoRecusa,
      'semana_numero': semanaNumero,
    };
  }

  SlotArreglo copyWith({
    String? campoId,
    String? reunionTipo,
    String? diaSemana,
    String? hora,
    String? usuarioUid,
    String? estado,
    String? motivoRecusa,
    int? semanaNumero,
    bool clearUsuario = false,
  }) {
    return SlotArreglo(
      slotId: slotId,
      campoId: campoId ?? this.campoId,
      reunionTipo: reunionTipo ?? this.reunionTipo,
      diaSemana: diaSemana ?? this.diaSemana,
      hora: hora ?? this.hora,
      usuarioUid: clearUsuario ? null : (usuarioUid ?? this.usuarioUid),
      estado: estado ?? this.estado,
      motivoRecusa: motivoRecusa ?? this.motivoRecusa,
      semanaNumero: semanaNumero ?? this.semanaNumero,
    );
  }

  bool get estaAsignado => usuarioUid != null && usuarioUid!.isNotEmpty;
  bool get estaRecusado => estado == 'recusado';
  bool get estaAceptado => estado == 'aceptado';
}

class Arreglo {
  final String id;
  final String funcionId;
  final String gestionadoPor;
  final String titulo;
  final String duracion;
  final DateTime fechaInicio;
  final DateTime fechaFin;
  final bool publicado;
  final bool activo;
  final List<SlotArreglo> slots;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  Arreglo({
    required this.id,
    required this.funcionId,
    required this.gestionadoPor,
    required this.titulo,
    required this.duracion,
    required this.fechaInicio,
    required this.fechaFin,
    this.publicado = false,
    this.activo = true,
    this.slots = const [],
    this.createdAt,
    this.updatedAt,
  });

  factory Arreglo.fromMap(String id, Map<String, dynamic> map) {
    return Arreglo(
      id: id,
      funcionId: map['funcion_id'] as String? ?? '',
      gestionadoPor: map['gestionado_por'] as String? ?? '',
      titulo: map['titulo'] as String? ?? '',
      duracion: map['duracion'] as String? ?? '1_mes',
      fechaInicio: map['fecha_inicio'] != null
          ? (map['fecha_inicio'] as dynamic).toDate()
          : DateTime.now(),
      fechaFin: map['fecha_fin'] != null
          ? (map['fecha_fin'] as dynamic).toDate()
          : DateTime.now().add(const Duration(days: 30)),
      publicado: map['publicado'] as bool? ?? false,
      activo: map['activo'] as bool? ?? true,
      slots: (map['slots'] as List?)
              ?.map((s) => SlotArreglo.fromMap(s as Map<String, dynamic>))
              .toList() ??
          [],
      createdAt: map['created_at'] != null
          ? (map['created_at'] as dynamic).toDate()
          : null,
      updatedAt: map['updated_at'] != null
          ? (map['updated_at'] as dynamic).toDate()
          : null,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'funcion_id': funcionId,
      'gestionado_por': gestionadoPor,
      'titulo': titulo,
      'duracion': duracion,
      'fecha_inicio': fechaInicio,
      'fecha_fin': fechaFin,
      'publicado': publicado,
      'activo': activo,
      'slots': slots.map((s) => s.toMap()).toList(),
      'created_at': createdAt ?? DateTime.now(),
      'updated_at': DateTime.now(),
    };
  }

  Arreglo copyWith({
    String? titulo,
    String? duracion,
    DateTime? fechaInicio,
    DateTime? fechaFin,
    bool? publicado,
    bool? activo,
    List<SlotArreglo>? slots,
  }) {
    return Arreglo(
      id: id,
      funcionId: funcionId,
      gestionadoPor: gestionadoPor,
      titulo: titulo ?? this.titulo,
      duracion: duracion ?? this.duracion,
      fechaInicio: fechaInicio ?? this.fechaInicio,
      fechaFin: fechaFin ?? this.fechaFin,
      publicado: publicado ?? this.publicado,
      activo: activo ?? this.activo,
      slots: slots ?? this.slots,
      createdAt: createdAt,
      updatedAt: DateTime.now(),
    );
  }

  int get totalSlots => slots.length;
  int get slotsAsignados => slots.where((s) => s.estaAsignado).length;
  int get slotsRecusados => slots.where((s) => s.estaRecusado).length;
  int get slotsAceptados => slots.where((s) => s.estaAceptado).length;
  bool get estaPorVencer {
    final diasRestantes = fechaFin.difference(DateTime.now()).inDays;
    return diasRestantes <= 7 && diasRestantes >= 0;
  }

  static String calcularFechaFin(DateTime inicio, String duracion) {
    switch (duracion) {
      case '1_semana':
        return inicio.add(const Duration(days: 6)).toString();
      case '1_mes':
        return DateTime(inicio.year, inicio.month + 1, 0).toString();
      case '3_meses':
        return DateTime(inicio.year, inicio.month + 3, 0).toString();
      default:
        return inicio.add(const Duration(days: 30)).toString();
    }
  }

  static DateTime calcularFechaFinDateTime(DateTime inicio, String duracion) {
    switch (duracion) {
      case '1_semana':
        return inicio.add(const Duration(days: 6));
      case '1_mes':
        return DateTime(inicio.year, inicio.month + 1, 0);
      case '3_meses':
        return DateTime(inicio.year, inicio.month + 3, 0);
      default:
        return inicio.add(const Duration(days: 30));
    }
  }
}
