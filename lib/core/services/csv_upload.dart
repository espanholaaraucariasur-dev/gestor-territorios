import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';

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

  String contenido;
  try {
    final bytes = result.files.single.bytes;
    if (bytes == null) return;
    contenido = String.fromCharCodes(bytes);
    onFileLoaded(contenido);
  } catch (e) {
    debugPrint('Error al leer archivo: $e');
  }
}
