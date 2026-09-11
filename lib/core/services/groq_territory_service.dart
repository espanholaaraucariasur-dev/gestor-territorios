import 'dart:convert';
import 'package:http/http.dart' as http;
import '../config/app_secrets.dart';

/// Motor de Inteligencia Territorial basado en Groq (OpenAI-compatible).
///
/// - [extraerDireccionesWhatsApp] usa un modelo rápido (qwen) para JSON masivo.
/// - [analizarYPlanificarReorganizacion] y [decidirTarjetaParaDireccion] usan
///   un modelo de razonamiento (gpt-oss-120b) con payload compacto para evitar
///   el error 413 Content Too Large de Groq.
class GroqTerritoryService {
  static const String _apiKey =
      String.fromEnvironment('GROQ_API_KEY', defaultValue: AppSecrets.groqSyncKey);
  static const String _baseUrl =
      'https://api.groq.com/openai/v1/chat/completions';
  static const String _model = 'qwen/qwen3.8-27b';
  static const String _razonamientoModel = 'openai/gpt-oss-120b';

  /// Tope de seguridad para el tamaño del prompt (evita 413 de Groq,
  /// que en el plan free limita los tokens por minuto, TPM ~8K).
  static const int _maxUserPromptChars = 5000;

  /// Máximo de sugerencias/direcciones por llamada para no exceder el TPM.
  static const int _maxSugerenciasPorLlamada = 40;
  static const int _maxTarjetasPorLlamada = 30;
  static const int _maxOutputTokens = 900;

  /// Lote más chico que [_maxSugerenciasPorLlamada] porque la respuesta de
  /// normalización es más verbosa (incluye la dirección completa por ítem).
  static const int _maxDireccionesPorLoteGeocoding = 25;
  static const int _maxOutputTokensGeocoding = 1400;

  /// Expuesto para que el orquestador de backfill sepa en qué lotes dividir
  /// las direcciones sin coordenadas.
  static int get maxDireccionesPorLoteGeocoding =>
      _maxDireccionesPorLoteGeocoding;

  static Uri _url() => Uri.parse(_baseUrl);

  static Map<String, String> _headers() =>
      {'Content-Type': 'application/json', 'Authorization': 'Bearer $_apiKey'};

  static void _checkKey() {
    if (_apiKey.isEmpty) {
      throw Exception(
          'API Key no configurada. Configura groqSyncKey en app_secrets.dart o pasa --dart-define=GROQ_API_KEY=gsk_... al compilar.');
    }
  }

  /// Recorta un texto a un máximo de caracteres conservando JSON válido.
  static String _recortar(String texto, int max) {
    if (texto.length <= max) return texto;
    return texto.substring(0, max);
  }

  /// Compacta sugerencias a los campos esenciales y limita la cantidad
  /// (para no superar el ToKens Per Minute del plan free de Groq).
  static List<Map<String, dynamic>> _compactarSugerencias(
      List<Map<String, dynamic>> sugerencias) {
    final resultado = <Map<String, dynamic>>[];
    for (final s in sugerencias.take(_maxSugerenciasPorLlamada)) {
      resultado.add({
        'id': s['id']?.toString() ?? '',
        'calle': (s['calle'] ?? s['direccion'] ?? s['texto_direccion'] ?? '')
            .toString(),
        'numero': s['numero']?.toString() ?? '',
        'complemento': s['complemento']?.toString() ?? '',
        'barrio': s['barrio']?.toString() ?? '',
      });
    }
    return resultado;
  }

  /// Compacta tarjetas a un resumen liviano y limita la cantidad.
  static List<Map<String, dynamic>> _compactarTarjetas(
      List<Map<String, dynamic>> tarjetas) {
    final resultado = <Map<String, dynamic>>[];
    for (final t in tarjetas.take(_maxTarjetasPorLlamada)) {
      final data = t['data'] is Map
          ? Map<String, dynamic>.from(t['data'] as Map)
          : Map<String, dynamic>.from(t);
      resultado.add({
        'id': t['id']?.toString() ?? data['id']?.toString() ?? '',
        'nombre': data['nombre']?.toString() ?? t['nombre']?.toString() ?? '',
        'territorio': data['territorio_id']?.toString() ??
            data['territorio']?.toString() ??
            '',
        'totalDirecciones':
            data['totalDirecciones'] ?? data['direccionesCount'] ?? 0,
      });
    }
    return resultado;
  }

  // 1. Probar conexión activa con Groq
  static Future<bool> verificarConexion() async {
    try {
      _checkKey();
      final response = await http.post(
        _url(),
        headers: _headers(),
        body: jsonEncode({
          "model": _model,
          "messages": [
            {
              "role": "user",
              "content": "Responde OK"
            }
          ],
          "temperature": 0.1,
          "max_tokens": 30,
        }),
      );

      if (response.statusCode == 200) {
        return true;
      } else {
        print('Error Handshake Groq: ${response.statusCode} - ${response.body}');
        return false;
      }
    } catch (e) {
      print('Excepción Handshake Groq: $e');
      return false;
    }
  }

  static Future<Map<String, dynamic>> _chat(
      String systemPrompt, String userPrompt,
      {String model = _model, int maxTokens = _maxOutputTokens}) async {
    _checkKey();
    final response = await http.post(
      _url(),
      headers: _headers(),
      body: jsonEncode({
        "model": model,
        "temperature": 0.2,
        "max_tokens": maxTokens,
        "response_format": {"type": "json_object"},
        "messages": [
          {"role": "system", "content": systemPrompt},
          {"role": "user", "content": _recortar(userPrompt, _maxUserPromptChars)}
        ],
      }),
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      String content =
          data['choices'][0]['message']['content'] as String? ?? '';
      if (content.trim().isEmpty) {
        throw Exception(
            'La IA no devolvió contenido (razonó sin responder). Reintenta.');
      }
      return jsonDecode(content) as Map<String, dynamic>;
    } else {
      throw Exception('Error al conectar con la IA de Groq: ${response.body}');
    }
  }

  /// Genera un plan completo de reorganización territorial.
  ///
  /// Retorna un mapa con:
  /// - explicacion_narrativa: resumen humano
  /// - tarjetas_a_eliminar: [String]
  /// - tarjetas_a_crear_o_actualizar: [...]
  /// - desglose_por_barrio: [...]
  /// - direcciones_duplicadas: [{id, calle, barrio, complemento, motivo}]
  /// - movimientos: [{direccion_id, calle, barrio, desde_tarjeta, hacia_tarjeta}]
  /// - territorio_nuevo_sugerido: {nombre, motivo} | null
  /// - estado_final: [{tarjeta_nombre, direcciones, creada_eliminada}]
  static Future<Map<String, dynamic>> analizarYPlanificarReorganizacion({
    required List<Map<String, dynamic>> sugerencias,
    required List<Map<String, dynamic>> tarjetasActuales,
  }) async {
    final sugerenciasCompactas = _compactarSugerencias(sugerencias);
    final tarjetasCompactas = _compactarTarjetas(tarjetasActuales);

    final systemPrompt = '''
Actúa como un Motor de Inteligencia Territorial para una congregación.
Analiza nuevas direcciones/sugerencias y la estructura de tarjetas actuales para proponer un plan de reorganización COMPLETO y seguro.

Reglas de Negocio:
1. Agrupa direcciones por cercanía o mismo barrio (máximo 8 direcciones por tarjeta).
2. Duplicados: dos direcciones son duplicadas SOLO si coinciden calle Y número Y barrio Y el complemento es igual o está vacío. Si el complemento difiere (ej. "Rua Teste Casa 1" vs "Rua Teste Casa 2"), NO son duplicadas: cada complemento es una casa/familia válida distinta.
3. Si una tarjeta queda con 0 direcciones, márcala para eliminar.
4. Si un barrio excede el límite de 8, planifica crear/actualizar tarjetas.
5. Sugiere territorio nuevo solo si existe un cluster geográfico/barrio sin tarjeta.
6. Para cada dirección, indica hacia qué tarjeta se moverá.
7. Proporciona una explicación narrativa clara, humana y detallada.

Responde SIEMPRE con un JSON válido de esta forma exacta:
{
  "explicacion_narrativa": "...",
  "tarjetas_a_eliminar": [{"id":"...","nombre":"..."}],
  "tarjetas_a_crear_o_actualizar": [
    {"id": "...", "nombre": "...", "territorioId": "", "direccionesCount": 0, "nueva": true}
  ],
  "desglose_por_barrio": ["..."],
  "direcciones_duplicadas": [
    {"id":"...", "calle":"...", "barrio":"...", "complemento":"...", "motivo":"duplicado"}
  ],
  "movimientos": [
    {"direccion_id":"...", "calle":"...", "barrio":"...", "desde_tarjeta":"...", "hacia_tarjeta":"..."}
  ],
  "territorio_nuevo_sugerido": {"nombre":"...", "motivo":"..."},
  "estado_final": [
    {"tarjeta_nombre":"...", "direcciones": 0, "creada_o_eliminada":"ninguna"}
  ]
}
''';

    final userPrompt = '''
Sugerencias a reorganizar: ${jsonEncode(sugerenciasCompactas)}
Tarjetas actuales (resumen): ${jsonEncode(tarjetasCompactas)}
''';

    return _chat(systemPrompt, userPrompt, model: _razonamientoModel);
  }

  // 3. Extraer direcciones estructuradas desde un fragmento de chat de WhatsApp
  static Future<List<Map<String, dynamic>>> extraerDireccionesWhatsApp({
    required String textoWhatsApp,
  }) async {
    final systemPrompt = '''
Actúa como un Motor de Inteligencia Territorial para una congregación.
Recibe un fragmento de chat de WhatsApp y extrae TODAS las direcciones mencionadas como un ARRAY JSON.

Reglas de Negocio:
1. Cada registro debe contener los campos EXACTOS:
   direccion (calle + número), numero (número de casa, string), barrio,
   observaciones (notas relevantes), casas_detectadas (número entero de
   casas/familias en el mismo terreno) y tarjeta_sugerida (nombre de la
   tarjeta/territorio sugerido, cadena vacía si no se sabe).
2. Si el texto indica VARIAS casas/familias en un mismo terreno (p. ej.
   "fundos", "2 familias", "terreno con 3 casas"), DESGLOSA el registro en
   un documento por casa/familia y agrega una sub-etiqueta en el campo
   observaciones, ejemplos: "Fundos - Casa 1", "Fundos - Casa 2",
   "Casa 1 de 2", "Casa 2 de 2".
3. Ignora mensajes sin direcciones claras. No inventes datos.
4. Responde SIEMPRE con un JSON de la forma:
   {"direcciones": [ { "direccion": "...", "numero": "...", "barrio": "...",
   "observaciones": "...", "casas_detectadas": 1, "tarjeta_sugerida": "..." } ] }
''';

    final userPrompt = _recortar(textoWhatsApp, _maxUserPromptChars);

    final objeto = await _chat(systemPrompt, userPrompt);
    final lista = objeto['direcciones'] as List? ?? [];
    return lista.map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  static Future<Map<String, dynamic>> decidirTarjetaParaDireccion({
    required Map<String, dynamic> direccion,
    required List<Map<String, dynamic>> tarjetasExistentes,
  }) async {
    final tarjetasCompactas = _compactarTarjetas(tarjetasExistentes);

    final systemPrompt = '''
Actúa como un Motor de Inteligencia Territorial para una congregación.
Recibe una dirección nueva y la lista de tarjetas actuales. Decide a cuál tarjeta asignar la dirección.

Reglas de Negocio:
1. Asigna la dirección a la tarjeta más cercana geográficamente o del mismo barrio/territorio.
2. Respeta el cupo máximo de 8 direcciones por tarjeta.
3. Si no hay cupo en la tarjeta más cercana, selecciona la siguiente con cupo.
4. Responde SIEMPRE con un JSON válido con los campos: tarjeta_id_destino
   (ID del documento), tarjeta_nombre (nombre visible) y explicacion
   (razonamiento humano y detallado).
''';

    final direccionJson = jsonEncode({
      'calle': direccion['calle'],
      'numero': direccion['numero'],
      'complemento': direccion['complemento'],
      'barrio': direccion['barrio'],
    });

    final userPrompt = '''
Dirección nueva (compacta): $direccionJson
Tarjetas actuales (resumen): ${jsonEncode(tarjetasCompactas)}
''';

    return _chat(systemPrompt, userPrompt, model: _razonamientoModel);
  }

  /// Normaliza y ordena un lote de direcciones crudas para enviarlas a
  /// geocodificar a Mapbox con la mayor precisión posible.
  ///
  /// Groq completa ciudad/estado faltantes, corrige abreviaturas comunes
  /// (R. -> Rua, Av. -> Avenida, etc.) SIN inventar datos que no estén en
  /// el original, y devuelve el orden sugerido de envío agrupando por
  /// barrio/cercanía (así, si una geocodificación falla, sus vecinas del
  /// mismo lote sirven de contexto para reintentar).
  ///
  /// [direccionesCrudas]: cada mapa debe tener al menos "id" y
  /// "calle"/"direccion"; "numero", "complemento" y "barrio" son opcionales.
  ///
  /// Retorna una lista de mapas:
  /// { id, direccion_normalizada, orden, confianza }.
  /// "confianza" es "alta"/"media"/"baja" según qué tan completa estaba la
  /// dirección original.
  static Future<List<Map<String, dynamic>>> normalizarDireccionesParaGeocoding(
    List<Map<String, dynamic>> direccionesCrudas,
  ) async {
    if (direccionesCrudas.isEmpty) return [];

    final lote =
        direccionesCrudas.take(_maxDireccionesPorLoteGeocoding).toList();
    final compactas = lote
        .map((d) => {
              'id': d['id']?.toString() ?? '',
              'calle': (d['calle'] ?? d['direccion'] ?? '').toString(),
              'numero': d['numero']?.toString() ?? '',
              'complemento': d['complemento']?.toString() ?? '',
              'barrio': d['barrio']?.toString() ?? '',
            })
        .toList();

    final systemPrompt = '''
Actúa como un Motor de Inteligencia Territorial para una congregación en Araucária, Paraná, Brasil.
Recibe una lista de direcciones crudas (posiblemente incompletas o mal escritas) y las prepara para ser geocodificadas por Mapbox con la máxima precisión posible.

Reglas de Negocio:
1. Arma "direccion_normalizada" como un string completo listo para geocodificar: calle + número (si existe) + barrio (si existe) + ciudad/estado. Si el original NO especifica ciudad/estado, agrega ", Araucária - PR, Brasil" al final. Si el original YA especifica una ciudad/estado distinto, respétalo tal cual (no lo sobrescribas).
2. Corrige abreviaturas comunes de calles en portugués: "R." -> "Rua", "Av." -> "Avenida", "Pça." -> "Praça", "Trav." -> "Travessa". No inventes número, barrio ni ningún dato que no esté en el original.
3. Asigna "confianza" ("alta", "media", "baja") según qué tan completa/clara está la dirección original para ser geocodificada (ej. sin número = "baja").
4. Asigna "orden" (entero desde 1) agrupando las direcciones por barrio/cercanía, de forma que direcciones del mismo barrio queden consecutivas.
5. No omitas ninguna dirección recibida: la cantidad de salida debe ser igual a la de entrada.

Responde SIEMPRE con un JSON válido de esta forma exacta:
{
  "direcciones": [
    {"id": "...", "direccion_normalizada": "...", "orden": 1, "confianza": "alta"}
  ]
}
''';

    final userPrompt = 'Direcciones a normalizar: ${jsonEncode(compactas)}';

    final objeto = await _chat(
      systemPrompt,
      userPrompt,
      model: _razonamientoModel,
      maxTokens: _maxOutputTokensGeocoding,
    );

    final lista = objeto['direcciones'] as List? ?? [];
    return lista.map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }
}
