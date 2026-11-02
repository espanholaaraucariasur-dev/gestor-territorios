import 'package:cloud_firestore/cloud_firestore.dart';

/// Contadores acumulados de la bandeja de temporales.
///
/// POR QUÉ UN SERVICIO Y NO LEER EL HISTORIAL
///
/// Antes, `Estadísticas` derivaba los totales así:
///   entradas = direccionesQueHayAhora + salidasDelHistorial
/// Es una fórmula, no un contador. Se rompe en cuanto una dirección sale de la
/// bandeja sin que se haya registrado su movimiento `salida`: el conteo en vivo
/// baja, `salidas` no sube, y **"Entradas" baja**, que es justo lo que no
/// debería pasar. Cualquier corrección manual, cambio de `estado` o proceso
/// masivo también lo hunde.
///
/// Además el historial se leía con `limit(2000)`: al crecer, los movimientos
/// más antiguos se salen de la ventana y los totales volverían a caer.
///
/// Solución: contadores que SOLO suman, guardados en Firestore e
/// incrementados en el mismo momento en que se registra un movimiento. La
/// línea base congela lo que ya existía antes de que existiera el historial, de
/// modo que la primera vez el número coincide con el que ya veías y de ahí en
/// adelante solo crece.
///
/// Invariante que se mantiene:
///   entradas - salidas = direcciones que hay ahora en la bandeja
class EstadisticasTemporalesService {
  EstadisticasTemporalesService._();

  static DocumentReference<Map<String, dynamic>> get _ref =>
      FirebaseFirestore.instance
          .collection('estadisticas_temporales')
          .doc('global');

  static const String _campoEntradasAcum = 'entradas_acumuladas';
  static const String _campoSalidasAcum = 'salidas_acumuladas';

  /// Suma 1 al contador que corresponda. Se llama al registrar un movimiento.
  ///
  /// Es best-effort: si falla, el movimiento igual quedó registrado en el
  /// historial y la diferencia se recupera con [recalcularDesdeHistorial].
  static Future<void> sumarMovimiento(String tipo) async {
    final campo = (tipo == 'entrada') ? _campoEntradasAcum : _campoSalidasAcum;
    try {
      // Incremento atómico y persistible offline. La transacción anterior
      // requería leer el servidor y fallaba sin conexión; `increment` crea el
      // campo como 1 si todavía no existía.
      await _ref.set({
        campo: FieldValue.increment(1),
        'actualizado_en': Timestamp.now(),
      }, SetOptions(merge: true));
    } catch (_) {}
  }

  /// Lee los contadores. Devuelve `null` si todavía no se inicializaron.
  static Future<AcumuladosTemporales?> leerAcumulados() async {
    try {
      final snap = await _ref.get();
      if (!snap.exists) return null;
      final d = snap.data() ?? const {};
      final baseEntradas = (d['entradas_inicial'] as num?)?.toInt();
      final baseSalidas = (d['salidas_inicial'] as num?)?.toInt();
      if (baseEntradas == null || baseSalidas == null) return null;
      return AcumuladosTemporales(
        entradas:
            baseEntradas + ((d[_campoEntradasAcum] as num?)?.toInt() ?? 0),
        salidas: baseSalidas + ((d[_campoSalidasAcum] as num?)?.toInt() ?? 0),
      );
    } catch (_) {
      return null;
    }
  }

  /// Congela la línea base UNA sola vez, si aún no existe.
  ///
  /// La base guarda el VALOR QUE SE VEÍA EN EL MOMENTO DE CONGELAR, no una
  /// constante "anterior al historial". Esa diferencia es lo que evita que el
  /// número salte al activar los contadores.
  ///
  /// [actuales] es el conteo en vivo de la bandeja y [salidasHistorico] los
  /// movimientos de salida ya registrados, que es lo que la fórmula anterior
  /// sumaba. Se congelan esos mismos números:
  ///
  ///   entradasInicial = actuales + salidasHistorico   (la fórmula de antes)
  ///   salidasInicial  = salidasHistorico
  ///
  /// A partir de ahí los acumulados arrancan en 0 y solo crecen, así que:
  ///
  ///   entradas - salidas
  ///     = (actuales + salidasHistorico) - salidasHistorico
  ///     = actuales
  ///
  /// Las ENTRADAS del historial ya no intervienen: esas direcciones hoy están
  /// en la bandeja, o sea que ya están dentro de [actuales]. Sumarlas otra vez
  /// vía una constante "pre-historial" hacía que Entradas BAJARA justo al
  /// congelar, que es justo lo que esta mejora prometía evitar.
  static Future<AcumuladosTemporales?> asegurarLineaBase({
    required int actuales,
    required int salidasHistorico,
  }) async {
    try {
      final entradasInicial = actuales + salidasHistorico;
      final salidasInicial = salidasHistorico;

      // Transacción: si dos pantallas abren a la vez, solo una congela la base.
      await FirebaseFirestore.instance.runTransaction((tx) async {
        final snap = await tx.get(_ref);
        if (snap.exists) {
          final d = snap.data() ?? const {};
          if (d['entradas_inicial'] != null) return; // Ya congelada.
        }
        // `set` deliberadamente REEMPLAZA: los acumulados vuelven a 0 porque la
        // base ya los absorbió. Cualquier incremento de [sumarMovimiento] que
        // llegara antes de congelar está respaldado por su escritura en
        // `historial_temporales`, que es justamente de donde sale
        // [salidasHistorico]; aquí no se pierde nada.
        tx.set(_ref, {
          'entradas_inicial': entradasInicial < 0 ? 0 : entradasInicial,
          'salidas_inicial': salidasInicial < 0 ? 0 : salidasInicial,
          _campoEntradasAcum: 0,
          _campoSalidasAcum: 0,
          'creado_en': FieldValue.serverTimestamp(),
          'baseline_pendiente': false,
          'nota': 'Linea base congelada con el valor que mostraba la formula '
              'anterior: actuales + salidas del historial.',
        });
      });

      return leerAcumulados();
    } catch (_) {
      return null;
    }
  }

  /// Reconstruye los totales desde cero a partir del historial.
  ///
  /// Solo para reparar. A diferencia de [asegurarLineaBase] no congela: pisa la
  /// base y los acumulados, así que se usa sabiendo que el resultado queda
  /// exactamente en "lo que había antes de los movimientos registrados" más lo
  /// que había en la bandeja. [actuales] es imprescindible: sin él no se puede
  /// reconstruir el total, porque el historial solo guarda los movimientos, no la
  /// foto.
  static Future<void> recalcularDesdeHistorial({
    required int actuales,
    required int salidasHistorico,
  }) async {
    try {
      await _ref.set({
        'entradas_inicial': actuales + salidasHistorico,
        'salidas_inicial': salidasHistorico,
        _campoEntradasAcum: 0,
        _campoSalidasAcum: 0,
        'baseline_pendiente': false,
        'actualizado_en': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (_) {}
  }
}

/// Totales acumulados de entradas y salidas de la bandeja de temporales.
class AcumuladosTemporales {
  final int entradas;
  final int salidas;

  const AcumuladosTemporales({required this.entradas, required this.salidas});

  @override
  String toString() => 'Acumulados(entradas: $entradas, salidas: $salidas)';
}
