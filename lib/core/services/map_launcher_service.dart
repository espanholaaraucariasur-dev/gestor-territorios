import 'package:flutter/foundation.dart'
    show kIsWeb, debugPrint, defaultTargetPlatform, TargetPlatform;
import 'package:url_launcher/url_launcher.dart';

class MapLauncherService {
  /// Abre Google Maps con una ruta multi-parada enviando una lista de direcciones.
  ///
  /// IMPORTANTE: Cada dirección en [direcciones] debe incluir ciudad y estado
  /// (ej: "R. Araucária, 290 - Jardim Bela Vista, Araucária - PR"), de lo
  /// contrario la API puede geolocalizar la calle en otro municipio con el
  /// mismo nombre y generar rutas absurdas de cientos de km. Esa parte se
  /// corrige donde se arma la lista de direcciones (ej. mapa_territorio_page.dart),
  /// no aquí.
  ///
  /// [travelmode] acepta 'driving' (default), 'walking', 'bicycling' o 'transit'.
  static Future<void> abrirRutaMultiplesDirecciones(
    List<String> direcciones, {
    String travelmode = 'driving',
  }) async {
    if (direcciones.isEmpty) return;

    try {
      // En iOS, enviar directamente una URL web (https://www.google.com/maps/...)
      // al deep link nativo de la app produce "El vínculo no es compatible".
      // Hay que usar primero el esquema nativo comgooglemaps://.
      if (!kIsWeb && defaultTargetPlatform == TargetPlatform.iOS) {
        final Uri nativeUrl = _construirUrlNativaIOS(direcciones, travelmode);
        if (await canLaunchUrl(nativeUrl)) {
          await launchUrl(nativeUrl, mode: LaunchMode.externalApplication);
          return;
        }
        // Si la app nativa no está instalada, seguimos con el fallback web.
      }

      final Uri webUrl = _construirUrlWeb(direcciones, travelmode);
      final LaunchMode mode =
          kIsWeb ? LaunchMode.platformDefault : LaunchMode.externalApplication;

      if (await canLaunchUrl(webUrl)) {
        await launchUrl(webUrl, mode: mode);
      } else {
        debugPrint('No se pudo abrir la ruta en Google Maps');
      }
    } catch (e) {
      debugPrint('Error al abrir Google Maps: $e');
    }
  }

  /// URL universal de Google Maps (funciona en Android/Web y como fallback en iOS).
  static Uri _construirUrlWeb(List<String> direcciones, String travelmode) {
    if (direcciones.length == 1) {
      return Uri(
        scheme: 'https',
        host: 'www.google.com',
        path: '/maps/search/',
        queryParameters: {
          'api': '1',
          'query': direcciones.first,
        },
      );
    }

    final String origen = direcciones.first;
    final String destino = direcciones.last;
    final List<String> intermedias =
        direcciones.sublist(1, direcciones.length - 1);

    final Map<String, String> queryParams = {
      'api': '1',
      'origin': origen,
      'destination': destino,
      'travelmode': travelmode,
    };

    if (intermedias.isNotEmpty) {
      queryParams['waypoints'] = intermedias.join('|');
    }

    return Uri(
      scheme: 'https',
      host: 'www.google.com',
      path: '/maps/dir/',
      queryParameters: queryParams,
    );
  }

  /// URL del esquema nativo de iOS (comgooglemaps://), según la API oficial:
  /// https://developers.google.com/maps/documentation/urls/ios-urlscheme
  ///
  /// Requiere que en Info.plist esté declarado en LSApplicationQueriesSchemes:
  ///   <key>LSApplicationQueriesSchemes</key>
  ///   <array>
  ///     <string>comgooglemaps</string>
  ///   </array>
  static Uri _construirUrlNativaIOS(
    List<String> direcciones,
    String travelmode,
  ) {
    if (direcciones.length == 1) {
      return Uri(
        scheme: 'comgooglemaps',
        host: '',
        queryParameters: {
          'q': direcciones.first,
        },
      );
    }

    final String origen = direcciones.first;
    final String destino = direcciones.last;
    final List<String> intermedias =
        direcciones.sublist(1, direcciones.length - 1);

    final String daddr = intermedias.isNotEmpty
        ? '${intermedias.join('+to:')}+to:$destino'
        : destino;

    return Uri(
      scheme: 'comgooglemaps',
      host: '',
      queryParameters: {
        'saddr': origen,
        'daddr': daddr,
        'directionsmode': travelmode,
      },
    );
  }
}