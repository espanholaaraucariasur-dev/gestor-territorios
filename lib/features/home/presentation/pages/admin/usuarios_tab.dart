import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class UsuariosTab extends StatefulWidget {
  final Map<String, dynamic> usuarioData;

  const UsuariosTab({
    super.key,
    required this.usuarioData,
  });

  @override
  State<UsuariosTab> createState() => _UsuariosTabState();
}

class _UsuariosTabState extends State<UsuariosTab> {
  void _mostrarDialogoGestionUsuarios() {
    // Implementación simulada - en el código original habría diálogo
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Gestión Avanzada de Usuarios - Función no implementada'),
        backgroundColor: Colors.blue,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Gestión de Usuarios',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: Color(0xFF1B5E20),
            ),
          ),
          const SizedBox(height: 12),
          StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance
                .collection('usuarios')
                .snapshots(),
            builder: (context, snapshot) {
              if (!snapshot.hasData) {
                return const Padding(
                  padding: EdgeInsets.only(top: 20),
                  child: Center(child: CircularProgressIndicator()),
                );
              }

              if (snapshot.data!.docs.isEmpty) {
                return const Padding(
                  padding: EdgeInsets.only(top: 20),
                  child: Center(
                    child: Text(
                      'No hay usuarios registrados.',
                      style: TextStyle(
                        color: Colors.grey,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ),
                );
              }

              return Column(
                children: snapshot.data!.docs.map((usuario) {
                  final data =
                      usuario.data() as Map<String, dynamic>;
                  final String nombreUsuario =
                      data['nombre'] ?? 'Usuario';
                  final String emailUsuario = data['email'] ?? '';
                  final String estadoUsuario =
                      data['estado'] ?? 'pendiente';
                  final bool esAdminUsuario =
                      data['es_admin'] ?? false;
                  final bool esConductorUsuario =
                      data['es_conductor'] ?? false;
                  final bool esAdminTerritoriosUsuario =
                      data['es_admin_territorios'] ?? false;
                  final bool esPublicadorUsuario =
                      data['es_publicador'] ?? false;

                  return Card(
                    margin: const EdgeInsets.only(bottom: 12),
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment:
                            CrossAxisAlignment.start,
                        children: [
                          Text(
                            nombreUsuario,
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            emailUsuario,
                            style: const TextStyle(
                              color: Colors.grey,
                              fontSize: 12,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  'Estado: $estadoUsuario',
                                  style: const TextStyle(
                                    color: Colors.black87,
                                  ),
                                ),
                              ),
                              if (estadoUsuario != 'aprobado')
                                ElevatedButton(
                                  onPressed: () async {
                                    await FirebaseFirestore.instance
                                        .collection('usuarios')
                                        .doc(usuario.id)
                                        .update({
                                      'estado': 'aprobado',
                                    });
                                  },
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.green,
                                  ),
                                  child: const Text('Aprobar'),
                                ),
                              if (estadoUsuario == 'aprobado')
                                ElevatedButton(
                                  onPressed: () async {
                                    await FirebaseFirestore.instance
                                        .collection('usuarios')
                                        .doc(usuario.id)
                                        .update({
                                      'estado': 'pendiente',
                                    });
                                  },
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.orange,
                                  ),
                                  child: const Text('Desaprobar'),
                                ),
                              const SizedBox(width: 8),
                              ElevatedButton(
                                onPressed: () async {
                                  bool? confirmar =
                                      await showDialog(
                                    context: context,
                                    builder: (c) => AlertDialog(
                                      title: const Text(
                                        'Eliminar Usuario',
                                      ),
                                      content: Text(
                                        '¿Estás seguro de eliminar a $nombreUsuario?',
                                      ),
                                      actions: [
                                        TextButton(
                                          onPressed: () =>
                                              Navigator.pop(
                                            c,
                                            false,
                                          ),
                                          child: const Text(
                                            'Cancelar',
                                          ),
                                        ),
                                        ElevatedButton(
                                          onPressed: () =>
                                              Navigator.pop(
                                            c,
                                            true,
                                          ),
                                          style: ElevatedButton
                                              .styleFrom(
                                            backgroundColor:
                                                Colors.red,
                                          ),
                                          child: const Text(
                                            'Eliminar',
                                          ),
                                        ),
                                      ],
                                    ),
                                  );
                                  if (confirmar == true) {
                                    await FirebaseFirestore.instance
                                        .collection('usuarios')
                                        .doc(usuario.id)
                                        .delete();
                                  }
                                },
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.red,
                                ),
                                child: const Text('Eliminar'),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          SwitchListTile(
                            title: const Text('Admin'),
                            value: esAdminUsuario,
                            activeThumbColor: Colors.redAccent,
                            contentPadding: EdgeInsets.zero,
                            onChanged: (value) async {
                              await FirebaseFirestore.instance
                                  .collection('usuarios')
                                  .doc(usuario.id)
                                  .update({'es_admin': value});
                            },
                          ),
                          SwitchListTile(
                            title: const Text('Admin Territorios'),
                            value: esAdminTerritoriosUsuario,
                            activeThumbColor: Colors.purple,
                            contentPadding: EdgeInsets.zero,
                            onChanged: (value) async {
                              await FirebaseFirestore.instance
                                  .collection('usuarios')
                                  .doc(usuario.id)
                                  .update({
                                'es_admin_territories': value,
                              });
                            },
                          ),
                          SwitchListTile(
                            title: const Text('Conductor'),
                            value: esConductorUsuario,
                            activeThumbColor: const Color(
                              0xFF1B5E20,
                            ),
                            contentPadding: EdgeInsets.zero,
                            onChanged: (value) async {
                              await FirebaseFirestore.instance
                                  .collection('usuarios')
                                  .doc(usuario.id)
                                  .update({'es_conductor': value});
                            },
                          ),
                          SwitchListTile(
                            title: const Text('Publicador'),
                            value: esPublicadorUsuario,
                            activeThumbColor: Colors.blue,
                            contentPadding: EdgeInsets.zero,
                            onChanged: (value) async {
                              await FirebaseFirestore.instance
                                  .collection('usuarios')
                                  .doc(usuario.id)
                                  .update({'es_publicador': value});
                            },
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Expanded(
                                child: OutlinedButton(
                                  onPressed: () =>
                                      _mostrarDialogoGestionUsuarios(),
                                  child: const Text(
                                    'Gestión avanzada',
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  );
                }).toList(),
              );
            },
          ),
        ],
      ),
    );
  }
}
