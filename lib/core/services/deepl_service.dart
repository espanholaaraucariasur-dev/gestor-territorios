import 'dart:convert';
import 'package:http/http.dart' as http;

/// Servicio DeepL para traducciones dinámicas.
/// Usado para anuncios, notificaciones y contenido generado por usuarios.
/// Plan Free: 500,000 caracteres/mes.
///
/// Para activar: obtener API key en https://www.deepl.com/pro-api
/// y guardar en configuracion/deepl_config en Firestore.
class DeepLService {
  static const String _baseUrl = 'https://api-free.deepl.com/v2/translate';

  /// Traduce texto al idioma destino.
  /// [targetLang]: 'ES' para español, 'PT-BR' para portugués brasileño.
  static Future<String> traducir({
    required String texto,
    required String targetLang,
    String? apiKey,
  }) async {
    if (texto.isEmpty) return texto;
    if (apiKey == null || apiKey.isEmpty) return texto;

    try {
      final response = await http.post(
        Uri.parse(_baseUrl),
        headers: {
          'Authorization': 'DeepL-Auth-Key $apiKey',
          'Content-Type': 'application/x-www-form-urlencoded',
        },
        body: {
          'text': texto,
          'target_lang': targetLang == 'PT' ? 'PT-BR' : targetLang,
        },
      ).timeout(const Duration(seconds: 5));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final translations = data['translations'] as List?;
        if (translations != null && translations.isNotEmpty) {
          return translations.first['text'] as String? ?? texto;
        }
      }
      return texto;
    } catch (_) {
      return texto;
    }
  }

  /// Traduce un texto al idioma actual del usuario.
  static Future<String> traducirParaIdioma({
    required String texto,
    required String idioma,
    required String apiKey,
  }) async {
    if (idioma == 'ES') return texto; // Español es el idioma base
    return traducir(texto: texto, targetLang: idioma, apiKey: apiKey);
  }
}
