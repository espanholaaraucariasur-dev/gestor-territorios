import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../../../core/l10n/translation_service.dart';

/// Mixin para editar, eliminar y crear direcciones/tarjetas
mixin EditarDireccionMixin<T extends StatefulWidget> on State<T> {
  String get usuarioEmail;
  Map<String, dynamic> get usuarioData;
  bool get campanaEspecialActiva;

  void _editarDireccion(QueryDocumentSnapshot dirDoc) {
    final data = dirDoc.data() as Map<String, dynamic>;
    final TextEditingController calleCtrl = TextEditingController(
      text: data.containsKey('calle') ? data['calle'] : '',
    );
    final TextEditingController complementoCtrl = TextEditingController(
      text: data.containsKey('complemento') ? data['complemento'] : '',
    );
    final TextEditingController informacionCtrl = TextEditingController(
      text: data.containsKey('informacion') ? data['informacion'] : '',
    );
    bool predicado = data.containsKey('predicado') ? data['predicado'] : false;
    bool noPredicado =
        data.containsKey('no_predicado') ? data['no_predicado'] : false;
    bool noHispano =
        (data.containsKey('es_hispano') ? data['es_hispano'] : true) == false;
    bool entregoInvitacion = data.containsKey('entrego_invitacion')
        ? data['entrego_invitacion']
        : false;
    bool campanaEspecial =
        data.containsKey('campana_especial') ? data['campana_especial'] : false;

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return Dialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.edit_location,
                        size: 40,
                        color: Colors.orange,
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'Editar Dirección',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 20),
                      TextField(
                        controller: calleCtrl,
                        decoration: InputDecoration(
                          hintText: 'Calle',
                          filled: true,
                          fillColor: const Color(0xFFF5F5F5),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: BorderSide.none,
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: const BorderSide(
                              color: Colors.orange,
                              width: 2,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: complementoCtrl,
                        decoration: InputDecoration(
                          hintText: 'Complemento',
                          filled: true,
                          fillColor: const Color(0xFFF5F5F5),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: BorderSide.none,
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: const BorderSide(
                              color: Colors.orange,
                              width: 2,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: informacionCtrl,
                        decoration: InputDecoration(
                          hintText: 'Información',
                          filled: true,
                          fillColor: const Color(0xFFF5F5F5),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: BorderSide.none,
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: const BorderSide(
                              color: Colors.orange,
                              width: 2,
                            ),
                          ),
                        ),
                        maxLines: 2,
                      ),
                      const SizedBox(height: 14),
                      CheckboxListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Se predicó'),
                        value: predicado,
                        activeColor: Colors.green,
                        onChanged: (value) {
                          setDialogState(() {
                            predicado = value ?? false;
                            if (predicado) noPredicado = false;
                          });
                        },
                      ),
                      CheckboxListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('No se predicó'),
                        value: noPredicado,
                        activeColor: Colors.red,
                        onChanged: (value) {
                          setDialogState(() {
                            noPredicado = value ?? false;
                            if (noPredicado) predicado = false;
                          });
                        },
                      ),
                      CheckboxListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('No vive hispanohablante'),
                        value: noHispano,
                        activeColor: Colors.orange,
                        onChanged: (value) =>
                            setDialogState(() => noHispano = value ?? false),
                      ),
                      CheckboxListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Entregó invitación'),
                        value: entregoInvitacion,
                        activeColor: Colors.blue,
                        onChanged: (value) => setDialogState(
                          () => entregoInvitacion = value ?? false,
                        ),
                      ),
                      if (_campanaEspecialActiva)
                        CheckboxListTile(
                          contentPadding: EdgeInsets.zero,
                          title: const Text('Campaña especial activa'),
                          value: campanaEspecial,
                          activeColor: Colors.deepOrange,
                          onChanged: (value) => setDialogState(
                            () => campanaEspecial = value ?? false,
                          ),
                        ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: ElevatedButton(
                              onPressed: () => Navigator.pop(context),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.grey,
                              ),
                              child: const Text('Cancelar'),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: ElevatedButton(
                              onPressed: () async {
                                final estadoPredicacion = predicado
                                    ? 'predicado'
                                    : noPredicado
                                        ? 'no_predicado'
                                        : 'pendiente';
                                await FirebaseFirestore.instance
                                    .collection('direcciones_globales')
                                    .doc(dirDoc.id)
                                    .update({
                                  'calle': calleCtrl.text.trim(),
                                  'complemento': complementoCtrl.text.trim(),
                                  'informacion': informacionCtrl.text.trim(),
                                  'direccion_normalizada': _normalizarDireccion(
                                    '${calleCtrl.text.trim()} ${complementoCtrl.text.trim()}',
                                  ),
                                  'predicado': predicado,
                                  'no_predicado': noPredicado,
                                  'es_hispano': !noHispano,
                                  'entrego_invitacion': entregoInvitacion,
                                  'campana_especial': campanaEspecial,
                                  'estado_predicacion': estadoPredicacion,
                                });
                                if (context.mounted) Navigator.pop(context);
                                if (mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text('✅ Dirección actualizada'),
                                      backgroundColor: Colors.green,
                                    ),
                                  );
                                }
                              },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.orange,
                              ),
                              child: const Text('Guardar'),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  void _eliminarDireccion(String dirId, String terId, String tarjetaId) async {
    bool? confirmar = await showDialog(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('⚠️ Eliminar Dirección'),
        content: const Text(
          '¿Estás completamente seguro de que deseas eliminar esta dirección? Esta acción no se puede deshacer.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text(
              'Cancelar',
              style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text(
              'SÍ, Eliminar',
              style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );

    if (confirmar == true) {
      try {
        await FirebaseFirestore.instance
            .collection('direcciones_globales')
            .doc(dirId)
            .delete();

        DocumentSnapshot snap = await FirebaseFirestore.instance
            .collection('territorios')
            .doc(terId)
            .collection('tarjetas')
            .doc(tarjetaId)
            .get();
        int currentCount = snap.data() != null
            ? (snap.data() as Map)['cantidad_direcciones'] ?? 0
            : 0;

        if (currentCount > 0) {
          await FirebaseFirestore.instance
              .collection('territorios')
              .doc(terId)
              .collection('tarjetas')
              .doc(tarjetaId)
              .update({'cantidad_direcciones': currentCount - 1});
        }

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('✅ Dirección eliminada correctamente'),
              backgroundColor: Colors.green,
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('❌ Error al eliminar: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }

  void _mostrarDialogoCrearTarjeta(BuildContext parentContext, String terId) {
    final ctrl = TextEditingController();
    showDialog(
      context: parentContext,
      builder: (context) {
        return Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          child: Stack(
            children: [
              Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.folder_open, size: 40, color: Colors.blue),
                    const SizedBox(height: 16),
                    const Text(
                      'Crear Nueva Tarjeta',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 20),
                    TextField(
                      controller: ctrl,
                      textAlign: TextAlign.center,
                      decoration: _inputStyleHelper('Ej: A01 - CENTRO 1'),
                    ),
                    const SizedBox(height: 24),
                    SizedBox(
                      width: double.infinity,
                      height: 45,
                      child: ElevatedButton(
                        onPressed: () async {
                          if (ctrl.text.trim().isEmpty) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text(
                                  'Por favor ingresa un nombre para la tarjeta',
                                ),
                              ),
                            );
                            return;
                          }

                          try {
                            String nombreTarjeta = ctrl.text.trim();
                            await FirebaseFirestore.instance
                                .collection('territorios')
                                .doc(terId)
                                .collection('tarjetas')
                                .doc(nombreTarjeta)
                                .set({
                              'nombre': nombreTarjeta,
                              'territorio_id': terId,
                              'estado': 'disponible',
                              'cantidad_direcciones': 0,
                              'barrio': '',
                              'created_at': FieldValue.serverTimestamp(),
                              'bloqueado': true,
                              'disponible_para_publicadores': false,
                              'asignado_a': '',
                              'asignado_en': null,
                            });

                            if (context.mounted) {
                              Navigator.pop(context);
                            }

                            if (parentContext.mounted) {
                              await Future.delayed(
                                const Duration(milliseconds: 500),
                              );
                              ScaffoldMessenger.of(parentContext).showSnackBar(
                                const SnackBar(
                                  content: Text('✅ ¡Tarjeta creada con éxito!'),
                                  backgroundColor: Colors.green,
                                ),
                              );
                            }
                          } catch (e) {
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text('❌ Error al crear tarjeta: $e'),
                                  backgroundColor: Colors.red,
                                ),
                              );
                            }
                          }
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.blue,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: const Text(
                          'Crear Tarjeta',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Positioned(
                top: 0,
                right: 0,
                child: IconButton(
                  icon: const Icon(Icons.close, color: Colors.grey),
                  onPressed: () => Navigator.pop(context),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

}
