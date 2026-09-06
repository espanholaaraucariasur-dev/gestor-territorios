import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

/// Clase auxiliar para gestionar el estado de cada fila de unidad/casa
class _UnidadItem {
  final TextEditingController casaCtrl = TextEditingController();
  final TextEditingController extraCtrl = TextEditingController();

  bool get vacia => casaCtrl.text.trim().isEmpty && extraCtrl.text.trim().isEmpty;

  String get textoCompuesto {
    final c = casaCtrl.text.trim();
    final e = extraCtrl.text.trim();
    if (c.isEmpty && e.isEmpty) return '';
    if (c.isNotEmpty && e.isNotEmpty) return '$c ($e)';
    return c.isNotEmpty ? c : e;
  }

  void dispose() {
    casaCtrl.dispose();
    extraCtrl.dispose();
  }
}

class EnviarDireccionCard extends StatefulWidget {
  final String usuarioNombre;
  final String? usuarioEmail;
  final VoidCallback? onEnviado;

  const EnviarDireccionCard({
    super.key,
    required this.usuarioNombre,
    this.usuarioEmail,
    this.onEnviado,
  });

  @override
  State<EnviarDireccionCard> createState() => _EnviarDireccionCardState();
}

class _EnviarDireccionCardState extends State<EnviarDireccionCard> {
  final TextEditingController _direccionController = TextEditingController();
  final TextEditingController _complementoController = TextEditingController();

  bool _variasCasas = false;
  bool _condominio = false;
  bool _isSending = false;

  final List<_UnidadItem> _unidades = [];

  bool get _modalidadMultiples => _variasCasas || _condominio;

  @override
  void dispose() {
    _direccionController.dispose();
    _complementoController.dispose();
    for (final u in _unidades) {
      u.dispose();
    }
    super.dispose();
  }

  void _onToggleVariasCasas(bool? value) {
    setState(() {
      _variasCasas = value ?? false;
      if (_variasCasas) {
        _condominio = false;
        if (_unidades.isEmpty) _unidades.add(_UnidadItem());
      } else if (!_condominio) {
        _limpiarUnidades();
      }
    });
  }

  void _onToggleCondominio(bool? value) {
    setState(() {
      _condominio = value ?? false;
      if (_condominio) {
        _variasCasas = false;
        if (_unidades.isEmpty) _unidades.add(_UnidadItem());
      } else if (!_variasCasas) {
        _limpiarUnidades();
      }
    });
  }

  void _limpiarUnidades() {
    for (final u in _unidades) {
      u.dispose();
    }
    _unidades.clear();
  }

  void _agregarUnidad() {
    setState(() {
      _unidades.add(_UnidadItem());
    });
  }

  void _removerUnidad(int index) {
    if (_unidades.length <= 1) return;
    setState(() {
      _unidades[index].dispose();
      _unidades.removeAt(index);
    });
  }

  String _construirTextoBase() {
    return _direccionController.text.trim();
  }

  List<Map<String, String>> _generarDirecciones() {
    final base = _construirTextoBase();
    final complementoPrincipal = _complementoController.text.trim();
    if (base.isEmpty && complementoPrincipal.isEmpty) return [];

    if (!_modalidadMultiples) {
      return [
        {
          'texto': base,
          'tipo': 'normal',
          'complemento': complementoPrincipal,
        }
      ];
    }

    final resultado = <Map<String, String>>[];
    final unidadesValidas = _unidades.where((u) => !u.vacia).toList();

    if (unidadesValidas.isEmpty) {
      resultado.add({
        'texto': base,
        'tipo': _condominio ? 'condominio' : 'multiples_casas',
        'complemento': complementoPrincipal,
      });
    } else {
      for (final u in unidadesValidas) {
        final compUnidad = u.textoCompuesto;
        final complementoFinal = [
          if (complementoPrincipal.isNotEmpty) complementoPrincipal,
          if (compUnidad.isNotEmpty) compUnidad,
        ].join(' - ');

        resultado.add({
          'texto': complementoFinal.isEmpty ? base : '$base, $compUnidad',
          'tipo': _condominio ? 'condominio' : 'multiples_casas',
          'complemento': complementoFinal,
        });
      }
    }

    return resultado;
  }

  Future<void> _enviarDirecciones() async {
    final direcciones = _generarDirecciones();
    if (direcciones.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Por favor, ingresa una dirección válida.')),
      );
      return;
    }

    setState(() => _isSending = true);

    try {
      final batch = FirebaseFirestore.instance.batch();
      final collection = FirebaseFirestore.instance.collection('direcciones');

      for (final dir in direcciones) {
        final docRef = collection.doc();
        batch.set(docRef, {
          'direccion': dir['texto'],
          'complemento': dir['complemento'],
          'tipo_entrega': dir['tipo'],
          'enviado_por': widget.usuarioNombre,
          'enviado_por_email': widget.usuarioEmail ?? '',
          'estado': 'PENDIENTE_AUDITORIA',
          'timestamp': FieldValue.serverTimestamp(),
        });
      }

      await batch.commit();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${direcciones.length} dirección(es) enviada(s) correctamente.')),
        );
        _direccionController.clear();
        _complementoController.clear();
        setState(() {
          _variasCasas = false;
          _condominio = false;
          _limpiarUnidades();
        });
        widget.onEnviado?.call();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al enviar: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
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
            if (!_modalidadMultiples) ...[
              TextField(
                controller: _complementoController,
                decoration: InputDecoration(
                  hintText: 'Complemento (opcional). Ej: casa 5, apto 3',
                  filled: true,
                  fillColor: Colors.grey.shade100,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
              const SizedBox(height: 12),
            ],
            _buildModalidadSelector(),
            if (_modalidadMultiples) ...[
              const SizedBox(height: 12),
              _buildUnidadesEditor(),
            ],
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _isSending ? null : _enviarDirecciones,
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              child: _isSending
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Enviar para Auditoría', style: TextStyle(fontSize: 16)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildModalidadSelector() {
    return Row(
      children: [
        Expanded(
          child: CheckboxListTile(
            title: const Text('Varias casas', style: TextStyle(fontSize: 13)),
            value: _variasCasas,
            onChanged: _onToggleVariasCasas,
            dense: true,
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
          ),
        ),
        Expanded(
          child: CheckboxListTile(
            title: const Text('Condominio', style: TextStyle(fontSize: 13)),
            value: _condominio,
            onChanged: _onToggleCondominio,
            dense: true,
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
          ),
        ),
      ],
    );
  }

  Widget _buildUnidadesEditor() {
    final esCondo = _condominio;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          esCondo ? 'Unidades / Departamentos:' : 'Casas en el terreno:',
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
        ),
        const SizedBox(height: 8),
        ListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: _unidades.length,
          itemBuilder: (context, index) {
            final item = _unidades[index];
            return Padding(
              padding: const EdgeInsets.only(bottom: 8.0),
              child: Row(
                children: [
                  Expanded(
                    flex: 2,
                    child: TextField(
                      controller: item.casaCtrl,
                      decoration: InputDecoration(
                        hintText: esCondo ? 'Bloque/Apto' : 'Casa N° (ej: Casa 1)',
                        isDense: true,
                        filled: true,
                        fillColor: Colors.grey.shade100,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(6),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    flex: 3,
                    child: TextField(
                      controller: item.extraCtrl,
                      decoration: InputDecoration(
                        hintText: 'Extra / Obs (opcional)',
                        isDense: true,
                        filled: true,
                        fillColor: Colors.grey.shade100,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(6),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.remove_circle_outline, color: Colors.redAccent),
                    onPressed: _unidades.length > 1 ? () => _removerUnidad(index) : null,
                  ),
                ],
              ),
            );
          },
        ),
        TextButton.icon(
          onPressed: _agregarUnidad,
          icon: const Icon(Icons.add),
          label: Text(esCondo ? 'Agregar departamento' : 'Agregar casa'),
        ),
      ],
    );
  }
}