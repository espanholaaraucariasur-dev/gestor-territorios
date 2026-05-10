import 'package:google_generative_ai/google_generative_ai.dart';

/// Servicio Gemini AI para Araucaria Sur.
/// - Traducción ES→PT de alta calidad
/// - Análisis de patrones de predicación
/// Plan Free: 1,500 req/día, 1M tokens/mes — suficiente para 40 usuarios.
class GeminiService {
  static const String _apiKey = 'AIzaSyB-tEoKnO74NI-FiumWLooLoQi_Gf3TrAE';

  static GenerativeModel? _model;

  static GenerativeModel get _instance {
    _model ??= GenerativeModel(
      model: 'gemini-1.5-flash',
      apiKey: _apiKey,
      generationConfig: GenerationConfig(
        temperature: 0.1, // Baja temperatura para traducciones precisas
        maxOutputTokens: 1024,
      ),
    );
    return _model!;
  }

  // ─────────────────────────────────────────────────────────
  // TRADUCCIÓN ES → PT
  // ─────────────────────────────────────────────────────────

  /// Traduce texto de español a portugués brasileño.
  /// Optimizado para textos de congregación y predicación.
  static Future<String> traducirEsPt(String texto) async {
    if (texto.trim().isEmpty) return texto;

    try {
      final prompt = '''Traduce el siguiente texto del español al portugués brasileño.
Contexto: App de gestión territorial para una congregación de Testigos de Jehová hispanohablante en Brasil.
Reglas:
- Traduce solo el texto, sin explicaciones
- Mantén nombres propios (Araucária, Iguaçu, etc.)
- Usa vocabulario de la congregación en portugués
- Si hay términos bíblicos/religiosos, usa los usados por las Testemunhas de Jeová en Brasil

Texto a traducir:
$texto

Traducción:''';

      final response = await _instance.generateContent([
        Content.text(prompt)
      ]);

      final traduccion = response.text?.trim() ?? '';
      if (traduccion.isNotEmpty && traduccion != texto) {
        return traduccion;
      }
      return texto;
    } catch (e) {
      // Fallback silencioso — devuelve original
      return texto;
    }
  }

  // ─────────────────────────────────────────────────────────
  // TRADUCCIÓN BILINGÜE
  // ─────────────────────────────────────────────────────────

  static Future<Map<String, String>> traducirBilingue(String textoEs) async {
    final textoPt = await traducirEsPt(textoEs);
    return {'es': textoEs, 'pt': textoPt};
  }

  // ─────────────────────────────────────────────────────────
  // ANALIZAR CAMPAÑA — sugerencias para el admin
  // ─────────────────────────────────────────────────────────

  /// Genera una descripción de campaña especial de predicación.
  static Future<String> generarDescripcionCampana({
    required String nombre,
    required String idioma,
  }) async {
    try {
      final lang = idioma == 'PT' ? 'portugués brasileño' : 'español';
      final prompt = '''Escribe una breve descripción motivadora (máximo 2 oraciones) 
para una campaña especial de predicación llamada "$nombre" 
para Testigos de Jehová. 
Idioma: $lang
Estilo: cálido, motivador, espiritual.
Solo la descripción, sin título ni explicaciones.''';

      final response = await _instance.generateContent([Content.text(prompt)]);
      return response.text?.trim() ?? '';
    } catch (_) {
      return '';
    }
  }

  // ─────────────────────────────────────────────────────────
  // VERIFICAR CONEXIÓN
  // ─────────────────────────────────────────────────────────

  static Future<bool> estaDisponible() async {
    try {
      final response = await _instance.generateContent([
        Content.text('Responde solo: OK')
      ]);
      return response.text?.contains('OK') == true;
    } catch (_) {
      return false;
    }
  }
}
