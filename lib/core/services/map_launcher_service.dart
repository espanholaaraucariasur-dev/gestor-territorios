import 'package:flutter/foundation.dart' show kIsWeb, debugPrint;
import 'package:url_launcher/url_launcher.dart';

class MapLauncherService {
  /// Abre Google Maps con una ruta multi-parada enviando una lista de direcciones.
  static Future<void> abrirRutaMultiplesDirecciones(List<String> direcciones) async {
    if (direcciones.isEmpty) return;

    try {
      Uri url;

      if (direcciones.length == 1) {
        url = Uri(
          scheme: 'https',
          host: 'www.google.com',
          path: '/maps/search/',
          queryParameters: {
            'api': '1',
            'query': direcciones.first,
          },
        );
      } else {
        final String origen = direcciones.first;
        final String destino = direcciones.last;
        final List<String> intermedias =
            direcciones.sublist(1, direcciones.length - 1);

        final Map<String, String> queryParams = {
          'api': '1',
          'origin': origen,
          'destination': destino,
        };

        if (intermedias.isNotEmpty) {
          queryParams['waypoints'] = intermedias.join('|');
        }

        url = Uri(
          scheme: 'https',
          host: 'www.google.com',
          path: '/maps/dir/',
          queryParameters: queryParams,
        );
      }

      final LaunchMode mode = kIsWeb
          ? LaunchMode.platformDefault
          : LaunchMode.externalApplication;

      if (await canLaunchUrl(url)) {
        await launchUrl(url, mode: mode);
      } else {
        debugPrint('No se pudo abrir la ruta en Google Maps');
      }
    } catch (e) {
      debugPrint('Error al abrir Google Maps: $e');
    }
  }
}