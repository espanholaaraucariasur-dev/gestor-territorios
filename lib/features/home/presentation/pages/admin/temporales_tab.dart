import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class TemporalesTab extends StatefulWidget {
  final Map<String, dynamic> usuarioData;

  const TemporalesTab({
    super.key,
    required this.usuarioData,
  });

  @override
  State<TemporalesTab> createState() => _TemporalesTabState();
}

class _TemporalesTabState extends State<TemporalesTab> {
  Future<void> _mostrarDialogoCrearTarjetaTemporal(
      List<DocumentSnapshot> direcciones, String nombreTerritorio) async {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Creación de tarjeta temporal en desarrollo para: $nombreTerritorio'),
        backgroundColor: Colors.blue,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Slider para límite de direcciones
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.05),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(
                      Icons.tune,
                      color: Color(0xFF4A148C),
                    ),
                    const SizedBox(width: 8),
                    const Text(
                      'Límite de direcciones por tarjeta',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF263238),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                StatefulBuilder(
                  builder: (context, setState) {
                    double limiteDirecciones = 10.0;
                    return Column(
                      children: [
                        Slider(
                          value: limiteDirecciones,
                          min: 5,
                          max: 30,
                          divisions: 25,
                          activeColor: const Color(0xFF4A148C),
                          label: '${limiteDirecciones.toInt()}',
                          onChanged: (value) {
                            setState(() {
                              limiteDirecciones = value;
                            });
                          },
                        ),
                        Center(
                          child: Text(
                            '${limiteDirecciones.toInt()} direcciones',
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF4A148C),
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // Query automática de direcciones temporales
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('direcciones_globales')
                  .where('predicado', isEqualTo: true)
                  .snapshots(),
              builder: (context, snapshot) {
                if (!snapshot.hasData) {
                  return const Center(
                    child: CircularProgressIndicator(),
                  );
                }

                final direcciones = snapshot.data!.docs;

                // Agrupar por territorio_id
                final Map<String, List<DocumentSnapshot>>
                    direccionesPorTerritorio = {};
                for (final doc in direcciones) {
                  final data = doc.data() as Map<String, dynamic>;
                  final territorioId =
                      data['territorio_id']?.toString() ??
                          'sin_territorio';
                  direccionesPorTerritorio
                      .putIfAbsent(territorioId, () => [])
                      .add(doc);
                }

                if (direccionesPorTerritorio.isEmpty) {
                  return const Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.inbox_outlined,
                          size: 64,
                          color: Colors.grey,
                        ),
                        SizedBox(height: 16),
                        Text(
                          'No hay direcciones temporales',
                          style: TextStyle(
                            fontSize: 16,
                            color: Colors.grey,
                          ),
                        ),
                      ],
                    ),
                  );
                }

                return ListView.builder(
                  padding: const EdgeInsets.only(top: 8),
                  itemCount: direccionesPorTerritorio.length,
                  itemBuilder: (context, index) {
                    final territorioId = direccionesPorTerritorio
                        .keys
                        .elementAt(index);
                    final direccionesTerritorio =
                        direccionesPorTerritorio[territorioId]!;

                    // Determinar nombre del territorio
                    String nombreTerritorio =
                        'Territorio desconocido';
                    if (territorioId != 'sin_territorio') {
                      nombreTerritorio =
                          'Territorio $territorioId';
                    } else {
                      nombreTerritorio = 'Mixta';
                    }

                    return Card(
                      margin: const EdgeInsets.only(bottom: 12),
                      elevation: 2,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment:
                              CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Container(
                                  width: 36,
                                  height: 36,
                                  decoration: BoxDecoration(
                                    color: Colors.purple.shade50,
                                    borderRadius:
                                        BorderRadius.circular(8),
                                  ),
                                  child: const Icon(
                                    Icons.timer,
                                    color: Color(0xFF4A148C),
                                    size: 20,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        nombreTerritorio,
                                        style: const TextStyle(
                                          fontWeight:
                                              FontWeight.bold,
                                          fontSize: 15,
                                          color: Color(
                                            0xFF263238,
                                          ),
                                        ),
                                      ),
                                      Text(
                                        '${direccionesTerritorio.length} direcciones disponibles',
                                        style: const TextStyle(
                                          fontSize: 12,
                                          color: Colors.grey,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                ElevatedButton(
                                  onPressed: () =>
                                      _mostrarDialogoCrearTarjetaTemporal(
                                    direccionesTerritorio,
                                    nombreTerritorio,
                                  ),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: const Color(
                                      0xFF4A148C,
                                    ),
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets
                                        .symmetric(
                                      horizontal: 16,
                                      vertical: 8,
                                    ),
                                  ),
                                  child: const Text(
                                    'Crear Tarjeta',
                                    style: TextStyle(
                                      fontSize: 12,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            // Mostrar algunas direcciones de ejemplo
                            Container(
                              height: 60,
                              child: ListView.builder(
                                scrollDirection: Axis.horizontal,
                                itemCount:
                                    direccionesTerritorio.length >
                                            3
                                        ? 3
                                        : direccionesTerritorio
                                            .length,
                                itemBuilder: (context, dirIndex) {
                                  final direccion =
                                      direccionesTerritorio[
                                          dirIndex];
                                  final data = direccion.data()
                                      as Map<String, dynamic>;
                                  final calle = data['calle'] ??
                                      'Sin nombre';

                                  return Container(
                                    width: 120,
                                    margin: const EdgeInsets.only(
                                      right: 8,
                                    ),
                                    padding: const EdgeInsets.all(
                                      8,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Colors.grey.shade100,
                                      borderRadius:
                                          BorderRadius.circular(
                                        6,
                                      ),
                                    ),
                                    child: Text(
                                      calle,
                                      style: const TextStyle(
                                        fontSize: 10,
                                        color: Colors.black87,
                                      ),
                                      overflow:
                                          TextOverflow.ellipsis,
                                      maxLines: 2,
                                    ),
                                  );
                                },
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
