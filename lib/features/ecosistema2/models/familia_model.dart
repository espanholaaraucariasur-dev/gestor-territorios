import 'package:cloud_firestore/cloud_firestore.dart';

class Familia {
  final String id;
  final String nombre;
  final List<String> miembros;
  final String creadoPor;
  final bool activa;
  final DateTime createdAt;

  Familia({
    required this.id,
    required this.nombre,
    required this.miembros,
    required this.creadoPor,
    this.activa = true,
    required this.createdAt,
  });

  factory Familia.fromMap(String id, Map<String, dynamic> map) {
    return Familia(
      id: id,
      nombre: map['nombre'] as String? ?? '',
      miembros: (map['miembros'] as List?)?.whereType<String>().toList() ?? [],
      creadoPor: map['creado_por'] as String? ?? '',
      activa: map['activa'] as bool? ?? true,
      createdAt: (map['created_at'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'nombre': nombre,
      'miembros': miembros,
      'creado_por': creadoPor,
      'activa': activa,
      'created_at': Timestamp.fromDate(createdAt),
    };
  }

  Familia copyWith({
    String? nombre,
    List<String>? miembros,
    bool? activa,
  }) {
    return Familia(
      id: id,
      nombre: nombre ?? this.nombre,
      miembros: miembros ?? this.miembros,
      creadoPor: creadoPor,
      activa: activa ?? this.activa,
      createdAt: createdAt,
    );
  }
}
