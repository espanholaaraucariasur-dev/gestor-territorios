import 'dart:convert';
import 'package:http/http.dart' as http;

/// Servicio de traducción ES→PT usando LibreTranslate.
/// Múltiples servidores públicos con fallback automático.
/// Funciona desde dispositivos móviles (no desde servidores).
class TranslationService {
  static const List<String> _servers = [
    'https://libretranslate.com',
    'https://translate.argosopentech.com',
    'https://libretranslate.de',
    'https://translate.terraprint.co',
    'https://lt.vern.cc',
  ];

  /// Traduce texto de ES a PT-BR.
  /// Retorna el texto original si todos los servidores fallan.
  static Future<String> traducirEsPt(String texto) async {
    if (texto.trim().isEmpty) return texto;

    for (final server in _servers) {
      try {
        final response = await http.post(
          Uri.parse('$server/translate'),
          headers: {
            'Content-Type': 'application/json',
            'Accept': 'application/json',
          },
          body: jsonEncode({
            'q': texto,
            'source': 'es',
            'target': 'pt',
            'format': 'text',
          }),
        ).timeout(const Duration(seconds: 8));

        if (response.statusCode == 200) {
          final data = jsonDecode(response.body) as Map<String, dynamic>;
          final traduccion = data['translatedText'] as String?;
          if (traduccion != null && traduccion.isNotEmpty && traduccion != texto) {
            return traduccion;
          }
        }
      } catch (_) {
        continue;
      }
    }
    return texto; // Fallback: texto original
  }

  static Future<Map<String, String>> traducirBilingue(String textoEs) async {
    final textoPt = await traducirEsPt(textoEs);
    return {'es': textoEs, 'pt': textoPt};
  }
}
