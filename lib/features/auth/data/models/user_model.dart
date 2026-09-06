class UserModel {
  final String uid;
  final String email;
  final String nombre;
  final String rol; // 'admin', 'conductor', 'publicador'
  final String? grupoId;
  final bool activo;

  UserModel({
    required this.uid,
    required this.email,
    required this.nombre,
    required this.rol,
    this.grupoId,
    this.activo = true,
  });

  // Mapeo seguro con Fallbacks para usuarios antiguos
  factory UserModel.fromMap(Map<String, dynamic> map, String docId) {
    return UserModel(
      uid: docId,
      email: map['email'] ?? map['correo'] ?? '',
      nombre: map['nombre'] ?? map['displayName'] ?? map['name'] ?? 'Usuario',
      // Si el usuario antiguo no tiene rol asignado, le asigna 'publicador' por defecto
      rol: map['rol'] ?? map['role'] ?? 'publicador',
      grupoId: map['grupoId'] ?? map['groupId'],
      activo: map['activo'] ?? map['active'] ?? true,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'email': email,
      'nombre': nombre,
      'rol': rol,
      'grupoId': grupoId,
      'activo': activo,
      'updatedAt': DateTime.now().toIso8601String(),
    };
  }

  bool get isAdmin => rol == 'admin' || rol == 'superusuario';
  bool get isConductor => rol == 'conductor' || isAdmin;
  bool get isPublicador => rol == 'publicador';
}