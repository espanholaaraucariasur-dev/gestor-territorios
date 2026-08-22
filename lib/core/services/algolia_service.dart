import 'package:algolia_client_search/algolia_client_search.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../config/app_secrets.dart';

/// Servicio de Algolia usando la librería oficial `algolia_client_search`.
/// Plan Free: 10,000 búsquedas/mes — suficiente para uso congregacional.
class AlgoliaService {
  static const String _appId = AppSecrets.algoliaAppId;
  static const String _searchKey = AppSecrets.algoliaSearchKey;
  static const String _adminKey = AppSecrets.algoliaAdminKey;
  static const String _indexName = 'direcciones';

  // Cliente singleton (read + write usan mismo client con keys diferentes)
  static SearchClient? _searchClient;
  static SearchClient? _adminClient;

  static SearchClient get _readClient => _searchClient ??= SearchClient(
        appId: _appId,
        apiKey: _searchKey,
      );

  static SearchClient get _writeClient => _adminClient ??= SearchClient(
        appId: _appId,
        apiKey: _adminKey,
      );

  // ─────────────────────────────────────────────────────────
  // VERIFICACIÓN DE CONECTIVIDAD
  // ─────────────────────────────────────────────────────────

  /// Verifica conectividad intentando obtener settings del índice.
  static Future<Map<String, dynamic>> verificarConexion() async {
    try {
      await _writeClient.getSettings(indexName: _indexName);
      return {'ok': true, 'mensaje': 'Conexión a Algolia exitosa'};
    } on AlgoliaApiException catch (e) {
      if (e.statusCode == 401) {
        return {'ok': false, 'mensaje': 'Credenciales Algolia inválidas (401). Verifica App ID y Admin Key.'};
      } else if (e.statusCode == 404) {
        return {'ok': false, 'mensaje': 'Índice "direcciones" no existe en Algolia (404). Se creará al sincronizar.'};
      }
      return {'ok': false, 'mensaje': 'Algolia error: ${e.error} (code: ${e.statusCode})'};
    } on AlgoliaTimeoutException catch (e) {
      return {'ok': false, 'mensaje': 'Timeout conectando a Algolia: ${e.error}'};
    } on AlgoliaIOException catch (e) {
      if (e.toString().contains('SocketException') || e.toString().contains('Failed host lookup')) {
        return {'ok': false, 'mensaje': 'No se puede resolver el host Algolia. Verifica: (1) conexión a internet, (2) DNS del dispositivo, (3) que el App ID sea correcto.'};
      }
      return {'ok': false, 'mensaje': 'Error de red: ${e.error}'};
    } catch (e) {
      return {'ok': false, 'mensaje': 'Error inesperado: $e'};
    }
  }

  // ─────────────────────────────────────────────────────────
  // BUSCAR
  // ─────────────────────────────────────────────────────────

  /// Busca una dirección en Algolia.
  /// Retorna el primer resultado o null si no hay coincidencias o error.
  static Future<Map<String, dynamic>?> buscar(String consulta) async {
    try {
      final response = await _readClient.searchSingleIndex(
        indexName: _indexName,
        searchParams: SearchParamsObject(
          query: consulta,
          hitsPerPage: 1,
          typoTolerance: true,
          ignorePlurals: true,
          attributesToRetrieve: [
            'calle',
            'complemento',
            'barrio',
            'territorio_id',
            'tarjeta_id',
            'estado_predicacion',
            'estado',
          ],
        ),
      );

      if (response.hits.isNotEmpty) {
        // El hit viene como Object (JSON deserializado)
        final hit = response.hits.first;
        if (hit is Map<String, dynamic>) {
          return hit;
        }
      }
      return null;
    } catch (_) {
      // Silencioso en búsqueda (widget tiene fallback a Firestore)
      return null;
    }
  }

  // ─────────────────────────────────────────────────────────
  // SINCRONIZAR DESDE FIRESTORE
  // ─────────────────────────────────────────────────────────

  /// Sincroniza todas las direcciones de Firestore a Algolia.
  static Future<Map<String, dynamic>> sincronizarTodas() async {
    // 1. Verificar conectividad primero
    final check = await verificarConexion();
    if (!check['ok'] as bool) {
      return {'exito': false, 'mensaje': 'Pre-check falló: ${check['mensaje']}'};
    }

    try {
      final snap = await FirebaseFirestore.instance
          .collection('direcciones_globales')
          .get();

      if (snap.docs.isEmpty) {
        return {'exito': false, 'mensaje': 'No hay direcciones para sincronizar'};
      }

      // Construir objetos para Algolia
      final objetos = <Map<String, dynamic>>[];
      for (final doc in snap.docs) {
        final data = doc.data();
        objetos.add({
          'objectID': doc.id,
          'calle': data['calle']?.toString() ?? '',
          'complemento': data['complemento']?.toString() ?? '',
          'barrio': data['barrio']?.toString() ?? '',
          'territorio_id': data['territorio_id']?.toString() ?? '',
          'tarjeta_id': data['tarjeta_id']?.toString() ?? '',
          'estado_predicacion': data['estado_predicacion']?.toString() ?? '',
          'estado': data['estado']?.toString() ?? '',
          'direccion_completa':
              '${data['calle'] ?? ''} ${data['complemento'] ?? ''} ${data['barrio'] ?? ''}',
        });
      }

      // Enviar en lotes de 1000 (límite de Algolia)
      int enviados = 0;
      for (int i = 0; i < objetos.length; i += 1000) {
        final lote = objetos.sublist(
          i,
          i + 1000 > objetos.length ? objetos.length : i + 1000,
        );

        final requests = lote
            .map((obj) => BatchRequest(action: Action.addObject, body: obj))
            .toList();

        try {
          await _writeClient.batch(
            indexName: _indexName,
            batchWriteParams: BatchWriteParams(requests: requests),
          );
          enviados += lote.length;
        } on AlgoliaApiException catch (e) {
          return {
            'exito': false,
            'mensaje': 'Error en lote $i: ${e.error} (code: ${e.statusCode})'
          };
        }
      }

      // Configurar atributos de búsqueda
      await _configurarIndice();

      return {
        'exito': true,
        'mensaje': '$enviados direcciones sincronizadas',
        'total': snap.docs.length,
      };
    } on AlgoliaApiException catch (e) {
      return {'exito': false, 'mensaje': 'Algolia: ${e.error} (code: ${e.statusCode})'};
    } on AlgoliaTimeoutException catch (e) {
      return {'exito': false, 'mensaje': 'Timeout: ${e.error}'};
    } on AlgoliaIOException catch (e) {
      return {'exito': false, 'mensaje': 'Error de red: ${e.error}'};
    } catch (e) {
      return {'exito': false, 'mensaje': 'Error: $e'};
    }
  }

  /// Agrega o actualiza una sola dirección en Algolia.
  static Future<void> sincronizarUna(String docId, Map<String, dynamic> data) async {
    try {
      final obj = {
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
      };

      await _writeClient.addOrUpdateObject(
        indexName: _indexName,
        objectID: docId,
        body: obj,
      );
    } catch (_) {
      // Silencioso para no bloquear flujo principal
    }
  }

  // ─────────────────────────────────────────────────────────
  // CONFIGURAR ÍNDICE
  // ─────────────────────────────────────────────────────────

  static Future<void> _configurarIndice() async {
    try {
      await _writeClient.setSettings(
        indexName: _indexName,
        indexSettings: IndexSettings(
          searchableAttributes: [
            'calle',
            'direccion_completa',
            'complemento',
            'barrio',
          ],
          typoTolerance: true,
          minWordSizefor1Typo: 4,
          minWordSizefor2Typos: 8,
          ignorePlurals: true,
          removeStopWords: false,
          queryLanguages: [SupportedLanguage.pt, SupportedLanguage.es],
        ),
      );
    } catch (_) {}
  }
}