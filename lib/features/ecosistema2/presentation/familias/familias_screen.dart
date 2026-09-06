import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../../../core/l10n/translation_service.dart';
import '../../data/familia_service.dart';
import '../../models/familia_model.dart';

const Color _kVerde = Color(0xFF1B5E20);
const Color _kVerdeClaro = Color(0xFF43A047);

class FamiliasScreen extends StatefulWidget {
  final String usuarioUid;
  const FamiliasScreen({super.key, required this.usuarioUid});

  @override
  State<FamiliasScreen> createState() => _FamiliasScreenState();
}

class _FamiliasScreenState extends State<FamiliasScreen> {
  String _busqueda = '';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF1F8E9),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        flexibleSpace: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [_kVerde, _kVerdeClaro],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
        ),
        title: Text(
          context.t('eco2_familias_titulo'),
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 15,
          ),
        ),
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: TextField(
              decoration: InputDecoration(
                hintText: context.t('eco2_familias_buscar'),
                prefixIcon: const Icon(Icons.search),
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
              onChanged: (v) => setState(() => _busqueda = v.toLowerCase()),
            ),
          ),
          Expanded(
            child: StreamBuilder<List<Familia>>(
              stream: FamiliaService.obtenerTodas(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                final todas = snapshot.data ?? [];
                final filtradas = _busqueda.isEmpty
                    ? todas
                    : todas
                        .where((f) =>
                            f.nombre.toLowerCase().contains(_busqueda))
                        .toList();
                if (filtradas.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.family_restroom,
                            size: 64, color: Colors.grey.shade300),
                        const SizedBox(height: 12),
                        Text(
                          context.t('eco2_familias_vacia'),
                          style: TextStyle(
                            color: Colors.grey.shade500,
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                  );
                }
                return ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: filtradas.length,
                  itemBuilder: (ctx, i) =>
                      _buildTarjetaFamilia(context, filtradas[i]),
                );
              },
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: _kVerde,
        onPressed: () => _mostrarDialogoCrear(context),
        child: const Icon(Icons.add, color: Colors.white),
      ),
    );
  }

  Widget _buildTarjetaFamilia(BuildContext context, Familia familia) {
    return Dismissible(
      key: Key(familia.id),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        color: Colors.red,
        child: const Icon(Icons.delete, color: Colors.white),
      ),
      confirmDismiss: (_) async {
        return await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Text(context.t('eco2_familias_confirmar_eliminar')),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: Text(context.t('cancel')),
              ),
              TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: Text(context.t('confirmar'),
                    style: const TextStyle(color: Colors.red)),
              ),
            ],
          ),
        );
      },
      onDismissed: (_) async {
        await FamiliaService.desactivar(familia.id);
      },
      child: Card(
        margin: const EdgeInsets.only(bottom: 10),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () => _mostrarDialogoEditar(context, familia),
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border(
                left: BorderSide(color: _kVerde, width: 4),
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: _kVerde.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.family_restroom,
                      color: _kVerde, size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        familia.nombre,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                          color: Color(0xFF263238),
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        '${familia.miembros.length} ${context.t('eco2_familias_miembros')}',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade600,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right, color: Colors.grey.shade400),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _mostrarDialogoCrear(BuildContext context) {
    final nombreCtrl = TextEditingController();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Padding(
        padding: EdgeInsets.fromLTRB(
            20, 20, 20, MediaQuery.of(ctx).viewInsets.bottom + 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              context.t('eco2_familias_crear'),
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: nombreCtrl,
              decoration: InputDecoration(
                labelText: context.t('eco2_familias_nombre'),
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: _kVerde,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
                onPressed: () async {
                  if (nombreCtrl.text.trim().isEmpty) return;
                  await FamiliaService.crear(
                    nombre: nombreCtrl.text.trim(),
                    creadoPor: widget.usuarioUid,
                  );
                  if (ctx.mounted) Navigator.pop(ctx);
                },
                child: Text(context.t('guardar')),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _mostrarDialogoEditar(BuildContext context, Familia familia) {
    final nombreCtrl = TextEditingController(text: familia.nombre);
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Padding(
        padding: EdgeInsets.fromLTRB(
            20, 20, 20, MediaQuery.of(ctx).viewInsets.bottom + 20),
        child: StatefulBuilder(
          builder: (ctx, setModalState) => Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                familia.nombre,
                style: const TextStyle(
                    fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: nombreCtrl,
                decoration: InputDecoration(
                  labelText: context.t('eco2_familias_nombre'),
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                context.t('eco2_familias_miembros'),
                style: const TextStyle(
                    fontWeight: FontWeight.bold, fontSize: 14),
              ),
              const SizedBox(height: 8),
              StreamBuilder<List<Map<String, dynamic>>>(
                stream: _usuariosAprobadosStream(),
                builder: (context, snapUsuarios) {
                  final usuarios = snapUsuarios.data ?? [];
                  return StreamBuilder<Familia?>(
                    stream: _familiaStream(familia.id),
                    builder: (context, snapFamilia) {
                      final familiaActual = snapFamilia.data;
                      final miembrosActuales = familiaActual?.miembros ?? familia.miembros;
                      return Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: usuarios.map((u) {
                          final uid = u['uid'] as String;
                          final nombre = u['nombre'] as String? ?? uid;
                          final enFamilia = miembrosActuales.contains(uid);
                          return FilterChip(
                            label: Text(nombre,
                                style: const TextStyle(fontSize: 12)),
                            selected: enFamilia,
                            selectedColor: _kVerde.withValues(alpha: 0.2),
                            onSelected: (selected) async {
                              if (selected) {
                                await FamiliaService.agregarMiembro(
                                    familia.id, uid);
                              } else {
                                await FamiliaService.removerMiembro(
                                    familia.id, uid);
                              }
                            },
                          );
                        }).toList(),
                      );
                    },
                  );
                },
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _kVerde,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ),
                  onPressed: () async {
                    if (nombreCtrl.text.trim().isNotEmpty &&
                        nombreCtrl.text.trim() != familia.nombre) {
                      await FamiliaService.actualizar(
                          familia.id, {'nombre': nombreCtrl.text.trim()});
                    }
                    if (ctx.mounted) Navigator.pop(ctx);
                  },
                  child: Text(context.t('guardar')),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Stream<Familia?> _familiaStream(String familiaId) {
    return FirebaseFirestore.instance
        .collection('eco2_familias')
        .doc(familiaId)
        .snapshots()
        .map((doc) {
      if (!doc.exists || doc.data() == null) return null;
      return Familia.fromMap(doc.id, doc.data()!);
    });
  }

  Stream<List<Map<String, dynamic>>> _usuariosAprobadosStream() {
    return FirebaseFirestore.instance
        .collection('usuarios')
        .where('estado', isEqualTo: 'aprobado')
        .snapshots()
        .map((snap) {
      final lista = snap.docs
          .map((d) => {'uid': d.id, 'nombre': d.data()['nombre'] as String? ?? d.id})
          .toList();
      lista.sort((a, b) => (a['nombre'] as String).compareTo(b['nombre'] as String));
      return lista;
    });
  }
}
