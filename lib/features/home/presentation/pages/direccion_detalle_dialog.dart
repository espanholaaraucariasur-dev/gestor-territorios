import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class DireccionDetalleDialog {
  static void mostrar(
    BuildContext context,
    QueryDocumentSnapshot dirDoc,
    bool campanaEspecialActiva,
  ) {
    final data = dirDoc.data() as Map<String, dynamic>;
    final calle = data['calle'] as String? ?? '';
    final complemento = data['complemento'] as String? ?? 'No especificado';
    final informacion = data['informacion'] as String? ?? 'No especificada';
    final barrio = data['barrio'] as String? ?? 'Sin barrio';
    final estadoPredicacion = data['estado_predicacion'] as String? ?? 'pendiente';
    final predicado = data['predicado'] == true;
    final noPredicado = data['no_predicado'] == true;
    final esHispano = data.containsKey('es_hispano') ? data['es_hispano'] as bool : true;
    final entregoInvitacion = data['entrego_invitacion'] == true;
    final campanaEspecial = data['campana_especial'] == true;

    // Campo dinámico de campaña
    final campanaInvitacionEntregada = data.keys
        .where((k) => k.startsWith('campana_invitacion_') && data[k] == true)
        .isNotEmpty;
    final nombresCampanas = data.keys
        .where((k) => k.startsWith('campana_invitacion_') && data[k] == true)
        .map((k) => k.replaceFirst('campana_invitacion_', ''))
        .join(', ');

    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Icon(Icons.location_on, size: 28, color: Colors.blue),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.grey),
                    onPressed: () => Navigator.pop(ctx),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              infoCard('📍 Calle', calle, Colors.blue, const Color(0xFFE3F2FD)),
              const SizedBox(height: 12),
              infoCard('🏠 Complemento', complemento, Colors.green, const Color(0xFFE8F5E9)),
              const SizedBox(height: 12),
              infoCard('🏘️ Barrio', barrio, Colors.orange, const Color(0xFFFFF3E0)),
              const SizedBox(height: 12),
              infoCard('📝 Información', informacion, Colors.purple, const Color(0xFFE1BEE7)),
              const SizedBox(height: 12),
              infoCard('📌 Estado', estadoPredicacion, Colors.teal, const Color(0xFFB2DFDB)),
              const SizedBox(height: 10),
              Row(children: [
                chip('Predicado', predicado),
                const SizedBox(width: 8),
                chip('No predicado', noPredicado),
              ]),
              const SizedBox(height: 10),
              Row(children: [
                chip(esHispano ? 'Hispano' : 'No hispano', esHispano),
                const SizedBox(width: 8),
                chip('Entregó invitación', entregoInvitacion),
              ]),
              if (campanaEspecialActiva || campanaInvitacionEntregada) ...[
                const SizedBox(height: 10),
                chip(
                  campanaInvitacionEntregada
                      ? '✅ Invitación: $nombresCampanas'
                      : 'Campaña: pendiente',
                  campanaInvitacionEntregada || campanaEspecial,
                ),
              ],
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                height: 45,
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(ctx),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF1B5E20),
                    foregroundColor: Colors.white,
                  ),
                  child: const Text('Entendido',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static Widget infoCard(
    String titulo,
    String valor,
    Color iconColor,
    Color backgroundColor,
  ) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: iconColor.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(titulo,
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: iconColor)),
          const SizedBox(height: 6),
          Text(valor,
              style: const TextStyle(fontSize: 14, color: Color(0xFF263238))),
        ],
      ),
    );
  }

  static Widget chip(String texto, bool activo) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: activo ? Colors.green.shade100 : Colors.grey.shade200,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Text(
        texto,
        style: TextStyle(
          fontSize: 12,
          color: activo ? Colors.green.shade900 : Colors.black54,
        ),
      ),
    );
  }
}
