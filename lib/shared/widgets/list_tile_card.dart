import 'package:flutter/material.dart';

/// Widget ListTile card reutilizable con estilo moderno y consistente.
///
/// [indice] se usa para asignar un color de borde izquierdo único por tarjeta.
/// [icono] es el icono a mostrar a la izquierda.
/// [titulo] es el texto principal (style: color: Color(0xFF1F2937)).
/// [subtitulo] es el texto secundario opcional.
/// [trailing] es el widget de arrastrar suelto a la derecha.
/// [onTap] es el callback de pulsación.
/// [colorIcono] color del icono (si se quiere sobreescribir el default).
Widget listTileCard({
  required int indice,
  required IconData icono,
  required String titulo,
  String? subtitulo,
  Widget? trailing,
  VoidCallback? onTap,
  Color? colorIcono,
}) {
  final List<Color> paleta = [
    Color(0xFF6B21A8), // Violeta
    Color(0xFF15803D), // Verde
    Color(0xFF1D4ED8), // Azul
    Color(0xFFEA580C), // Naranja
    Color(0xFFBE185D), // Rosa
    Color(0xFF0E7490), // Cian
  ];
  final Color colorBorde = paleta[indice % paleta.length];
  final Color colorIconoUsado = colorIcono ?? colorBorde;

  return Card(
    margin: const EdgeInsets.only(bottom: 12),
    elevation: 1,
    shadowColor: Colors.black.withValues(alpha: 0.08),
    color: Colors.white,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(14),
    ),
    child: Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        border: Border(
          left: BorderSide(color: colorBorde, width: 6),
        ),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.all(14),
        leading: Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: colorIconoUsado.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icono, color: colorIconoUsado, size: 22),
        ),
        title: Text(
          titulo,
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 15,
            color: Color(0xFF1F2937),
          ),
        ),
        subtitle: subtitulo != null
            ? Text(
                subtitulo,
                style: TextStyle(
                  fontSize: 11,
                  color: Colors.grey.shade600,
                ),
              )
            : null,
        trailing: trailing,
        onTap: onTap,
      ),
    ),
  );
}