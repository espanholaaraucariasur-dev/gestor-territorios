import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

/// Mixin para envíos programados de tarjetas
mixin EnvioProgramadoMixin<T extends StatefulWidget> on State<T> {
  String get usuarioEmail;
  Map<String, dynamic> get usuarioData;

  void _procesarEnviosProgramados() async {
    final now = DateTime.now();
    try {
      final queryTerritorios = await FirebaseFirestore.instance
          .collection('territorios')
          .where(
            'programado_para',
            isLessThanOrEqualTo: Timestamp.fromDate(now),
          )
          .where('estatus_envio', isEqualTo: 'programado')
          .get();
      final queryTarjetas = await FirebaseFirestore.instance
          .collectionGroup('tarjetas')
          .where(
            'programado_para',
            isLessThanOrEqualTo: Timestamp.fromDate(now),
          )
          .where('estatus_envio', isEqualTo: 'programado')
          .get();

      final batch = FirebaseFirestore.instance.batch();
      for (final doc in queryTerritorios.docs) {
        final docData = doc.data();
        batch.update(doc.reference, {
          'estatus_envio': 'enviado',
          'enviado_on': FieldValue.serverTimestamp(),
          'enviado_a': docData.containsKey('conductor_email')
              ? docData['conductor_email']
              : '',
        });
      }
      for (final doc in queryTarjetas.docs) {
        final docData = doc.data();
        batch.update(doc.reference, {
          'estatus_envio': 'enviado',
          'enviado_on': FieldValue.serverTimestamp(),
          'enviado_a': docData.containsKey('conductor_email')
              ? docData['conductor_email']
              : '',
        });
      }
      bool hasUpdates =
          queryTerritorios.docs.isNotEmpty || queryTarjetas.docs.isNotEmpty;
      if (hasUpdates) {
        await batch.commit();
      }
    } catch (_) {
      // No interrumpir la app si el procesamiento programado falla.
    }
  }

  Future<void> _programarEnvioTarjeta(
    BuildContext context,

  Future<void> _mostrarDialogoProgramarEnvio(
    String terId, {
    String? tarjetaId,
    required String nombre,
    required bool isTarjeta,
  }) async {
    final conductoresSnapshot = await FirebaseFirestore.instance
        .collection('usuarios')
        .where('es_conductor', isEqualTo: true)
        .get();
    final conductores = conductoresSnapshot.docs
        .map((doc) => doc.data()['email'] as String? ?? '')
        .where((email) => email.isNotEmpty)
        .toList();
    if (!mounted) return;
    String selectedConductor = conductores.isNotEmpty ? conductores.first : '';
    DateTime fechaSeleccionada = DateTime.now();

    await showDialog(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setStateDialog) {
            return AlertDialog(
              title: Text(
                isTarjeta
                    ? 'Programar envío de tarjeta'
                    : 'Programar envío de territorio',
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (conductores.isEmpty)
                    const Text(
                      'No hay conductores registrados. Agrega un conductor antes de programar.',
                    )
                  else
                    DropdownButtonFormField<String>(
                      value: selectedConductor,
                      items: conductores
                          .map(
                            (email) => DropdownMenuItem(
                              value: email,
                              child: Text(email),
                            ),
                          )
                          .toList(),
                      onChanged: (value) {
                        if (value != null)
                          setStateDialog(() => selectedConductor = value);
                      },
                      decoration: const InputDecoration(
                        labelText: 'Conductor',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  const SizedBox(height: 12),
                  InkWell(
                    onTap: () async {
                      final picked = await showDatePicker(
                        context: dialogContext,
                        initialDate: fechaSeleccionada,
                        firstDate: DateTime.now().subtract(
                          const Duration(days: 1),
                        ),
                        lastDate: DateTime.now().add(const Duration(days: 365)),
                      );
                      if (picked != null) {
                        setStateDialog(() => fechaSeleccionada = picked);
                      }
                    },
                    child: InputDecorator(
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                        labelText: 'Fecha de envío',
                      ),
                      child: Text(
                        '${fechaSeleccionada.day}/${fechaSeleccionada.month}/${fechaSeleccionada.year}',
                      ),
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text('Cancelar'),
                ),
                ElevatedButton(
                  onPressed: conductores.isEmpty
                      ? null
                      : () async {
                          try {
                            final data = {
                              'programado_para': Timestamp.fromDate(
                                fechaSeleccionada,
                              ),
                              'conductor_email': selectedConductor,
                              'estatus_envio': 'programado',
                              'programado_tipo':
                                  isTarjeta ? 'tarjeta' : 'territorio',
                              'programado_nombre': nombre,
                            };
                            if (isTarjeta) {
                              await FirebaseFirestore.instance
                                  .collection('territorios')
                                  .doc(terId)
                                  .collection('tarjetas')
                                  .doc(tarjetaId)
                                  .set(data, SetOptions(merge: true));
                            } else {
                              await FirebaseFirestore.instance
                                  .collection('territorios')
                                  .doc(terId)
                                  .set(data, SetOptions(merge: true));
                            }
                            if (!mounted) return;
                            Navigator.pop(dialogContext);
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  'Programación guardada para $nombre',
                                ),
                                backgroundColor: Colors.green,
                              ),
                            );
                          } catch (e) {
                            if (!mounted) return;
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text('Error al programar envío: $e'),
                                backgroundColor: Colors.redAccent,
                              ),
                            );
                          }
                        },
                  child: const Text('Programar'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  String _formatScheduledDate(String? isoDate) {
    if (isoDate == null) return 'No programado';

    try {
      DateTime dateTime = DateTime.parse(isoDate);
      return '${dateTime.day}/${dateTime.month}/${dateTime.year} ${dateTime.hour.toString().padLeft(2, '0')}:${dateTime.minute.toString().padLeft(2, '0')}';
    } catch (e) {
      return 'Fecha inválida';
    }
  }

  void _cancelarProgramacionEnvio(String terId, String tarjetaId) async {
    try {
      await FirebaseFirestore.instance
          .collection('territorios')
          .doc(terId)
          .collection('tarjetas')
          .doc(tarjetaId)
          .update({'programado': false, 'programado_envio': null});

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('✅ Programación de envío cancelada'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('❌ Error al cancelar programación: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

}
