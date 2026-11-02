/// Utilidades para las carpetas de campana.
///
/// POR QUE EXISTE ESTO
///
/// Cada campana usa su NOMBRE como ID de la subcoleccion donde se guardan las
/// direcciones a las que el publicador no entrego la invitacion:
///
///   territorios/campanas/{nombre de la campana}/direcciones
///
/// El nombre viene de `configuracion/campana_1` o `campana_2` y lo escribe el
/// admin, asi que es texto libre. Pero un ID de coleccion en Firestore es
/// mucho mas restrictivo que un texto normal: no admite `/`, ni `.` ni `..`,
/// ni un patron que empiece y termine con `__`, ni caracteres de control.
///
/// Con un nombre invalido, construir la ruta revienta con:
///
///   Invalid argument(s): A collection path must point to a valid collection.
///
/// y como el error ocurre al ARMAR el batch, no se guarda NADA: la tarjeta
/// entera del publicador queda sin procesar.
///
/// IMPORTANTE: [idColeccionCampana] devuelve el nombre TAL CUAL cuando ya es
/// valido. Es deliberado: las campanas que ya funcionan tienen sus direcciones
/// guardadas bajo el nombre crudo, y siempre anadir un sufijo (un hash, un
/// indice) las dejaria huerfanas. Solo se transforma lo que rompia, y como la
/// funcion es determinista, los tres lados que la usan (el publicador que
/// escribe y los dos tabs de admin que leen) calculan el mismo ID.
class CampanasUtils {
  CampanasUtils._();

  /// Convierte el nombre de una campana en un ID de coleccion valido.
  ///
  /// Devuelve cadena vacia si el nombre no tiene forma de convertirse; en ese
  /// caso el llamador debe saltarse la campana en lugar de construir una ruta
  /// rota.
  static String idColeccionCampana(String nombre) {
    var s = nombre.trim();
    if (s.isEmpty) return '';

    // Caracteres de control (U+0000-U+001F y U+007F). Se quitan, no se
    // reemplazan: no aportan nada visible y si rompen la ruta.
    s = s.replaceAll(RegExp(r'[\x00-\x1F\x7F]'), '');

    // La barra es el separador del path. Este es el caso real: una campana
    // llamada "Navidad / Fin de Ano" revienta. Se convierte en guion.
    s = s.replaceAll('/', '-');

    s = s.trim();
    if (s.isEmpty) return '';

    // Solo puntos no valen, y los puntos del borde tampoco.
    s = s.replaceAll(RegExp(r'^\.+'), '');
    s = s.replaceAll(RegExp(r'\.+$'), '');
    if (s.isEmpty) return '';

    // Firebase reserva el patron __algo__ para uso propio.
    if (RegExp(r'^__.*__$').hasMatch(s)) {
      s = s.replaceAll('_', '-');
    }

    // Tope de 1500 bytes. Se corta desde el final para no partir un caracter
    // UTF-8 por la mitad.
    if (s.length > 400) {
      s = s.substring(0, 400);
      s = s.replaceAll(RegExp(r'\.+$'), '');
    }

    return s;
  }

  /// `true` si el nombre se puede usar tal cual como ID de coleccion.
  ///
  /// Sirve para avisar en la UI del admin en vez de fallar en silencio cuando
  /// el publicador procese.
  static bool esNombreValido(String nombre) {
    final limpio = nombre.trim();
    if (limpio.isEmpty) return false;
    return limpio == idColeccionCampana(nombre);
  }
}
