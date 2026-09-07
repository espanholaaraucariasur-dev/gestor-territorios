import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

const Color _verdePrincipal = Color(0xFF1C5924);
const Color _fondoVerdeSuave = Color(0xFFF2F7F2);

/// Clase para gestionar sub-unidades dentro de un mismo terreno o condominio.
class _Unidad {
  final TextEditingController bloque = TextEditingController();
  final TextEditingController piso = TextEditingController();
  final TextEditingController aptoCasa = TextEditingController();
  final TextEditingController extra = TextEditingController();

  /// Formato compuesto para Condominios (ej: blo A piso 2 apt 102)
  String get textoCondominio {
    final partes = <String>[];
    if (bloque.text.trim().isNotEmpty) partes.add('blo ${bloque.text.trim()}');
    if (piso.text.trim().isNotEmpty) partes.add('piso ${piso.text.trim()}');
    if (aptoCasa.text.trim().isNotEmpty) partes.add('apt ${aptoCasa.text.trim()}');
    if (extra.text.trim().isNotEmpty) partes.add(extra.text.trim());
    return partes.join(' ');
  }

  /// Formato compuesto para Varias Casas (ej: Casa 1 / Frente)
  String get textoVariasCasas {
    final blo = bloque.text.trim();
    final numCasa = aptoCasa.text.trim();
    if (blo.isEmpty && numCasa.isNotEmpty) return 'Casa $numCasa';
    return [
      if (blo.isNotEmpty) blo,
      if (extra.text.trim().isNotEmpty) extra.text.trim(),
    ].join(' ');
  }

  bool get estaVacia =>
      bloque.text.trim().isEmpty &&
      piso.text.trim().isEmpty &&
      aptoCasa.text.trim().isEmpty &&
      extra.text.trim().isEmpty;

  void dispose() {
    bloque.dispose();
    piso.dispose();
    aptoCasa.dispose();
    extra.dispose();
  }
}

class EnviarDireccionCard extends StatefulWidget {
  final String usuarioNombre;
  final String usuarioEmail;
  final VoidCallback onEnviado;

  const EnviarDireccionCard({
    super.key,
    required this.usuarioNombre,
    required this.usuarioEmail,
    required this.onEnviado,
  });

  @override
  State<EnviarDireccionCard> createState() => _EnviarDireccionCardState();
}

class _EnviarDireccionCardState extends State<EnviarDireccionCard> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _calleController = TextEditingController();
  final TextEditingController _complementoController = TextEditingController();

  bool _enviando = false;
  bool _agregandoMas = false;

  // Modalidades avanzadas (Varias Casas / Condominio)
  bool _variasCasas = false;
  bool _condominio = false;
  final List<_Unidad> _unidades = [_Unidad()];

  // Casas o departamentos ya registrados para la misma dirección base
  final Set<String> _casasExistentesNorm = {};
  final List<String> _casasExistentesLabel = [];

  bool get _modalidadMultipla => _variasCasas || _condominio;

  @override
  void dispose() {
    _calleController.dispose();
    _complementoController.dispose();
    for (final u in _unidades) {
      u.dispose();
    }
    super.dispose();
  }

  void _toggleModalidad(String tipo, bool valor) {
    setState(() {
      if (tipo == 'casas') {
        _variasCasas = valor;
        if (valor) _condominio = false;
      } else {
        _condominio = valor;
        if (valor) _variasCasas = false;
      }

      if (_modalidadMultipla && _unidades.length == 1 && !_unidades.first.estaVacia) {
        _unidades.add(_Unidad());
      }
    });
  }

  void _agregarUnidad() {
    setState(() => _unidades.add(_Unidad()));
  }

  void _quitarUnidad(int index) {
    setState(() {
      _unidades[index].dispose();
      _unidades.removeAt(index);
      if (_unidades.isEmpty) _unidades.add(_Unidad());
    });
  }

  String _norm(String s) {
    const comAcentos = 'ÀÁÂÃÄÅÇÈÉÊËÌÍÎÏÑÒÓÔÕÖÙÚÛÜÝàáâãäåçèéêëìíîïñòóôõöùúûüýÿ';
    const semAcentos = 'AAAAAACEEEEIIIINOOOOOUUUUYaaaaaaceeeeiiiinooooouuuuyy';
    final buf = StringBuffer();
    for (int i = 0; i < s.length; i++) {
      final ch = s[i];
      final idx = comAcentos.indexOf(ch);
      buf.write(idx >= 0 ? semAcentos[idx] : ch);
    }
    return buf.toString().trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
  }

  String _normSinPuntuacion(String s) => _norm(s).replaceAll(RegExp(r'[,.\-]'), '');

  bool _esPrefijoOIgual(String base, String s) {
    if (s.isEmpty || base.isEmpty) return false;
    if (s == base) return true;
    if (s.startsWith('$base ') || s.startsWith('$base,')) return true;
    if (base.startsWith('$s,') || base.startsWith('$s ')) return true;
    return false;
  }

  bool _coincideBase(String base, Map<String, dynamic> e) {
    final calle = (e['calle'] as String?) ?? '';
    final completa = (e['completa'] as String?) ?? '';
    final comunBase = _normSinPuntuacion(base);
    if (_esPrefijoOIgual(_normSinPuntuacion(calle), comunBase)) return true;
    if (_esPrefijoOIgual(_normSinPuntuacion(completa), comunBase)) return true;
    return false;
  }

  String? _errorDeUnidad(_Unidad u) {
    if (u.estaVacia) return null;
    final comp = _norm(_condominio ? u.textoCondominio : u.textoVariasCasas);
    if (comp.isEmpty) return null;

    if (_casasExistentesNorm.contains(comp)) {
      return 'Ya registrada en la base de datos.';
    }

    final repetido = _unidades.any((o) =>
        o != u &&
        _norm(_condominio ? o.textoCondominio : o.textoVariasCasas) == comp);
    if (repetido) return 'Repetida en esta lista.';

    return null;
  }

  List<Map<String, String>> _generarEstructuraDirecciones() {
    final base = _calleController.text.trim();
    if (base.isEmpty) return [];

    if (!_modalidadMultipla) {
      final comp = _complementoController.text.trim();
      return [
        {
          'texto': base,
          'tipo': comp.isEmpty ? 'normal' : 'multiples_casas',
          'complemento': comp,
        },
      ];
    }

    final resultado = <Map<String, String>>[
      {
        'texto': base,
        'tipo': _condominio ? 'condominio' : 'multiples_casas',
        'complemento': '',
      },
    ];

    for (final u in _unidades) {
      if (u.estaVacia) continue;
      final comp = _condominio ? u.textoCondominio : u.textoVariasCasas;
      if (comp.isEmpty) continue;

      resultado.add({
        'texto': '$base, $comp',
        'tipo': _condominio ? 'condominio' : 'multiples_casas',
        'complemento': comp,
      });
    }

    return resultado;
  }

  Future<List<Map<String, dynamic>>> _cargarExistentes() async {
    final snap = await FirebaseFirestore.instance
        .collection('direcciones_globales')
        .get();
    return snap.docs.map((d) {
      final data = d.data();
      final calle = _norm((data['calle'] ?? data['texto_direccion'] ?? '').toString());
      final complemento = _norm((data['complemento'] ?? '').toString());
      final completa = _norm((data['direccion_normalizada'] ?? '$calle $complemento').toString());
      return {
        'calle': calle,
        'complemento': complemento,
        'completa': completa,
        'es_condominio': data['es_condominio'] == true,
      };
    }).toList();
  }

  Future<List<Map<String, dynamic>>> _cargarPendientes() async {
    try {
      final snap = await FirebaseFirestore.instance
          .collection('sugerencias')
          .get();
      return snap.docs.map((d) {
        final data = d.data();
        return {
          'completa': _norm((data['texto_direccion'] ?? data['calle'] ?? '').toString()),
          'complemento': _norm((data['complemento'] ?? '').toString()),
          'tipo': (data['tipo_entrega'] ?? '').toString(),
        };
      }).toList();
    } catch (_) {
      return [];
    }
  }

  String _detectarTipo(List<Map<String, dynamic>> globales, List<Map<String, dynamic>> pendientes) {
    final candidatos = [...globales, ...pendientes];
    String? tipoPendiente;
    for (final e in candidatos) {
      if (e['es_condominio'] == true || e['tipo'] == 'condominio') return 'condominio';
      if (e['tipo'] == 'multiples_casas') tipoPendiente ??= 'multicasas';
      final c = (e['complemento'] as String?) ?? '';
      if (c.isNotEmpty) {
        if (c.contains('apt') || c.contains('blo') || c.contains('bloco') || c.contains('piso')) {
          return 'condominio';
        }
        tipoPendiente ??= 'multicasas';
      }
    }
    return tipoPendiente ?? 'simple';
  }

  Future<void> _mostrarAvisoSimple() async {
    await showDialog<void>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Dirección ya registrada'),
        content: const Text(
          'Esta dirección ya está registrada en la base de datos. No es posible enviarla nuevamente.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c),
            child: const Text('Entendido'),
          ),
        ],
      ),
    );
  }

  Future<void> _mostrarDialogoExistente(String tipo) async {
    final esCondo = tipo == 'condominio';
    final aceptar = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(esCondo ? 'Condominio ya registrado' : 'Terreno multi-casa ya registrado'),
        content: Text(
          esCondo
              ? 'Esta dirección ya figura como CONDOMINIO. Puedes agregar nuevos departamentos.'
              : 'Esta dirección ya figura con VARIAS CASAS. Puedes agregar más casas a la lista.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: _verdePrincipal),
            onPressed: () => Navigator.pop(c, true),
            child: Text(
              esCondo ? 'Agregar departamentos' : 'Agregar casas',
              style: const TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
    );

    if (aceptar != true || !mounted) return;
    setState(() {
      _agregandoMas = true;
      _condominio = esCondo;
      _variasCasas = !esCondo;
      if (!_unidades.any((u) => u.estaVacia)) _unidades.add(_Unidad());
    });
  }

  Future<void> _enviarDireccion() async {
    if (!_formKey.currentState!.validate()) return;

    final listaGenerada = _generarEstructuraDirecciones();
    if (listaGenerada.isEmpty) return;

    setState(() => _enviando = true);

    try {
      final existentes = await _cargarExistentes();
      final baseNorm = _norm(_calleController.text.trim());

      final coincidencias = existentes.where((e) => _coincideBase(baseNorm, e)).toList();
      final pendientes = await _cargarPendientes();
      final pendientesBase = pendientes.where((e) => _coincideBase(baseNorm, e)).toList();
      final historialBase = [...coincidencias, ...pendientesBase];

      if (historialBase.isNotEmpty && !_agregandoMas) {
        final tipo = _detectarTipo(coincidencias, pendientesBase);
        final unidadesActuales = historialBase
            .where((e) => ((e['complemento'] as String?) ?? '').isNotEmpty)
            .toList();

        setState(() {
          _casasExistentesNorm.clear();
          _casasExistentesLabel.clear();
          for (final e in unidadesActuales) {
            final comp = _norm((e['complemento'] ?? '').toString());
            _casasExistentesNorm.add(comp);
            _casasExistentesLabel.add((e['complemento'] ?? '').toString());
          }
        });

        if (tipo == 'simple') {
          await _mostrarAvisoSimple();
        } else {
          await _mostrarDialogoExistente(tipo);
        }
        return;
      }

      final duplicadosExistentes = <String>[];
      final duplicadosEnLista = <String>[];
      final vistos = <String>{};

      for (final item in listaGenerada) {
        final comp = _norm((item['complemento'] ?? '').toString());
        if (comp.isEmpty) continue;

        if (_casasExistentesNorm.contains(comp)) {
          duplicadosExistentes.add(item['texto'] ?? comp);
        } else if (vistos.contains(comp)) {
          duplicadosEnLista.add(item['texto'] ?? comp);
        }
        vistos.add(comp);
      }

      if (duplicadosExistentes.isNotEmpty) {
        _mostrarSnackBar('Ya registradas: ${duplicadosExistentes.join(', ')}', Colors.red);
        return;
      }

      if (duplicadosEnLista.isNotEmpty) {
        _mostrarSnackBar('Casas repetidas en tu formulario: ${duplicadosEnLista.join(', ')}', Colors.red);
        return;
      }

      final enviar = <Map<String, String>>[...listaGenerada];
      if (_agregandoMas) {
        enviar.removeWhere((item) => (item['complemento'] ?? '').isEmpty);
      }

      final batch = FirebaseFirestore.instance.batch();
      final totalFinal = historialBase.length + enviar.length;

      for (final item in enviar) {
        final ref = FirebaseFirestore.instance.collection('sugerencias').doc();
        batch.set(ref, {
          'texto_direccion': item['texto'],
          'complemento': item['complemento'],
          'tipo_entrega': item['tipo'],
          'es_condominio': item['tipo'] == 'condominio',
          'cantidad_unidades': totalFinal,
          'fecha_ingreso': FieldValue.serverTimestamp(),
          'enviado_por': widget.usuarioEmail,
          'usuario_nombre': widget.usuarioNombre,
          'estado': 'PENDIENTE_AUDITORIA',
        });
      }

      await batch.commit();

      _calleController.clear();
      _complementoController.clear();
      for (final u in _unidades) {
        u.dispose();
      }

      setState(() {
        _agregandoMas = false;
        _variasCasas = false;
        _condominio = false;
        _casasExistentesNorm.clear();
        _casasExistentesLabel.clear();
        _unidades
          ..clear()
          ..add(_Unidad());
      });

      widget.onEnviado();
      _mostrarSnackBar('¡Dirección enviada correctamente a auditoría!', _verdePrincipal);
    } catch (e) {
      _mostrarSnackBar('Error al procesar: $e', Colors.red);
    } finally {
      if (mounted) setState(() => _enviando = false);
    }
  }

  void _mostrarSnackBar(String texto, Color fondo) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(texto),
        backgroundColor: fondo,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

 @override
Widget build(BuildContext context) {
  return Container(
    margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
    padding: const EdgeInsets.all(24),
    decoration: BoxDecoration(
      color: _fondoVerdeSuave,
      borderRadius: BorderRadius.circular(28),
    ),
    child: Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Cabecera con Icono de Ubicación integrando el Pin Verde
          Row(
            children: [
              Icon(
                Icons.location_on,
                color: _verdePrincipal,
                size: 26,
              ),
              const SizedBox(width: 8),
              const Text(
                'Direcciones nuevas',
                style: TextStyle(
                  fontSize: 19,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF1A1C1E),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),

          // Campo Calle y Número
          TextFormField(
            controller: _calleController,
            textCapitalization: TextCapitalization.sentences,
            style: const TextStyle(fontSize: 15, color: Color(0xFF2C312E)),
            validator: (val) {
              if (val == null || val.trim().isEmpty) {
                return 'Ingresa la calle y número';
              }
              return null;
            },
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.add_location_alt_outlined, color: _verdePrincipal, size: 20),
              hintText: 'Calle y número (ej: Calle Flores 123)',
              hintStyle: const TextStyle(color: Color(0xFF727873), fontSize: 14),
              filled: true,
              fillColor: Colors.white,
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: const BorderSide(color: Color(0xFFE0ECE1)),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: const BorderSide(color: Color(0xFFE0ECE1)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: const BorderSide(color: _verdePrincipal, width: 1.5),
              ),
            ),
          ),
          const SizedBox(height: 12),

          // Campo Complemento
          if (!_modalidadMultipla) ...[
            TextFormField(
              controller: _complementoController,
              textCapitalization: TextCapitalization.sentences,
              style: const TextStyle(fontSize: 15, color: Color(0xFF2C312E)),
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.home_outlined, color: _verdePrincipal, size: 20),
                hintText: 'Complemento (opcional). Ej: casa 5, apto 3',
                hintStyle: const TextStyle(color: Color(0xFF727873), fontSize: 14),
                filled: true,
                fillColor: Colors.white,
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: const BorderSide(color: Color(0xFFE0ECE1)),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: const BorderSide(color: Color(0xFFE0ECE1)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: const BorderSide(color: _verdePrincipal, width: 1.5),
                ),
              ),
            ),
            const SizedBox(height: 16),
          ],

          // Subtítulo con mejor espaciado
          const Text(
            '¿Varias casas en el mismo terreno o un condominio?',
            style: TextStyle(
              fontSize: 13,
              color: Color(0xFF3B493E),
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 12),

          // Checkboxes
          Row(
            children: [
              Expanded(
                child: InkWell(
                  onTap: () => _toggleModalidad('casas', !_variasCasas),
                  borderRadius: BorderRadius.circular(8),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 24,
                        height: 24,
                        child: Checkbox(
                          value: _variasCasas,
                          onChanged: (v) => _toggleModalidad('casas', v ?? false),
                          activeColor: _verdePrincipal,
                          side: const BorderSide(color: Color(0xFF424944), width: 1.5),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                        ),
                      ),
                      const SizedBox(width: 8),
                      const Text(
                        'Varias casas',
                        style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Color(0xFF1A1C1E)),
                      ),
                    ],
                  ),
                ),
              ),
              Expanded(
                child: InkWell(
                  onTap: () => _toggleModalidad('condominio', !_condominio),
                  borderRadius: BorderRadius.circular(8),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 24,
                        height: 24,
                        child: Checkbox(
                          value: _condominio,
                          onChanged: (v) => _toggleModalidad('condominio', v ?? false),
                          activeColor: _verdePrincipal,
                          side: const BorderSide(color: Color(0xFF424944), width: 1.5),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                        ),
                      ),
                      const SizedBox(width: 8),
                      const Text(
                        'Condominio',
                        style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Color(0xFF1A1C1E)),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),

          if (_modalidadMultipla) ...[
            const SizedBox(height: 16),
            _buildUnidadesEditor(),
            if (_agregandoMas && _casasExistentesLabel.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                _condominio ? 'DEPARTAMENTOS REGISTRADOS:' : 'CASAS REGISTRADAS:',
                style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: _verdePrincipal),
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: _casasExistentesLabel
                    .map((label) => Chip(
                          label: Text(label, style: const TextStyle(fontSize: 11)),
                          backgroundColor: Colors.white,
                          side: const BorderSide(color: Color(0xFFC2D5C4)),
                          visualDensity: VisualDensity.compact,
                        ))
                    .toList(),
              ),
            ],
          ],

          const SizedBox(height: 24),

          // Botón principal
          SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton(
              onPressed: _enviando ? null : _enviarDireccion,
              style: ElevatedButton.styleFrom(
                backgroundColor: _verdePrincipal,
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(26),
                ),
              ),
              child: _enviando
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                    )
                  : Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.send_rounded, size: 18),
                        const SizedBox(width: 8),
                        Text(
                          _modalidadMultipla
                              ? 'Enviar ${_generarEstructuraDirecciones().length} direcciones'
                              : 'Enviar dirección',
                          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
            ),
          ),
        ],
      ),
    ),
  );
}

  Widget _buildUnidadesEditor() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFC2D5C4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _condominio
                ? 'Departamentos/unidades del condominio:'
                : 'Cada casa se guardará como una dirección individual:',
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: _verdePrincipal),
          ),
          const SizedBox(height: 8),
          ..._unidades.asMap().entries.map((entry) {
            final index = entry.key;
            final u = entry.value;
            final error = _errorDeUnidad(u);

            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: _miniInput(
                          hint: _condominio ? 'Bloque' : 'Casa',
                          controller: u.bloque,
                        ),
                      ),
                      const SizedBox(width: 4),
                      if (_condominio) ...[
                        Expanded(
                          child: _miniInput(hint: 'Piso', controller: u.piso),
                        ),
                        const SizedBox(width: 4),
                      ],
                      Expanded(
                        child: _miniInput(
                          hint: _condominio ? 'Apto' : 'N° Casa',
                          controller: u.aptoCasa,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: _miniInput(hint: 'Extra', controller: u.extra),
                      ),
                      const SizedBox(width: 4),
                      if (index == _unidades.length - 1)
                        IconButton(
                          visualDensity: VisualDensity.compact,
                          icon: const Icon(Icons.add_circle, color: _verdePrincipal, size: 22),
                          onPressed: _agregarUnidad,
                        )
                      else
                        IconButton(
                          visualDensity: VisualDensity.compact,
                          icon: const Icon(Icons.remove_circle, color: Colors.redAccent, size: 22),
                          onPressed: () => _quitarUnidad(index),
                        ),
                    ],
                  ),
                  if (error != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 2, left: 4),
                      child: Text(
                        error,
                        style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.red.shade700),
                      ),
                    ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _miniInput({required String hint, required TextEditingController controller}) {
    return TextField(
      controller: controller,
      onChanged: (_) => setState(() {}),
      style: const TextStyle(fontSize: 12),
      decoration: InputDecoration(
        hintText: hint,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        filled: true,
        fillColor: const Color(0xFFF7FBF7),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }
}