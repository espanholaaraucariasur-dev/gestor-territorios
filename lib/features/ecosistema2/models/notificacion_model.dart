class Notificacion {
  final String id;
  final String tipo;
  final String paraUid;
  final String? deUid;
  final String? funcionId;
  final String? arregloId;
  final String? slotId;
  final String titulo;
  final String mensaje;
  final bool leida;
  final String? accionUrl;
  final DateTime? createdAt;

  Notificacion({
    required this.id,
    required this.tipo,
    required this.paraUid,
    this.deUid,
    this.funcionId,
    this.arregloId,
    this.slotId,
    required this.titulo,
    required this.mensaje,
    this.leida = false,
    this.accionUrl,
    this.createdAt,
  });

  factory Notificacion.fromMap(String id, Map<String, dynamic> map) {
    return Notificacion(
      id: id,
      tipo: map['tipo'] as String? ?? '',
      paraUid: map['para_uid'] as String? ?? '',
      deUid: map['de_uid'] as String?,
      funcionId: map['funcion_id'] as String?,
      arregloId: map['arreglo_id'] as String?,
      slotId: map['slot_id'] as String?,
      titulo: map['titulo'] as String? ?? '',
      mensaje: map['mensaje'] as String? ?? '',
      leida: map['leida'] as bool? ?? false,
      accionUrl: map['accion_url'] as String?,
      createdAt: map['created_at'] != null
          ? (map['created_at'] as dynamic).toDate()
          : null,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'tipo': tipo,
      'para_uid': paraUid,
      'de_uid': deUid,
      'funcion_id': funcionId,
      'arreglo_id': arregloId,
      'slot_id': slotId,
      'titulo': titulo,
      'mensaje': mensaje,
      'leida': leida,
      'accion_url': accionUrl,
      'created_at': createdAt ?? DateTime.now(),
    };
  }

  Notificacion copyWith({
    bool? leida,
  }) {
    return Notificacion(
      id: id,
      tipo: tipo,
      paraUid: paraUid,
      deUid: deUid,
      funcionId: funcionId,
      arregloId: arregloId,
      slotId: slotId,
      titulo: titulo,
      mensaje: mensaje,
      leida: leida ?? this.leida,
      accionUrl: accionUrl,
      createdAt: createdAt,
    );
  }

  String get iconoTipo {
    switch (tipo) {
      case 'asignacion':
        return 'assignment';
      case 'recusa':
        return 'cancel';
      case 'recordatorio':
        return 'alarm';
      case 'nuevo_arreglo':
        return 'calendar_today';
      default:
        return 'notifications';
    }
  }
}
