import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'dart:convert';

void startCsvUpload(Function(String) onFileLoaded) async {
  FilePickerResult? result;
  try {
    result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['csv'],
      allowMultiple: false,
    );
  } catch (e) {
    debugPrint('Error al abrir archivo: $e');
    return;
  }

  if (result == null) return;

  try {
    final bytes = result.files.single.bytes;
    if (bytes == null) return;

    // ✅ Intentar UTF-8 primero, si falla usar Latin-1
    String contenido;
    try {
      contenido = utf8.decode(bytes);
    } catch (_) {
      contenido = latin1.decode(bytes);
    }

    onFileLoaded(contenido);
  } catch (e) {
    debugPrint('Error al leer archivo: $e');
  }
}
