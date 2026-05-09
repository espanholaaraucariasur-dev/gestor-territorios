import 'dart:convert';
import 'package:http/http.dart' as http;

/// Servicio de traducción usando LibreTranslate API pública.
/// Gratis, sin API key, sin registro.
/// Límite: ~80 req/hora en la API pública — suficiente para 40 personas.
/// 
/// Traduce solo contenido dinámico: anuncios, notificaciones, campañas.
/// Los strings de la UI se manejan por app_translations.dart.
class TranslationService {
  // Servidores públicos de LibreTranslate (fallback automático)
  static const List<String> _servers = [
    'https://libretranslate.com',
    'https://translate.terraprint.co',
    'https://lt.vern.cc',
  ];

  /// Traduce texto de ES a PT-BR.
  /// Retorna el texto original si falla.
  static Future<String> traducirEsPt(String texto) async {
    if (texto.trim().isEmpty) return texto;

    for (final server in _servers) {
      try {
        final response = await http.post(
          Uri.parse('$server/translate'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'q': texto,
            'source': 'es',
            'target': 'pt',
            'format': 'text',
          }),
        ).timeout(const Duration(seconds: 6));

        if (response.statusCode == 200) {
          final data = jsonDecode(response.body) as Map<String, dynamic>;
          final traduccion = data['translatedText'] as String?;
          if (traduccion != null && traduccion.isNotEmpty) {
            return traduccion;
          }
        }
      } catch (_) {
        // Intentar siguiente servidor
        continue;
      }
    }
    // Si todos fallan, retornar original
    return texto;
  }

  /// Traduce en ambos idiomas si se necesita.
  static Future<Map<String, String>> traducirBilingue(String textoEs) async {
    final textoPt = await traducirEsPt(textoEs);
    return {'es': textoEs, 'pt': textoPt};
  }
}
