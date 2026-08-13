import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
// Traducciones
import '../../../core/l10n/translation_service.dart';

// ─────────────────────────────────────────────────────────────
// ECOSISTEMA 2 · MANTENIMIENTO
// Botón principal: "Hacer visible" → elige qué usuarios pueden
// ver y acceder a la congregación. Bloqueado con PIN 272700.
// ─────────────────────────────────────────────────────────────

class Ecosistema2MantenimientoScreen extends StatefulWidget {
  const Ecosistema2MantenimientoScreen({super.key});

  @override
  State<Ecosistema2MantenimientoScreen> createState() =>
      _Ecosistema2MantenimientoScreenState();
}

class _Ecosistema2MantenimientoScreenState
    extends State<Ecosistema2MantenimientoScreen> {
  static const String _pinLocal = '272700';
  bool _desbloqueado = false;
  Set<String> _usuariosVisibles = <String>{};

  @override
  void initState() {
    super.initState();
    _cargarVisibilidad();
  }

  // ── Cargar selección guardada ─────────────────────────────
  Future<void> _cargarVisibilidad() async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('configuracion')
          .doc('ecosistema2_visibilidad')
          .get();
      if (!doc.exists || !mounted) return;
      final ids = (doc.data()?['usuario_ids'] as List?)
              ?.whereType<String>()
              .toList() ??
          const <String>[];
      setState(() => _usuariosVisibles = ids.toSet());
    } catch (_) {}
  }

  // ── Guardar selección ─────────────────────────────────────
  Future<void> _guardarVisibilidad(Set<String> ids) async {
    setState(() => _usuariosVisibles = ids);
    try {
      await FirebaseFirestore.instance
          .collection('configuracion')
          .doc('ecosistema2_visibilidad')
          .set({'usuario_ids': ids.toList()}, SetOptions(merge: true));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('❌ $e'), backgroundColor: Colors.red),
        );
      }
      return;
    }
    if (mounted) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(context.t('eco2_visibilidad_guardado')),
            backgroundColor: const Color(0xFF1B5E20),
            behavior: SnackBarBehavior.floating,
          ),
        );
    }
  }

  // ── Verificar PIN ─────────────────────────────────────────
  Future<void> _verificarPin() async {
    final ctrl = TextEditingController();
    final ingresado = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (c) => StatefulBuilder(
        builder: (context, setDlg) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(
            children: [
              const Icon(Icons.lock_outline, color: Color(0xFF1B5E20)),
              const SizedBox(width: 8),
              Text(context.t('eco2_pin_titulo')),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                context.t('eco2_pin_desc'),
                style: const TextStyle(fontSize: 13, color: Colors.grey),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              TextField(
                controller: ctrl,
                keyboardType: TextInputType.number,
                maxLength: 6,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 8),
                decoration: InputDecoration(
                  counterText: '',
                  border:
                      OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  filled: true,
                  fillColor: Colors.grey.shade50,
                ),
                autofocus: true,
                onSubmitted: (v) => Navigator.pop(c, v),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c, null),
              child: Text(context.t('eco2_pin_cancelar')),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(c, ctrl.text),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF1B5E20),
                foregroundColor: Colors.white,
              ),
              child: Text(context.t('eco2_pin_ingresar')),
            ),
          ],
        ),
      ),
    );
    ctrl.dispose();
    if (ingresado == null) return;

    final doc = await FirebaseFirestore.instance
        .collection('configuracion')
        .doc('pin_mantenimiento')
        .get();
    final pinCorrecto = (doc.data()?['pin'] as String?) ?? _pinLocal;

    if (ingresado == pinCorrecto) {
      if (mounted) setState(() => _desbloqueado = true);
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(context.t('eco2_pin_incorrecto')),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _abrirSelectorAcceso() async {
    final resultado = await showModalBottomSheet<List<String>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (c) => _SelectorUsuariosSheet(
        seleccionInicial: _usuariosVisibles,
      ),
    );
    if (resultado != null) {
      await _guardarVisibilidad(resultado.toSet());
    }
  }

  // ── Pantalla de bloqueo ───────────────────────────────────
  Widget _buildBloqueo(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: const Color(0xFF1B5E20).withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.lock_outline,
                  size: 48, color: Color(0xFF1B5E20)),
            ),
            const SizedBox(height: 20),
            Text(
              context.t('eco2_section_maintenance'),
              style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF1B5E20)),
            ),
            const SizedBox(height: 8),
            Text(
              context.t('eco2_maintenance_desc'),
              style: TextStyle(color: Colors.grey.shade600),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _verificarPin,
              icon: const Icon(Icons.lock_open_outlined),
              label: Text(context.t('eco2_pin_ingresar_pin')),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF1B5E20),
                foregroundColor: Colors.white,
                padding:
                    const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Contenido del mantenimiento ───────────────────────────
  Widget _buildContenido(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            context.t('eco2_maintenance_desc'),
            style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
          ),
          const SizedBox(height: 16),
          // ── Botón principal: hacer visible ────────────────
          Material(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            child: InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: _abrirSelectorAcceso,
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  border: const Border(
                    left: BorderSide(color: Color(0xFF1B5E20), width: 4),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF1B5E20).withValues(alpha: 0.08),
                      blurRadius: 8,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    Container(
                      width: 46,
                      height: 46,
                      decoration: BoxDecoration(
                        color:
                            const Color(0xFF1B5E20).withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(Icons.visibility_outlined,
                          color: Color(0xFF1B5E20), size: 24),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            context.t('eco2_visibilidad_boton'),
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 15,
                              color: Color(0xFF263238),
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            context.t('eco2_visibilidad_boton_desc'),
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey.shade600,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (_usuariosVisibles.isNotEmpty)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 9, vertical: 4),
                        decoration: BoxDecoration(
                          color: const Color(0xFF1B5E20)
                              .withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          '${_usuariosVisibles.length}',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                            color: Color(0xFF1B5E20),
                          ),
                        ),
                      ),
                    const SizedBox(width: 4),
                    Icon(Icons.chevron_right, color: Colors.grey.shade400),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.amber.shade50,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.amber.shade200),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.info_outline,
                    color: Colors.amber.shade800, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    context.t('eco2_maintenance_nota'),
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.amber.shade900,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

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
              colors: [Color(0xFF1B5E20), Color(0xFF0277BD)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
        ),
        title: Text(
          context.t('eco2_section_maintenance'),
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 15,
            letterSpacing: 0.3,
          ),
        ),
        centerTitle: true,
      ),
      body: _desbloqueado ? _buildContenido(context) : _buildBloqueo(context),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// SELECTOR DE USUARIOS (bottom sheet)
// Muestra la lista de usuarios aprobados con casillas para
// elegir quién puede ver y acceder a la congregación.
// ─────────────────────────────────────────────────────────────
class _SelectorUsuariosSheet extends StatefulWidget {
  final Set<String> seleccionInicial;

  const _SelectorUsuariosSheet({required this.seleccionInicial});

  @override
  State<_SelectorUsuariosSheet> createState() => _SelectorUsuariosSheetState();
}

class _SelectorUsuariosSheetState extends State<_SelectorUsuariosSheet> {
  late final Set<String> _seleccion = {...widget.seleccionInicial};
  final TextEditingController _busquedaCtrl = TextEditingController();
  String _busqueda = '';

  @override
  void dispose() {
    _busquedaCtrl.dispose();
    super.dispose();
  }

  void _guardar() {
    Navigator.pop(context, _seleccion.toList());
  }

  Widget _buildUsuarioItem(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    final nombre = (data['nombre'] as String?) ?? 'Usuario';
    final email = (data['email'] as String?) ?? '';
    final seleccionado = _seleccion.contains(doc.id);
    final iniciales = nombre
        .trim()
        .split(' ')
        .take(2)
        .map((p) => p.isNotEmpty ? p[0] : '')
        .join();

    return Material(
      color: seleccionado
          ? const Color(0xFF1B5E20).withValues(alpha: 0.06)
          : Colors.transparent,
      child: InkWell(
        onTap: () => setState(() {
          if (seleccionado) {
            _seleccion.remove(doc.id);
          } else {
            _seleccion.add(doc.id);
          }
        }),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          child: Row(
            children: [
              CircleAvatar(
                radius: 20,
                backgroundColor:
                    const Color(0xFF1B5E20).withValues(alpha: 0.12),
                child: Text(
                  iniciales.toUpperCase(),
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                    color: Color(0xFF1B5E20),
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
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                        color: Color(0xFF263238),
                      ),
                    ),
                    Text(
                      email,
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade600,
                      ),
                    ),
                  ],
                ),
              ),
              Checkbox(
                value: seleccionado,
                activeColor: const Color(0xFF1B5E20),
                onChanged: (v) => setState(() {
                  if (v == true) {
                    _seleccion.add(doc.id);
                  } else {
                    _seleccion.remove(doc.id);
                  }
                }),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: ConstrainedBox(
        constraints:
            BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.85),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 12),
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  const Icon(Icons.visibility_outlined,
                      color: Color(0xFF1B5E20), size: 22),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      context.t('eco2_visibilidad_titulo'),
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF263238),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 6),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Text(
                context.t('eco2_visibilidad_desc'),
                style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
              ),
            ),
            const SizedBox(height: 14),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: TextField(
                controller: _busquedaCtrl,
                onChanged: (v) => setState(() => _busqueda = v.trim()),
                decoration: InputDecoration(
                  hintText: context.t('eco2_visibilidad_buscar'),
                  prefixIcon: const Icon(Icons.search_outlined, size: 20),
                  isDense: true,
                  filled: true,
                  fillColor: Colors.grey.shade50,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 10),
            Expanded(
              child: StreamBuilder<QuerySnapshot>(
                stream: FirebaseFirestore.instance
                    .collection('usuarios')
                    .orderBy('nombre')
                    .snapshots(),
                builder: (context, snapshot) {
                  if (snapshot.hasError) {
                    return Center(
                      child: Text('${snapshot.error}',
                          style: const TextStyle(color: Colors.red)),
                    );
                  }
                  if (!snapshot.hasData) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  final usuarios = snapshot.data!.docs.where((u) {
                    final d = u.data() as Map<String, dynamic>;
                    return (d['estado'] ?? 'pendiente') == 'aprobado';
                  }).toList();
                  final filtrados = _busqueda.isEmpty
                      ? usuarios
                      : usuarios.where((u) {
                          final d = u.data() as Map<String, dynamic>;
                          final nombre = (d['nombre'] as String?) ?? '';
                          final email = (d['email'] as String?) ?? '';
                          final q = _busqueda.toLowerCase();
                          return nombre.toLowerCase().contains(q) ||
                              email.toLowerCase().contains(q);
                        }).toList();
                  if (filtrados.isEmpty) {
                    return Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.person_search_outlined,
                              size: 40, color: Colors.grey.shade400),
                          const SizedBox(height: 8),
                          Text(
                            context.t('eco2_visibilidad_sin_usuarios'),
                            style: TextStyle(color: Colors.grey.shade600),
                          ),
                        ],
                      ),
                    );
                  }
                  return ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    itemCount: filtrados.length,
                    itemBuilder: (context, i) =>
                        _buildUsuarioItem(filtrados[i]),
                  );
                },
              ),
            ),
            const SizedBox(height: 6),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_seleccion.isEmpty)
                    Text(
                      context.t('eco2_visibilidad_vacio_desc'),
                      style: TextStyle(
                          fontSize: 12, color: Colors.grey.shade600),
                    )
                  else
                    Text(
                      '${_seleccion.length} · '
                      '${context.t('eco2_visibilidad_seleccionados')}',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF1B5E20),
                      ),
                    ),
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: _guardar,
                      icon: const Icon(Icons.check, size: 18),
                      label: Text(context.t('save')),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF1B5E20),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
