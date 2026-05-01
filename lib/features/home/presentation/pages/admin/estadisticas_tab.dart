import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class EstadisticasTab extends StatefulWidget {
  final Map<String, dynamic> usuarioData;

  const EstadisticasTab({
    super.key,
    required this.usuarioData,
  });

  @override
  State<EstadisticasTab> createState() => _EstadisticasTabState();
}

class _EstadisticasTabState extends State<EstadisticasTab> {
  Widget _statCard(String title, int value, IconData icon) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          Icon(icon, size: 32, color: const Color(0xFF4A148C)),
          const SizedBox(height: 8),
          Text(
            value.toString(),
            style: const TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: Color(0xFF4A148C),
            ),
          ),
          Text(title, style: TextStyle(fontSize: 12, color: Colors.grey[600])),
        ],
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
          const Text(
            'Estadísticas',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Color(0xFF4A148C),
            ),
          ),
          const SizedBox(height: 16),
          StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance
                .collection('territorios')
                .snapshots(),
            builder: (context, snapshot) {
              if (!snapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }

              final territorios = snapshot.data!.docs;
              final totalTerritorios = territorios.length;
              final territoriosDisponibles = territorios.where((doc) {
                final data = doc.data() as Map<String, dynamic>;
                return data['disponible_para_publicadores'] == true;
              }).length;
              final territoriosEnviados = territorios.where((doc) {
                final data = doc.data() as Map<String, dynamic>;
                return data['enviado_a'] != null;
              }).length;

              return GridView.count(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                crossAxisCount: 2,
                childAspectRatio: 1.5,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
                children: [
                  _statCard('Total Territorios', totalTerritorios, Icons.map),
                  _statCard(
                      'Disponibles', territoriosDisponibles, Icons.lock_open),
                  _statCard('Enviados', territoriosEnviados, Icons.send),
                  _statCard('Libres', totalTerritorios - territoriosEnviados,
                      Icons.lock),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}
