import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'dart:convert';
import 'dart:typed_data';

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

  FilePickerResult? result;
  try {
    result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['csv', 'txt'],
      allowMultiple: false,
      withData: true,
      withReadStream: true,
    );
  } catch (e) {
    debugPrint('Error al abrir archivo: $e');
    alerta('Error al abrir el archivo: $e');
    return;
  }

  if (result == null || result.files.isEmpty) return;

  final file = result.files.single;

  try {
    // En web, los bytes vienen con withData: true. Fallback a readStream.
    Uint8List bytes = file.bytes ?? (await _leerStream(file));
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

Future<Uint8List> _leerStream(PlatformFile file) async {
  final stream = file.readStream;
  if (stream == null) return Uint8List(0);
  final bytes = <int>[];
  await for (final chunk in stream) {
    bytes.addAll(chunk);
  }
  return Uint8List.fromList(bytes);
}
