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
  // ─────────────────────────────────────────────────────────
  // APROBAR / DESAPROBAR
  // ─────────────────────────────────────────────────────────

  Future<void> _toggleEstado(String docId, String estadoActual) async {
    final nuevoEstado = estadoActual == 'aprobado' ? 'pendiente' : 'aprobado';
    await FirebaseFirestore.instance
        .collection('usuarios')
        .doc(docId)
        .update({'estado': nuevoEstado});
  }

  // ─────────────────────────────────────────────────────────
  // ELIMINAR USUARIO
  // ─────────────────────────────────────────────────────────

  Future<void> _eliminarUsuario(String docId, String nombre) async {
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Eliminar usuario'),
        content:
            Text('¿Eliminar a "$nombre"? Esta acción no se puede deshacer.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(c, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
    if (confirmar != true) return;
    await FirebaseFirestore.instance.collection('usuarios').doc(docId).delete();
  }

  // ─────────────────────────────────────────────────────────
  // TOGGLE ROL
  // ─────────────────────────────────────────────────────────

  Future<void> _toggleRol(String docId, String campo, bool valorActual) async {
    await FirebaseFirestore.instance
        .collection('usuarios')
        .doc(docId)
        .update({campo: !valorActual});
  }

  // ─────────────────────────────────────────────────────────
  // BUILD
  // ─────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('usuarios')
          .orderBy('nombre')
          .snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final usuarios = snapshot.data!.docs;

        if (usuarios.isEmpty) {
          return const Center(
            child: Text(
              'No hay usuarios registrados.',
              style: TextStyle(color: Colors.grey),
            ),
          );
        }

        // Separar pendientes de aprobados
        final pendientes = usuarios.where((u) {
          final d = u.data() as Map<String, dynamic>;
          return (d['estado'] ?? 'pendiente') != 'aprobado';
        }).toList();

        final aprobados = usuarios.where((u) {
          final d = u.data() as Map<String, dynamic>;
          return (d['estado'] ?? 'pendiente') == 'aprobado';
        }).toList();

        return SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Pendientes de aprobación ──────────────────
              if (pendientes.isNotEmpty) ...[
                Row(
                  children: [
                    Container(
                      width: 4,
                      height: 16,
                      decoration: BoxDecoration(
                        color: Colors.orange,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'PENDIENTES (${pendientes.length})',
                      style: const TextStyle(
                        fontSize: 11,
                        letterSpacing: 1.5,
                        fontWeight: FontWeight.w700,
                        color: Colors.orange,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                ...pendientes.map((u) => _buildUsuarioCard(u)),
                const SizedBox(height: 20),
              ],

              // ── Aprobados ─────────────────────────────────
              Row(
                children: [
                  Container(
                    width: 4,
                    height: 16,
                    decoration: BoxDecoration(
                      color: const Color(0xFF1B5E20),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'APROBADOS (${aprobados.length})',
                    style: const TextStyle(
                      fontSize: 11,
                      letterSpacing: 1.5,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF1B5E20),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              if (aprobados.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text('No hay usuarios aprobados.',
                      style: TextStyle(color: Colors.grey)),
                )
              else
                ...aprobados.map((u) => _buildUsuarioCard(u)),
            ],
          ),
        );
      },
    );
  }

  // ─────────────────────────────────────────────────────────
  // CARD DE USUARIO
  // ─────────────────────────────────────────────────────────

  Widget _buildUsuarioCard(DocumentSnapshot usuario) {
    final data = usuario.data() as Map<String, dynamic>;
    final nombre = (data['nombre'] as String?) ?? 'Usuario';
    final email = (data['email'] as String?) ?? '';
    final estado = (data['estado'] as String?) ?? 'pendiente';
    final esAdmin = (data['es_admin'] as bool?) ?? false;
    final esAdminTer = (data['es_admin_territorios'] as bool?) ?? false;
    final esConductor = (data['es_conductor'] as bool?) ?? false;
    final esPublicador = (data['es_publicador'] as bool?) ?? false;
    final aprobado = estado == 'aprobado';

    // Iniciales
    final iniciales = nombre.isNotEmpty
        ? nombre.trim().split(' ').take(2).map((p) => p[0]).join()
        : '?';

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border(
          left: BorderSide(
            color: aprobado ? const Color(0xFF1B5E20) : Colors.orange,
            width: 4,
          ),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Cabecera ────────────────────────────────────
            Row(
              children: [
                // Avatar
                CircleAvatar(
                  radius: 22,
                  backgroundColor: aprobado
                      ? const Color(0xFF1B5E20).withOpacity(0.12)
                      : Colors.orange.withOpacity(0.12),
                  child: Text(
                    iniciales.toUpperCase(),
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                      color: aprobado ? const Color(0xFF1B5E20) : Colors.orange,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        nombre,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                          color: Color(0xFF263238),
                        ),
                      ),
                      Text(
                        email,
                        style: const TextStyle(
                          fontSize: 12,
                          color: Colors.grey,
                        ),
                      ),
                    ],
                  ),
                ),
                // Badge estado
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: aprobado
                        ? const Color(0xFF1B5E20).withOpacity(0.1)
                        : Colors.orange.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    aprobado ? 'Aprobado' : 'Pendiente',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: aprobado ? const Color(0xFF1B5E20) : Colors.orange,
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 14),
            Divider(height: 1, color: Colors.grey.shade100),
            const SizedBox(height: 12),

            // ── Roles ────────────────────────────────────────
            const Text(
              'ROLES',
              style: TextStyle(
                fontSize: 10,
                letterSpacing: 1.2,
                fontWeight: FontWeight.w700,
                color: Colors.grey,
              ),
            ),
            const SizedBox(height: 8),
            _rolSwitch(
              label: 'Administrador',
              icon: Icons.admin_panel_settings,
              color: Colors.red,
              value: esAdmin,
              onChanged: (v) => _toggleRol(usuario.id, 'es_admin', esAdmin),
            ),
            _rolSwitch(
              label: 'Admin Territorios',
              icon: Icons.map,
              color: Colors.purple,
              value: esAdminTer,
              onChanged: (v) =>
                  _toggleRol(usuario.id, 'es_admin_territorios', esAdminTer),
            ),
            _rolSwitch(
              label: 'Conductor',
              icon: Icons.drive_eta,
              color: const Color(0xFF1B5E20),
              value: esConductor,
              onChanged: (v) =>
                  _toggleRol(usuario.id, 'es_conductor', esConductor),
            ),
            _rolSwitch(
              label: 'Publicador',
              icon: Icons.person,
              color: Colors.blue,
              value: esPublicador,
              onChanged: (v) =>
                  _toggleRol(usuario.id, 'es_publicador', esPublicador),
            ),

            const SizedBox(height: 12),
            Divider(height: 1, color: Colors.grey.shade100),
            const SizedBox(height: 12),

            // ── Acciones ─────────────────────────────────────
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _toggleEstado(usuario.id, estado),
                    icon: Icon(
                      aprobado ? Icons.block : Icons.check_circle_outline,
                      size: 16,
                    ),
                    label: Text(
                      aprobado ? 'Desaprobar' : 'Aprobar',
                      style: const TextStyle(fontSize: 13),
                    ),
                    style: OutlinedButton.styleFrom(
                      foregroundColor:
                          aprobado ? Colors.orange : const Color(0xFF1B5E20),
                      side: BorderSide(
                        color:
                            aprobado ? Colors.orange : const Color(0xFF1B5E20),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 10),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  onPressed: () => _eliminarUsuario(usuario.id, nombre),
                  icon: const Icon(Icons.delete_outline, size: 16),
                  label: const Text('Eliminar', style: TextStyle(fontSize: 13)),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.red,
                    side: const BorderSide(color: Colors.red),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 10),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────
  // ROL SWITCH
  // ─────────────────────────────────────────────────────────

  Widget _rolSwitch({
    required String label,
    required IconData icon,
    required Color color,
    required bool value,
    required Function(bool) onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: value ? color.withOpacity(0.1) : Colors.grey.shade100,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              icon,
              size: 16,
              color: value ? color : Colors.grey.shade400,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 14,
                fontWeight: value ? FontWeight.w600 : FontWeight.w400,
                color: value ? const Color(0xFF263238) : Colors.grey,
              ),
            ),
          ),
          Switch(
            value: value,
            onChanged: onChanged,
            activeColor: color,
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
        ],
      ),
    );
  }
}
