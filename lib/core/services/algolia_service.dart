import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:cloud_firestore/cloud_firestore.dart';

/// Servicio de Algolia para búsqueda robusta de direcciones.
/// Plan Free: 10,000 búsquedas/mes — suficiente para uso congregacional.
class AlgoliaService {
  static const String _appId = '0DXT0ACC9Z';
  static const String _searchKey = '6fba0df3111fb7a9e6ade60c81d86316';
  static const String _adminKey = 'ea89a21cffb75ebbc13deacc8c7e01c8';
  static const String _indexName = 'direcciones';

  static const String _baseUrl = 'https://$_appId-dsn.algolia.net';
  static const String _adminUrl = 'https://$_appId.algolia.net';

  // ─────────────────────────────────────────────────────────
  // BUSCAR
  // ─────────────────────────────────────────────────────────

  /// Busca una dirección en Algolia.
  /// Retorna el primer resultado o null si no hay coincidencias.
  static Future<Map<String, dynamic>?> buscar(String consulta) async {
    try {
      final url = Uri.parse('$_baseUrl/1/indexes/$_indexName/query');
      final response = await http.post(
        url,
        headers: {
          'X-Algolia-Application-Id': _appId,
          'X-Algolia-API-Key': _searchKey,
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'query': consulta,
          'hitsPerPage': 1,
          'typoTolerance': true,
          'ignorePlurals': true,
          'removeStopWords': false,
          'attributesToRetrieve': [
            'calle',
            'complemento',
            'barrio',
            'territorio_id',
            'tarjeta_id',
            'estado_predicacion',
            'estado',
            'objectID',
          ],
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final hits = data['hits'] as List?;
        if (hits != null && hits.isNotEmpty) {
          return hits.first as Map<String, dynamic>;
        }
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  // ─────────────────────────────────────────────────────────
  // SINCRONIZAR DESDE FIRESTORE
  // ─────────────────────────────────────────────────────────

  /// Sincroniza todas las direcciones de Firestore a Algolia.
  /// Llamar desde el panel admin cuando se agreguen nuevas direcciones.
  static Future<Map<String, dynamic>> sincronizarTodas() async {
    try {
      final snap = await FirebaseFirestore.instance
          .collection('direcciones_globales')
          .get();

      if (snap.docs.isEmpty) {
        return {'exito': false, 'mensaje': 'No hay direcciones para sincronizar'};
      }

      // Construir objetos para Algolia
      final objetos = snap.docs.map((doc) {
        final data = doc.data();
        return {
          'objectID': doc.id,
          'calle': data['calle']?.toString() ?? '',
          'complemento': data['complemento']?.toString() ?? '',
          'barrio': data['barrio']?.toString() ?? '',
          'territorio_id': data['territorio_id']?.toString() ?? '',
          'tarjeta_id': data['tarjeta_id']?.toString() ?? '',
          'estado_predicacion': data['estado_predicacion']?.toString() ?? '',
          'estado': data['estado']?.toString() ?? '',
          // Campo de búsqueda completo
          'direccion_completa':
              '${data['calle'] ?? ''} ${data['complemento'] ?? ''} ${data['barrio'] ?? ''}',
        };
      }).toList();

      // Enviar en lotes de 1000 (límite de Algolia)
      int enviados = 0;
      for (int i = 0; i < objetos.length; i += 1000) {
        final lote = objetos.sublist(
          i,
          i + 1000 > objetos.length ? objetos.length : i + 1000,
        );

        final url = Uri.parse('$_adminUrl/1/indexes/$_indexName/batch');
        final response = await http.post(
          url,
          headers: {
            'X-Algolia-Application-Id': _appId,
            'X-Algolia-API-Key': _adminKey,
            'Content-Type': 'application/json',
          },
          body: jsonEncode({
            'requests': lote
                .map((obj) => {'action': 'addObject', 'body': obj})
                .toList(),
          }),
        );

        if (response.statusCode == 200) {
          enviados += lote.length;
        }
      }

      // Configurar atributos de búsqueda
      await _configurarIndice();

      return {
        'exito': true,
        'mensaje': '$enviados direcciones sincronizadas',
        'total': snap.docs.length,
      };
    } catch (e) {
      return {'exito': false, 'mensaje': 'Error: $e'};
    }
  }

  /// Agrega o actualiza una sola dirección en Algolia.
  static Future<void> sincronizarUna(String docId, Map<String, dynamic> data) async {
    try {
      final url = Uri.parse('$_adminUrl/1/indexes/$_indexName/$docId');
      await http.put(
        url,
        headers: {
          'X-Algolia-Application-Id': _appId,
          'X-Algolia-API-Key': _adminKey,
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'objectID': docId,
          'calle': data['calle']?.toString() ?? '',
          'complemento': data['complemento']?.toString() ?? '',
          'barrio': data['barrio']?.toString() ?? '',
          'territorio_id': data['territorio_id']?.toString() ?? '',
          'tarjeta_id': data['tarjeta_id']?.toString() ?? '',
          'estado_predicacion': data['estado_predicacion']?.toString() ?? '',
          'estado': data['estado']?.toString() ?? '',
          'direccion_completa':
              '${data['calle'] ?? ''} ${data['complemento'] ?? ''} ${data['barrio'] ?? ''}',
        }),
      );
    } catch (_) {}
  }

  // ─────────────────────────────────────────────────────────
  // CONFIGURAR ÍNDICE
  // ─────────────────────────────────────────────────────────

  static Future<void> _configurarIndice() async {
    try {
      final url = Uri.parse('$_adminUrl/1/indexes/$_indexName/settings');
      await http.put(
        url,
        headers: {
          'X-Algolia-Application-Id': _appId,
          'X-Algolia-API-Key': _adminKey,
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'searchableAttributes': [
            'calle',
            'direccion_completa',
            'complemento',
            'barrio',
          ],
          'typoTolerance': true,
          'minWordSizefor1Typo': 4,
          'minWordSizefor2Typos': 8,
          'ignorePlurals': true,
          'removeStopWords': false,
          'queryLanguages': ['pt', 'es'],
        }),
      );
    } catch (_) {}
  }
}
