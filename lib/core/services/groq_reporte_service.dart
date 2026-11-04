import 'dart:convert';
import 'package:http/http.dart' as http;
import '../config/app_secrets.dart';

/// Redacta informes ejecutivos de estadísticas usando Groq.
///
/// Sigue el mismo patrón que [GroqTerritoryService]: usa la clave de
/// [AppSecrets.groqSyncKey] (o --dart-define=GROQ_API_KEY), el endpoint de
/// chat de Groq y recorta el prompt para no exceder el TPM del plan free.
/// A diferencia de los servicios territoriales, pide una respuesta en texto
/// (narrativa), no en JSON.
class GroqReporteService {
  static const String _apiKey =
      String.fromEnvironment('GROQ_API_KEY', defaultValue: AppSecrets.groqSyncKey);
  static const String _baseUrl =
      'https://api.groq.com/openai/v1/chat/completions';
  static const String _model = 'qwen/qwen3.8-27b';

  /// Tope de seguridad para el tamaño del prompt (evita 413 de Groq).
  static const int _maxUserPromptChars = 4000;
  static const int _maxOutputTokens = 700;

  static Uri _url() => Uri.parse(_baseUrl);

  static Map<String, String> _headers() =>
      {'Content-Type': 'application/json', 'Authorization': 'Bearer $_apiKey'};

  static void _checkKey() {
    if (_apiKey.isEmpty) {
      throw Exception(
          'API Key no configurada. Configura groqSyncKey en app_secrets.dart o pasa --dart-define=GROQ_API_KEY=gsk_... al compilar.');
    }
  }

  static String _recortar(String texto, int max) {
    if (texto.length <= max) return texto;
    return texto.substring(0, max);
  }

  /// Genera un informe ejecutivo en texto (narrativa profesional y corporativa)
  /// a partir de un resumen numérico de estadísticas territoriales.
  ///
  /// Retorna el texto del informe. Si la API falla, lanza la excepción para
  /// que el llamador decida cómo degradar (p. ej. usar un resumen local).
  static Future<String> generarInformeEjecutivo({
    required Map<String, dynamic> resumen,
  }) async {
    _checkKey();

    final systemPrompt = '''
Eres un redactor senior de informes ejecutivos para una congregación cristiana.
Redacta UN informe profesional, corporativo y bien estructurado en ESPAÑOL,
basado en los datos que recibas.

Reglas:
1. Responde SOLO con el texto del informe, sin títulos de sección en mayúsculas largas, sin viñetas con guiones ni emojis.
2. Extensión: 3 a 5 párrafos breves; un máximo de 220 palabras. Sé conciso.
3. Debe incluir, en prosa natural:
   - El cierre del período (direcciones al final del período) y el piso inicial (direcciones de inicio del período).
   - La cobertura de predicación: direcciones completadas y direcciones pendientes sobre el total de direcciones, usando el porcentaje de cobertura provisto.
   - El crecimiento del período en porcentaje calculado como (cierre del período - piso inicial) / piso inicial * 100, y el desglose: direcciones nuevas, restauradas y removidas.
   - Interpretación del crecimiento (¿positivo, estable o en contracción?) con tono constructivo y de servicio.
   - Mención del trabajo pendiente a partir de las direcciones pendientes.
   - Un cierre animador y profesional orientado a la predicación.
4. Usa cifras exactas proporcionadas. No inventes datos.
5. El tono debe ser de informe ejecutivo: claro, sobrio, positivo y útil para la toma de decisiones.
''';

    final userPrompt =
        'Resumen de estadísticas del período:\n${_recortar(jsonEncode(resumen), _maxUserPromptChars)}';

    final response = await http.post(
      _url(),
      headers: _headers(),
      body: jsonEncode({
        "model": _model,
        "messages": [
          {"role": "system", "content": systemPrompt},
          {"role": "user", "content": userPrompt}
        ],
        "temperature": 0.5,
        "max_tokens": _maxOutputTokens,
      }),
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      String content =
          data['choices'][0]['message']['content'] as String? ?? '';
      content = content.trim().replaceAll('\r\n', '\n');
      if (content.isEmpty) {
        throw Exception('La IA no devolvió contenido.');
      }
      return content;
    } else {
      throw Exception('Error generando informe con Groq: ${response.body}');
    }
  }
}