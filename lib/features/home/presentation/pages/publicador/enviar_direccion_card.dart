import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../../../core/services/notificacion_service.dart' as notif;

/// Un "complemento" opcional que describe una unidad dentro de un mismo
/// terreno/condominio (p. ej. Bloque 1 / Piso 1 / Apto 3). Cada complemento
/// se convierte en una dirección SEPARADA al enviarse.
class _Unidad {
  final TextEditingController bloque = TextEditingController();
  final TextEditingController piso = TextEditingController();
  final TextEditingController apto = TextEditingController();
  final TextEditingController extra = TextEditingController();

  String get textoCompuesto => [
        if (bloque.text.trim().isNotEmpty) 'blo ${bloque.text.trim()}',
        if (piso.text.trim().isNotEmpty) 'piso ${piso.text.trim()}',
        if (apto.text.trim().isNotEmpty) 'apt ${apto.text.trim()}',
        if (extra.text.trim().isNotEmpty) extra.text.trim(),
      ].join(' ');

  bool get vacia =>
      bloque.text.trim().isEmpty &&
      piso.text.trim().isEmpty &&
      apto.text.trim().isEmpty &&
      extra.text.trim().isEmpty;

  void dispose() {
    bloque.dispose();
    piso.dispose();
    apto.dispose();
    extra.dispose();
  }
}

/// Tarjeta rápida para que un publicador envíe direcciones nuevas a la bandeja
/// del Auditor. Guarda en la colección /sugerencias con estado
/// 'PENDIENTE_AUDITORIA'.
///
/// Soporta una dirección simple o, si se marcan los checkboxes de
/// "varias casas / mismo terreno" o "condominio", permite agregar varias
/// unidades (bloque / piso / apartamento / casa). CADA unidad se guarda como
/// una dirección separada con su propio complemento.
class EnviarDireccionCard extends StatefulWidget {
  final String usuarioEmail;
  final String usuarioNombre; // ✅ NUEVO: nombre para mostrar en notificaciones

  const EnviarDireccionCard({
    Key? key, 
    required this.usuarioEmail,
    required this.usuarioNombre, // ✅ NUEVO
  }) : super(key: key);

  @override
  State<EnviarDireccionCard> createState() => _EnviarDireccionCardState();
}

class _EnviarDireccionCardState extends State<EnviarDireccionCard> {
  final TextEditingController _direccionController = TextEditingController();
  bool _enviando = false;

  // Modos compuestos
  bool _multiplesCasas = false;
  bool _condominio = false;
  final List<_Unidad> _unidades = [
    _Unidad(),
  ];

  bool get _modalidadMultiples =>
      _multiplesCasas || _condominio;

  void _toggleModalidad(String tipo, bool valor) {
    setState(() {
      if (tipo == 'casas') {
        _multiplesCasas = valor;
        if (valor) _condominio = false;
      } else {
        _condominio = valor;
        if (valor) _multiplesCasas = false;
      }
      // Asegurar al menos una línea + una vacía para agregar.
      if (_modalidadMultiples && _unidades.length == 1 && !_unidades.first.vacia) {
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

  String _construirTextoBase() {
    var base = _direccionController.text.trim();
    // Normaliza: se conserva tal cual la base (calle + número).
    return base;
  }

  /// Genera la lista de direcciones a enviar (base + complemento por unidad).
  List<Map<String, String>> _generarDirecciones() {
    final base = _construirTextoBase();
    if (base.isEmpty) return [];

    if (!_modalidadMultiples) {
      return [
        {
          'texto': base,
          'tipo': 'normal',
          'complemento': '',
        }
      ];
    }

    final resultado = <Map<String, String>>[];
    // La primera unidad vacía = la dirección base sola (caso común).
    resultado.add({
      'texto': base,
      'tipo': _condominio ? 'condominio' : 'multiples_casas',
      'complemento': '',
    });
    for (final u in _unidades) {
      if (u.vacia) continue;
      final comp = u.textoCompuesto;
      resultado.add({
        'texto': comp.isEmpty ? base : '$base, $comp',
        'tipo': _condominio ? 'condominio' : 'multiples_casas',
        'complemento': comp,
      });
    }
    return resultado;
  }

  Future<void> _enviarDirecciones() async {
    final direcciones = _generarDirecciones();
    if (direcciones.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Escribe la calle y número de la dirección.'),
              backgroundColor: Colors.orange),
        );
      }
      return;
    }

    setState(() => _enviando = true);

    try {
      final batch = FirebaseFirestore.instance.batch();
      for (final d in direcciones) {
        final ref =
            FirebaseFirestore.instance.collection('sugerencias').doc();
        batch.set(ref, {
          'texto_direccion': d['texto'],
          'complemento': d['complemento'],
          'tipo_entrega': d['tipo'],
          'fecha_ingreso': FieldValue.serverTimestamp(),
          'enviado_por': widget.usuarioEmail,
          'estado': 'PENDIENTE_AUDITORIA',
          'origen': 'APP_PUBLICADOR',
        });
      }
      await batch.commit();

      _direccionController.clear();
      for (final u in _unidades) {
        u.dispose();
      }
      setState(() {
        _multiplesCasas = false;
        _condominio = false;
        _unidades
          ..clear()
          ..add(_Unidad());
      });

      // Notificar al auditor de las nuevas direcciones recibidas.
      try {
        await notif.NotificacionService.enviarAAuditores(
          titulo: direcciones.length == 1
              ? 'Nueva dirección enviada'
              : '${direcciones.length} direcciones enviadas',
          cuerpo: '${widget.usuarioNombre} envió ${direcciones.length} dirección(es): '
              '${_construirTextoBase()}',
          tipo: notif.TipoNotificacion.solicitudDireccion,
          extra: {'origen': 'APP_PUBLICADOR', 'cantidad': direcciones.length},
        );
      } catch (_) {}

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(direcciones.length == 1
                ? '¡Dirección enviada con éxito al Auditor!'
                : '¡${direcciones.length} direcciones enviadas con éxito al Auditor!'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Error al enviar: $e'),
              backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _enviando = false);
    }
  }

  @override
  void dispose() {
    _direccionController.dispose();
    for (final u in _unidades) {
      u.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: const [
                Icon(Icons.add_location_alt_outlined, color: Color(0xFF1B5E20)),
                SizedBox(width: 8),
                Text(
                  'Enviar dirección nueva',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _direccionController,
              decoration: InputDecoration(
                hintText: 'Calle y número (ej: Rua das Flores 123)',
                filled: true,
                fillColor: Colors.grey.shade100,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
            const SizedBox(height: 12),
            _buildModalidadSelector(),
            if (_modalidadMultiples) ...[
              const SizedBox(height: 10),
              _buildUnidadesEditor(),
            ],
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton.icon(
                onPressed: _enviando ? null : _enviarDirecciones,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF1B5E20),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(24)),
                ),
                icon: _enviando
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                            color: Colors.white, strokeWidth: 2),
                      )
                    : const Icon(Icons.send, color: Colors.white),
                label: Text(
                  _enviando
                      ? 'Enviando...'
                      : _modalidadMultiples
                          ? 'Enviar ${_generarDirecciones().length} direcciones'
                          : 'Enviar dirección',
                  style: const TextStyle(
                      color: Colors.white, fontWeight: FontWeight.bold),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildModalidadSelector() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('¿Varias casas en el mismo terreno o un condominio?',
            style: TextStyle(fontSize: 12, color: Colors.grey[700])),
        Row(
          children: [
            Expanded(
              child: CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                controlAffinity: ListTileControlAffinity.leading,
                value: _multiplesCasas,
                activeColor: const Color(0xFF1B5E20),
                onChanged: (v) => _toggleModalidad('casas', v ?? false),
                title: const Text('Varias casas',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
              ),
            ),
            Expanded(
              child: CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                controlAffinity: ListTileControlAffinity.leading,
                value: _condominio,
                activeColor: const Color(0xFF1B5E20),
                onChanged: (v) => _toggleModalidad('condominio', v ?? false),
                title: const Text('Condominio',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
              ),
            ),
          ],
        ),
      ],
    );
  }

  /// Editor de unidades: cada fila tiene 4 apartados (bloque, piso, apt/casa,
  /// extra) y un botón + para agregar otra fila. Cada fila = 1 dirección.
  Widget _buildUnidadesEditor() {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.green.shade50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.green.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _condominio
                ? 'Unidad por apartamento/casa del condominio (bloque, piso, apto):'
                : 'Cada casa del mismo terreno se envía por separado:',
            style: TextStyle(fontSize: 12, color: Colors.green.shade900),
          ),
          const SizedBox(height: 6),
          ..._unidades.asMap().entries.map((entry) {
            final index = entry.key;
            final u = entry.value;
            return Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                children: [
                  Expanded(
                    child: _miniCampo(
                      hint: _condominio ? 'Bloque' : 'Casa',
                      controller: u.bloque,
                    ),
                  ),
                  const SizedBox(width: 4),
                  if (_condominio) ...[
                    Expanded(
                      child: _miniCampo(hint: 'Piso', controller: u.piso),
                    ),
                    const SizedBox(width: 4),
                  ],
                  Expanded(
                    child: _miniCampo(
                      hint: _condominio ? 'Apto' : 'N° casa',
                      controller: u.apto,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: _miniCampo(hint: 'Extra', controller: u.extra),
                  ),
                  const SizedBox(width: 2),
                  // Botón + al final de la última fila, − para las demás.
                  if (index == _unidades.length - 1)
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      icon: const Icon(Icons.add_circle,
                          color: Color(0xFF1B5E20), size: 22),
                      tooltip: 'Agregar más casas/apartamentos',
                      onPressed: _agregarUnidad,
                    )
                  else
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      icon: const Icon(Icons.remove_circle,
                          color: Colors.redAccent, size: 22),
                      tooltip: 'Quitar',
                      onPressed: () => _quitarUnidad(index),
                    ),
                ],
              ),
            );
          }),
          Text(
            'Cada línea se guarda como una dirección aparte. '
            'Ej: $_vistaEjemplo',
            style: TextStyle(fontSize: 10, color: Colors.grey[600]),
          ),
        ],
      ),
    );
  }

  String get _vistaEjemplo {
    final base = _construirTextoBase() == '' ? 'Rua Teste' : _construirTextoBase();
    if (_condominio) {
      return '$base blo 1 piso 1 apt 3, $base blo 1 piso 1 apt 2, '
          '$base blo 1 piso 1 apt 12 → 3 direcciones';
    }
    return '$base casa 1, $base casa 2 → 2 direcciones';
  }

  Widget _miniCampo({
    required String hint,
    required TextEditingController controller,
  }) {
    return TextField(
      controller: controller,
      style: const TextStyle(fontSize: 12),
      decoration: InputDecoration(
        hintText: hint,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(6),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }
}
