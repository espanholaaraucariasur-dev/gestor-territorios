import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'dart:convert';

void startCsvUpload(
  BuildContext context,
  Future<void> Function(String) onFileLoaded,
) async {
  void alerta(String msg) {
    if (context.mounted) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(
          content: Text(msg),
          backgroundColor: Colors.red,
        ));
    }
  }

  PlatformFile? file;
  try {
    file = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: ['csv', 'txt'],
    );
  } catch (e) {
    debugPrint('Error al abrir archivo: $e');
    alerta('Error al abrir el archivo: $e');
    return;
  }

  if (file == null) return;

  try {
    final bytes = await file.readAsBytes();
    if (bytes.isEmpty) {
      alerta('No se pudo leer el contenido del archivo.');
      return;
    }

    // Intentar UTF-8 primero, si falla usar Latin-1
    String contenido;
    try {
      contenido = utf8.decode(bytes);
    } catch (_) {
      contenido = latin1.decode(bytes);
    }

    await onFileLoaded(contenido);
  } catch (e) {
    debugPrint('Error al leer archivo: $e');
    alerta('Error al leer el archivo: $e');
  }
}
