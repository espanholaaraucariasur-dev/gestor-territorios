import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:araucaria_sur/core/l10n/translation_service.dart';
import 'package:araucaria_sur/core/services/groq_reporte_service.dart';
import 'package:araucaria_sur/core/utils/campanas_utils.dart';
import 'package:araucaria_sur/features/home/presentation/pages/admin/seccion_progreso_territorios.dart';

class EstadisticasTab extends StatefulWidget {
  final Map<String, dynamic> usuarioData;

  const EstadisticasTab({
    super.key,
    required this.usuarioData,
  });

  @override
  State<EstadisticasTab> createState() => _EstadisticasTabState();
}

class _EstadisticasTabState extends State<EstadisticasTab> {
  // Período seleccionado: 1=mensual, 3=trimestral, 6=semestral, 12=anual
  int _mesesSeleccionados = 1;

  /// Mes específico seleccionado (clave 'AAAA-MM'). `null` = mes actual.
  String? _mesSeleccionado;

  /// Primer mes con estadísticas (la congregación empezó en Sep 2026).
  static const int _mesInicioAnio = 2026;
  static const int _mesInicioMes = 9;

  /// El Future se conserva para no repetir lecturas ni escrituras en cada
  /// rebuild. Se invalida al cambiar el período o al guardar el piso.
  Future<_DatosEstadisticas>? _datosFuture;
  String _datosFutureKey = '';

  static const Color _morado = Color(0xFF4A148C);
  static const Color _verde = Color(0xFF1B5E20);

  /// Datos cargados a mano para campañas cuyo trabajo no quedó registrado por
  /// dirección en Firestore. `completadas: null` conserva el conteo de la
  /// base. `mesInicio` evita heredar el dato en una campaña futura con el
  /// mismo nombre.
  static const Map<String, ({int total, int? completadas, String mesInicio})>
      _datosHistoricosCampana = {
    'campaña especial ( folleto)': (
      total: 187,
      completadas: 27,
      mesInicio: '2026-09',
    ),
    'invitación asamblea regional': (
      total: 187,
      completadas: null,
      mesInicio: '2026-09',
    ),
  };

  static String _claveCampana(String nombre) =>
      nombre.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');

  // ─────────────────────────────────────────────────────────
  // HELPERS DE FECHA
  // ─────────────────────────────────────────────────────────

  List<String> _getMesesPeriodo() {
    // Si hay un mes específico seleccionado, el período es solo ese mes.
    if (_mesSeleccionado != null) return [_mesSeleccionado!];
    final ahora = DateTime.now();
    final meses = <String>[];
    for (int i = _mesesSeleccionados - 1; i >= 0; i--) {
      final fecha = DateTime(ahora.year, ahora.month - i, 1);
      meses.add('${fecha.year}-${fecha.month.toString().padLeft(2, '0')}');
    }
    return meses;
  }

  /// Meses ya cerrados (desde Sep 2026 hasta el mes anterior al actual),
  /// del más reciente al más antiguo. Hoy: ['2026-09'].
  List<String> _mesesCerradosDisponibles() {
    final ahora = DateTime.now();
    final inicio = DateTime(_mesInicioAnio, _mesInicioMes, 1);
    final out = <String>[];
    var d = DateTime(ahora.year, ahora.month - 1, 1);
    while (!d.isBefore(inicio)) {
      out.add(_claveMes(d));
      d = DateTime(d.year, d.month - 1, 1);
    }
    return out;
  }

  String _claveMes(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}';

  /// Meses donde puede estar guardada la foto de cierre de una campaña.
  ///
  /// `_cerrarCampana` nombra esa foto con el mes del día de cierre, que puede
  /// caer después de `fecha_fin` (cierre automático o manual). Se recorre
  /// desde el inicio hasta dos meses después del fin para no depender de que
  /// el cierre haya sido puntual.
  List<String> _mesesCierreCampana(DateTime? inicio, DateTime? fin) {
    final desdeBase = inicio ?? fin ?? DateTime.now();
    var hastaBase = fin ?? DateTime.now();
    if (hastaBase.isBefore(desdeBase)) hastaBase = desdeBase;
    final limite = DateTime(hastaBase.year, hastaBase.month + 2, 1);
    final out = <String>[];
    var d = DateTime(desdeBase.year, desdeBase.month, 1);
    while (!d.isAfter(limite) && out.length < 18) {
      out.add(_claveMes(d));
      d = DateTime(d.year, d.month + 1, 1);
    }
    return out;
  }

  String _nombreMes(String mesStr) {
    final partes = mesStr.split('-');
    if (partes.length < 2) return mesStr;
    final meses = [
      '',
      'Ene',
      'Feb',
      'Mar',
      'Abr',
      'May',
      'Jun',
      'Jul',
      'Ago',
      'Sep',
      'Oct',
      'Nov',
      'Dic'
    ];
    final m = int.tryParse(partes[1]) ?? 0;
    return '${meses[m]} ${partes[0]}';
  }

  String _labelPeriodo() {
    if (_mesSeleccionado != null) return _nombreMes(_mesSeleccionado!);
    switch (_mesesSeleccionados) {
      case 1:
        return context.t('stat_this_month');
      case 3:
        return context.t('stat_last_3_months');
      case 6:
        return context.t('stat_last_6_months');
      case 12:
        return context.t('stat_last_year');
      default:
        return '';
    }
  }

  /// Etiqueta del período REALMENTE cargado en los datos. Se deriva de
  /// `datos.meses` y no del selector: si el usuario cambia de vista o la
  /// carga se cachea, el encabezado nunca puede decir "trimestral" mientras
  /// las cifras son de un solo mes (el bug que ocultaba octubre).
  String _labelPeriodoDatos(_DatosEstadisticas datos) {
    if (datos.meses.isEmpty) return '';
    if (datos.meses.length == 1) return _nombreMes(datos.meses.first);
    return '${_nombreMes(datos.meses.first)} - ${_nombreMes(datos.meses.last)}';
  }

  // ─────────────────────────────────────────────────────────
  // BUILD
  // ─────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // ── Selector de período ──────────────────────────────
        Container(
          color: Colors.white,
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                context.t('stat_title_org'),
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: _morado,
                ),
              ),
              Text(
                context.t('stat_title_report'),
                style: TextStyle(fontSize: 11, color: Colors.grey),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  _periodoBtn(
                    _mesSeleccionado != null
                        ? _nombreMes(_mesSeleccionado!)
                        : context.t('stat_period_monthly'),
                    1,
                    onTap: _abrirSelectorMes,
                    mostrarFlecha: true,
                  ),
                  const SizedBox(width: 8),
                  _periodoBtn(context.t('stat_period_quarterly'), 3),
                  const SizedBox(width: 8),
                  _periodoBtn(context.t('stat_period_semiannual'), 6),
                  const SizedBox(width: 8),
                  _periodoBtn(context.t('stat_period_annual'), 12),
                ],
              ),
            ],
          ),
        ),

        // ── Contenido ───────────────────────────────────────
        Expanded(
          child: _buildContenido(),
        ),
      ],
    );
  }

  Widget _periodoBtn(
    String label,
    int meses, {
    VoidCallback? onTap,
    bool mostrarFlecha = false,
  }) {
    final activo = _mesesSeleccionados == meses;
    return Expanded(
      child: GestureDetector(
        onTap: onTap ??
            () => setState(() {
                  _mesesSeleccionados = meses;
                  _mesSeleccionado = null;
                }),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
          decoration: BoxDecoration(
            color: activo ? _morado : Colors.grey.shade100,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Flexible(
                child: Text(
                  label,
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: activo ? Colors.white : Colors.grey,
                  ),
                ),
              ),
              if (mostrarFlecha)
                Icon(
                  Icons.arrow_drop_down,
                  size: 16,
                  color: activo ? Colors.white : Colors.grey,
                ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _abrirSelectorMes() async {
    final mesActual = _claveMes(DateTime.now());
    final cerrados = _mesesCerradosDisponibles();

    // Aún no hay meses cerrados: solo se puede ver el mes actual.
    if (cerrados.isEmpty) {
      setState(() {
        _mesesSeleccionados = 1;
        _mesSeleccionado = null;
      });
      return;
    }

    final sel = await showModalBottomSheet<String>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Text(
                'Ver estadísticas de un mes',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  color: _morado,
                ),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.calendar_today),
              title: const Text('Mes actual'),
              subtitle: Text(_nombreMes(mesActual)),
              selected: _mesSeleccionado == null,
              onTap: () => Navigator.pop(ctx, mesActual),
            ),
            const Divider(height: 1),
            for (final m in cerrados)
              ListTile(
                leading: const Icon(Icons.event_note),
                title: Text(_nombreMes(m)),
                selected: _mesSeleccionado == m,
                trailing:
                    _mesSeleccionado == m ? const Icon(Icons.check) : null,
                onTap: () => Navigator.pop(ctx, m),
              ),
          ],
        ),
      ),
    );

    if (sel == null) return;
    setState(() {
      _mesesSeleccionados = 1;
      // Elegir el mes actual equivale al modo por defecto.
      _mesSeleccionado = sel == _claveMes(DateTime.now()) ? null : sel;
    });
  }

  // ─────────────────────────────────────────────────────────
  // CONTENIDO PRINCIPAL
  // ─────────────────────────────────────────────────────────

  Widget _buildContenido() {
    final meses = _getMesesPeriodo();
    final key = meses.join(',');
    if (key != _datosFutureKey) {
      _datosFutureKey = key;
      _datosFuture = _cargarDatos(meses);
    }

    return FutureBuilder<_DatosEstadisticas>(
      future: _datosFuture,
      builder: (context, snap) {
        if (!snap.hasData) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                CircularProgressIndicator(color: _morado),
                SizedBox(height: 12),
                Text(context.t('stat_loading'),
                    style: TextStyle(color: Colors.grey)),
              ],
            ),
          );
        }

        final datos = snap.data!;

        return SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Resumen global ───────────────────────────
              _seccionTitulo(
                  context.t('stat_section_global_summary'),
                  _labelPeriodoDatos(datos)),
              const SizedBox(height: 12),
              _buildResumenGlobal(datos),
              const SizedBox(height: 12),
              _buildCreditosCrecimiento(datos),
              const SizedBox(height: 20),

              // ── Gráfico de barras mensual ────────────────
              if (_mesesSeleccionados > 1) ...[
                _seccionTitulo(context.t('stat_section_monthly_progress'), ''),
                const SizedBox(height: 12),
                _buildGraficoBarras(datos),
                const SizedBox(height: 20),
              ],

              // ── Distribución del directorio ─────────────
              _seccionTitulo(context.t('stat_pdf_address_distribution'),
                  _labelPeriodoDatos(datos)),
              const SizedBox(height: 20),

              // ── Gráfico de torta ────────────────────────
              _buildGraficoTorta(datos),
              const SizedBox(height: 20),

              // ── Campañas ─────────────────────────────────
              _seccionTitulo(context.t('stat_section_campanas'),
                  _labelPeriodoDatos(datos)),
              const SizedBox(height: 12),
              _buildSeccionCampanas(datos),
              const SizedBox(height: 20),

              // ── Por territorio ──────────────────────────
              _seccionTitulo(context.t('stat_section_by_territory'), ''),
              const SizedBox(height: 12),
              ...datos.porTerritorio.entries
                  .map((e) => _buildTarjetaTerritorio(e.key, e.value, datos)),
              const SizedBox(height: 20),

              // ── Progreso de territorio: se predicó (sección extra) ──
              _seccionTitulo(context.t('ses_section_title'), ''),
              const SizedBox(height: 12),
              const SeccionProgresoTerritorios(),
              const SizedBox(height: 20),

              // ── Botón exportar ──────────────────────────
              _buildBotonExportar(datos),
              const SizedBox(height: 20),
            ],
          ),
        );
      },
    );
  }

  // ─────────────────────────────────────────────────────────
  // CARGAR DATOS
  // ─────────────────────────────────────────────────────────

  Future<_DatosEstadisticas> _cargarDatos(List<String> meses) async {
    final db = FirebaseFirestore.instance;

    // Todas las direcciones globales
    final dirsSnap = await db.collection('direcciones_globales').get();
    final dirs = dirsSnap.docs;

    // Removidas
    final removidasSnap = await db.collection('direcciones_removidas').get();

    // Territorios
    final terSnap = await db.collection('territorios').get();

    // Rango extendido de movimiento: desde el primer mes del período
    // seleccionado hasta el mes actual. Para un mes cerrado (p. ej. octubre
    // visto en noviembre) el piso hay que rebajarlo con TODO lo que entró y
    // salió desde entonces, no solo dentro del mes; si no, el "piso inicial"
    // sería el cierre del mes y no su arranque, y el "total" mostraría el
    // directorio de hoy junto a un piso de otro fecha.
    final mesActualClave = _claveMes(DateTime.now());
    final mesesMovimiento = <String>[];
    {
      final p = meses.first.split('-');
      var d = DateTime(int.parse(p[0]), int.parse(p[1]), 1);
      while (mesesMovimiento.length < 240) {
        final clave = _claveMes(d);
        mesesMovimiento.add(clave);
        if (clave == mesActualClave) break;
        d = DateTime(d.year, d.month + 1, 1);
      }
    }

    // Estadísticas mensuales guardadas (por mes del rango extendido)
    final statsFutures = mesesMovimiento.map(
        (mes) => db.collection('estadisticas').doc('removidas_$mes').get());
    final statsSnaps = await Future.wait(statsFutures);

    // Totales globales: el total considera TODO el directorio global.
    // Sólo se descartan las removidas, que viven en direcciones_removidas
    // y ya no pertenecen al directorio.
    final totalActivas = dirs.where((d) {
      final data = (d.data() as Map<String, dynamic>?) ?? {};
      return data['estado'] != 'removida';
    }).length;

    // El piso ya no se calcula acá: se DERIVA del movimiento real después de
    // armar los mapas por mes (ver `pisoInicial` más abajo). La foto guardada
    // (`cierre_ultimo`) quedaba congelada en la última apertura de la pestaña
    // y cualquier salida sin registro mensual (p. ej. la limpieza de
    // noviembre de 2026) la dejaba inflada: el período mostraba crecimiento
    // negativo aunque el mes hubiera sumado direcciones.
    final pisoDoc = await db.collection('configuracion').doc('estadisticas').get();
    final pisoData = pisoDoc.data() ?? {};

    final totalRemovidas = removidasSnap.docs.length;

    // Datos por mes para gráfico
    final Map<String, int> predicadasPorMes = {};
    for (final mes in meses) {
      predicadasPorMes[mes] = dirs.where((d) {
        final data = (d.data() as Map<String, dynamic>?) ?? {};
        return data['predicado'] == true && data['mes_predicacion'] == mes;
      }).length;
    }

    // Nuevas direcciones por mes (ingresos a direcciones_globales).
    // `creado_el` se usa preferentemente; si falta, se usa `created_at`
    // siempre que NO sea una restauración (las restauradas traen
    // `restaurada_en` y no deben contarse como nuevas).
    final Map<String, int> nuevasPorMes = {};
    for (final mes in mesesMovimiento) {
      nuevasPorMes[mes] = dirs.where((d) {
        final data = (d.data() as Map<String, dynamic>?) ?? {};
        final ts = (data['creado_el'] ?? data['created_at']) as Timestamp?;
        if (ts == null) return false;
        final fecha = ts.toDate();
        if (data['restaurada_en'] != null) return false;
        return '${fecha.year}-${fecha.month.toString().padLeft(2, '0')}' ==
            mes;
      }).length;
    }

    // Altas que ya salieron del directorio: si una dirección se creó y se
    // removió dentro del período, en `direcciones_globales` ya no está y sin
    // esto desaparecería de "Nuevas". La copia en `direcciones_removidas`
    // conserva su fecha de creación cuando el motivo la guardó.
    final idsVivos = dirs.map((d) => d.id).toSet();
    for (final d in removidasSnap.docs) {
      if (idsVivos.contains(d.id)) continue;
      final data = (d.data() as Map<String, dynamic>?) ?? {};
      final ts = (data['creado_el'] ?? data['created_at']) as Timestamp?;
      if (ts == null) continue;
      final fecha = ts.toDate();
      final mes = '${fecha.year}-${fecha.month.toString().padLeft(2, '0')}';
      if (!mesesMovimiento.contains(mes)) continue;
      nuevasPorMes[mes] = (nuevasPorMes[mes] ?? 0) + 1;
    }

    // Overrides del auditor: cuando la importación inicial no tiene
    // `creado_el` (septiembre 2026), el conteo automático confunde altas con
    // el backfill. `nuevas_manual_$mes` reemplaza el mes completo y alimenta
    // igual los totales y la derivación del piso.
    for (final mes in mesesMovimiento) {
      final manual = (pisoData['nuevas_manual_$mes'] as num?)?.toInt();
      if (manual != null) nuevasPorMes[mes] = manual;
    }

    // Removidas por mes (fecha de remoción en direcciones_removidas).
    final Map<String, int> removidasPorMes = {};
    for (final mes in mesesMovimiento) {
      removidasPorMes[mes] = removidasSnap.docs.where((d) {
        final data = (d.data() as Map<String, dynamic>?) ?? {};
        final ts = data['removida_en'] as Timestamp?;
        if (ts == null) return false;
        final fecha = ts.toDate();
        return '${fecha.year}-${fecha.month.toString().padLeft(2, '0')}' ==
            mes;
      }).length;
    }

    // Restauradas / eliminadas permanentes por mes (estadisticas/removidas_$mes).
    final Map<String, int> restauradasPorMes = {};
    final Map<String, int> eliminadasPorMes = {};
    for (final snap in statsSnaps) {
      if (snap.exists) {
        final data = snap.data() ?? {};
        final mes = data['mes']?.toString() ?? snap.id.replaceAll('removidas_', '');
        restauradasPorMes[mes] = ((data['restauradas'] ?? 0) as num).toInt();
        eliminadasPorMes[mes] =
            ((data['eliminadas_permanente'] ?? 0) as num).toInt();
      }
    }

    // Ajuste manual de restauradas: el contador mensual puede incluir
    // restauraciones de la carga inicial (septiembre 2026) que ya están
    // contempladas en el piso y en las altas manuales. Sin este ajuste el
    // cierre del trimestre superaba el directorio real (212 vs 210).
    for (final mes in mesesMovimiento) {
      final manual = (pisoData['restauradas_manual_$mes'] as num?)?.toInt();
      if (manual != null) restauradasPorMes[mes] = manual;
    }

    // Totales del PERÍODO mostrado (solo los meses seleccionados): alimentan
    // las tarjetas "Nuevas/Restauradas/Removidas/Eliminadas" y el cierre.
    int nuevasPeriodoTotal = 0;
    int removidasPeriodoTotal = 0;
    int restauradasPeriodoTotal = 0;
    int eliminadasPeriodoTotal = 0;
    for (final mes in meses) {
      nuevasPeriodoTotal += nuevasPorMes[mes] ?? 0;
      removidasPeriodoTotal += removidasPorMes[mes] ?? 0;
      restauradasPeriodoTotal += restauradasPorMes[mes] ?? 0;
      eliminadasPeriodoTotal += eliminadasPorMes[mes] ?? 0;
    }

    // Piso inicial y cierre del período, derivados del movimiento real:
    //   piso   = total de hoy − altas − restauradas + bajas DESDE el arranque
    //            del período hasta hoy (rango extendido);
    //   cierre = piso + movimiento del período.
    //
    // Así la pareja que se muestra es coherente en el tiempo: para un mes
    // cerrado, "piso inicial" es el directorio al 1º de ese mes y "cierre del
    // período" es el directorio al terminar ese mes, no el de hoy. Si el
    // período incluye el mes actual, cierre == total de hoy. Las salidas sin
    // registro mensual (limpiezas directas) quedan absorbidas por el piso:
    // existían antes de que el período empezara.
    int nuevasMovTotal = 0;
    int removidasMovTotal = 0;
    int restauradasMovTotal = 0;
    for (final mes in mesesMovimiento) {
      nuevasMovTotal += nuevasPorMes[mes] ?? 0;
      removidasMovTotal += removidasPorMes[mes] ?? 0;
      restauradasMovTotal += restauradasPorMes[mes] ?? 0;
    }
    final int pisoDerivado = (totalActivas -
            nuevasMovTotal -
            restauradasMovTotal +
            removidasMovTotal)
        .clamp(0, totalActivas);

    // Ajuste manual del auditor (lápiz en la tarjeta de crecimiento). Se
    // guarda por mes de INICIO del período para no pisar otros períodos.
    final int pisoInicial = (pisoData['piso_manual_${meses.first}'] as num?)
            ?.toInt() ??
        pisoDerivado;
    final int cierrePeriodo = pisoInicial +
        nuevasPeriodoTotal +
        restauradasPeriodoTotal -
        removidasPeriodoTotal;

    // Cobertura: las direcciones completadas son un estado ACUMULADO del
    // directorio, no un movimiento del mes. Se cuentan las predicadas que
    // seguían en el directorio al cierre (sin mes de predicación = se
    // completaron en la carga inicial).
    final int completadasCierre = dirs.where((d) {
      final data = (d.data() as Map<String, dynamic>?) ?? {};
      if (data['estado'] == 'removida' || data['predicado'] != true) {
        return false;
      }
      final mes = data['mes_predicacion']?.toString();
      return mes == null || mes.compareTo(meses.last) <= 0;
    }).length.clamp(0, cierrePeriodo).toInt();

    // Por territorio
    final Map<String, _DatosTerritorio> porTerritorio = {};
    for (final ter in terSnap.docs) {
      final terData = (ter.data() as Map<String, dynamic>?) ?? {};
      // Los territorios BASE solo almacenan direcciones en el directorio
      // global; no se cuentan en las estadísticas.
      if (terData['tipo'] == 'base') continue;
      final terNombre = terData['nombre']?.toString() ?? ter.id;

      final dirsTer = dirs.where((d) {
        final data = (d.data() as Map<String, dynamic>?) ?? {};
        return data['territorio_id'] == ter.id ||
            data['barrio'] == ter.id ||
            data['barrio'] == terNombre ||
            data['territorio_nombre'] == terNombre;
      }).toList();

      // Completadas acumuladas: mismo criterio que el total global, para que
      // la suma de los territorios cierre con la cobertura del informe.
      final completadasTer = dirsTer.where((d) {
        final data = (d.data() as Map<String, dynamic>?) ?? {};
        if (data['estado'] == 'removida' || data['predicado'] != true) {
          return false;
        }
        final mes = data['mes_predicacion']?.toString();
        return mes == null || mes.compareTo(meses.last) <= 0;
      }).length;

      final removidasTer = removidasSnap.docs.where((d) {
        final data = (d.data() as Map<String, dynamic>?) ?? {};
        return data['territorio_id'] == ter.id ||
            data['territorio_nombre'] == terNombre;
      }).length;

      // Tarjetas del territorio
      final tarjSnap = await db
          .collection('territorios')
          .doc(ter.id)
          .collection('tarjetas')
          .get();
      final totalTarjetas = tarjSnap.docs.length;
      final tarjetasCompletadas = tarjSnap.docs.where((t) {
        final td = (t.data() as Map<String, dynamic>?) ?? {};
        return td['completada'] == true;
      }).length;

      porTerritorio[terNombre] = _DatosTerritorio(
        totalDirecciones: dirsTer.length,
        completadas: completadasTer,
        removidas: removidasTer,
        totalTarjetas: totalTarjetas,
        tarjetasCompletadas: tarjetasCompletadas,
      );
    }

    // Orden estable por volumen: la tabla del informe se lee de mayor a menor
    // en vez del orden arbitrario en que Firestore devuelve los territorios.
    final porTerritorioOrdenado = Map<String, _DatosTerritorio>.fromEntries(
      porTerritorio.entries.toList()
        ..sort((a, b) {
          final porDir =
              b.value.totalDirecciones.compareTo(a.value.totalDirecciones);
          return porDir != 0 ? porDir : a.key.compareTo(b.key);
        }),
    );

    // ── Estadísticas de campañas ───────────────────────────────────
    // El alcance de una campaña NO es el directorio de hoy: se compone de las
    // direcciones que la campaña registró. `completadas` sale de las marcas
    // por campaña (`campana_invitacion_{nombre}` y el estado genérico
    // `campana_estado` de esa misma campaña); `pendientes` sale de la foto
    // que deja `_cerrarCampana` (`total_faltantes`) o de la carpeta mientras
    // la campaña siga activa. Usar `dirs.length` hacía que una campaña de
    // septiembre midiera contra el directorio de noviembre (210).
    final List<_DatosCampana> campanas = [];
    for (final slot in ['campana_1', 'campana_2']) {
      try {
        final campDoc = await db.collection('configuracion').doc(slot).get();
        if (!campDoc.exists) continue;
        final cd = campDoc.data() ?? {};
        final nombre = (cd['nombre'] as String?) ?? slot;
        final activa = (cd['activa'] as bool?) ?? false;
        final fechaInicio = (cd['fecha_inicio'] as Timestamp?)?.toDate();
        final fechaFin = (cd['fecha_fin'] as Timestamp?)?.toDate();
        final etiqueta =
            (cd['etiqueta_entrega'] as String?)?.trim().isNotEmpty == true
                ? (cd['etiqueta_entrega'] as String).trim()
                : 'material entregado';

        // Marcas de entrega de ESTA campaña. Se descartan las anteriores al
        // inicio del período y, en campañas nuevas (`iniciada_en`), las marcas
        // sin fecha, que solo pueden venir de una campaña homónima anterior.
        var entregadas = dirs.where((d) {
          final dd = (d.data() as Map<String, dynamic>?) ?? {};
          return CampanasUtils.esEntregaDeCampana(
            dd,
            nombre,
            desde: fechaInicio,
            exigirFecha: cd['iniciada_en'] != null,
          );
        }).length;

        // Pendientes al cierre. La campaña cerrada guarda su foto en
        // `estadisticas/campana_{nombre}_{mes}` y borra la carpeta; la activa
        // todavía tiene la carpeta con la lista viva.
        var pendientes = 0;
        var hayCierre = false;
        if (!activa) {
          for (final mes in _mesesCierreCampana(fechaInicio, fechaFin)) {
            final snap = await db
                .collection('estadisticas')
                .doc('campana_${nombre}_$mes')
                .get();
            if (!snap.exists) continue;
            final sd = snap.data() ?? {};
            pendientes = (sd['total_faltantes'] as num?)?.toInt() ?? 0;
            // La foto es el registro histórico: si las marcas por dirección
            // se perdieron después del cierre, sigue diciendo cuántas se
            // entregaron. Se toma el mayor para no pisar marcas más nuevas.
            final enFoto =
                (sd['total_invitaciones_dejadas'] as num?)?.toInt() ?? 0;
            if (enFoto > entregadas) entregadas = enFoto;
            hayCierre = true;
          }
        }
        if (activa || !hayCierre) {
          final campId = CampanasUtils.idColeccionCampana(nombre);
          if (campId.isNotEmpty) {
            final carpeta = await db
                .collection('territorios')
                .doc('campanas')
                .collection(campId)
                .get();
            pendientes = carpeta.docs.where((d) {
              final dd = (d.data() as Map<String, dynamic>?) ?? {};
              return dd['estado_campana'] != 'completada';
            }).length;
          }
        }

        // Base y completadas de campañas que no tienen registro por dirección.
        // Se cargan acá (estático) en lugar de escribir datos inventados en
        // Firestore; `mesInicio` impide que una campaña futura con el mismo
        // nombre herede estas cifras.
        final historico = _datosHistoricosCampana[_claveCampana(nombre)];
        final aplicaHistorico = historico != null &&
            fechaInicio != null &&
            _claveMes(fechaInicio) == historico.mesInicio;

        var totalDirecciones = entregadas + pendientes;

        // Base congelada al crear la campaña: manda sobre el alcance
        // reconstruido para que el denominador no cambie si el directorio
        // crece o se depura durante el período.
        final baseGuardada = (cd['base_direcciones'] as num?)?.toInt();
        if (baseGuardada != null) {
          totalDirecciones =
              baseGuardada > entregadas ? baseGuardada : entregadas;
          pendientes = totalDirecciones - entregadas;
        }

        if (historico != null && aplicaHistorico) {
          final completadas = historico.completadas ?? entregadas;
          entregadas =
              completadas > historico.total ? historico.total : completadas;
          totalDirecciones = historico.total;
          pendientes = totalDirecciones - entregadas;
        }

        // Campaña cerrada con pendientes pero sin una sola marca de entrega:
        // la app nunca guardó esas entregas. Mostrar "0 de N" afirmaría que no
        // hubo trabajo; el informe muestra las direcciones trabajadas y avisa
        // que las entregas no están registradas.
        final sinRegistro =
            !aplicaHistorico && !activa && entregadas == 0 && pendientes > 0;

        campanas.add(_DatosCampana(
          slot: slot,
          nombre: nombre,
          activa: activa,
          fechaInicio: fechaInicio,
          fechaFin: fechaFin,
          totalDirecciones: totalDirecciones,
          completadas: entregadas,
          etiqueta: etiqueta,
          sinRegistro: sinRegistro,
        ));
      } catch (_) {
        // Si el doc no existe, no hay campaña en ese slot.
      }
    }

    return _DatosEstadisticas(
      totalActivas: totalActivas,
      cierrePeriodo: cierrePeriodo,
      pisoInicial: pisoInicial,
      completadasCierre: completadasCierre,
      totalRemovidas: totalRemovidas,
      predicadasPorMes: predicadasPorMes,
      meses: meses,
      porTerritorio: porTerritorioOrdenado,
      nuevasPeriodo: nuevasPeriodoTotal,
      removidasPeriodo: removidasPeriodoTotal,
      restauradasPeriodo: restauradasPeriodoTotal,
      eliminadasPeriodo: eliminadasPeriodoTotal,
      nuevasPorMes: nuevasPorMes,
      removidasPorMes: removidasPorMes,
      restauradasPorMes: restauradasPorMes,
      eliminadasPorMes: eliminadasPorMes,
      totalTerritorios: terSnap.docs.where((d) {
        final dd = (d.data() as Map<String, dynamic>?) ?? {};
        return dd['tipo'] != 'base';
      }).length,
      campanas: campanas,
    );
  }

  // ─────────────────────────────────────────────────────────
  // WIDGETS DE ESTADÍSTICAS
  // ─────────────────────────────────────────────────────────

  Widget _seccionTitulo(String titulo, String subtitulo) {
    return Row(
      children: [
        Container(
          width: 4,
          height: 16,
          decoration: BoxDecoration(
            color: _morado,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          titulo,
          style: const TextStyle(
            fontSize: 11,
            letterSpacing: 1.2,
            fontWeight: FontWeight.w700,
            color: _morado,
          ),
        ),
        if (subtitulo.isNotEmpty) ...[
          const SizedBox(width: 8),
          Text(
            subtitulo,
            style: TextStyle(fontSize: 11, color: Colors.grey[500]),
          ),
        ],
      ],
    );
  }

  Widget _buildResumenGlobal(_DatosEstadisticas datos) {
    final porcentaje = datos.cobertura;
    final incluyeMesActual =
        datos.meses.contains(_claveMes(DateTime.now()));
    final etiquetaDirecciones = incluyeMesActual
        ? context.t('stat_total_addresses')
        : context.t('stat_addresses_at_close');

    return Column(
      children: [
        // Barra de progreso grande
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF4A148C), Color(0xFF7B1FA2)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    context.t('stat_prediction_progress'),
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                    ),
                  ),
                  Text(
                    '${porcentaje.toStringAsFixed(1)}%',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 22,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: LinearProgressIndicator(
                  value: porcentaje / 100,
                  minHeight: 12,
                  backgroundColor: Colors.white.withOpacity(0.2),
                  valueColor: const AlwaysStoppedAnimation<Color>(Colors.white),
                ),
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '${datos.completadasCierre} ${context.t('stat_completed').toLowerCase()}',
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.85),
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    '${datos.pendientesCierre} '
                    '${context.t('stat_pending').toLowerCase()}',
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.85),
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                context.t('stat_coverage_hint',
                    args: ['${datos.cierrePeriodo}']),
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white.withOpacity(0.65),
                  fontSize: 10,
                  height: 1.3,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),

        Row(
          children: [
            Expanded(
              child: _metricaCard(
                '${datos.cierrePeriodo}',
                etiquetaDirecciones,
                Icons.home_work_outlined,
                Colors.blue,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _metricaCard(
                '${datos.completadasCierre}',
                context.t('stat_completed'),
                Icons.check_circle_outline,
                _verde,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: _metricaCard(
                '${datos.pendientesCierre}',
                context.t('stat_pending'),
                Icons.schedule,
                Colors.orange,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _metricaCard(
                '${datos.totalTerritorios}',
                context.t('stat_territories'),
                Icons.map,
                _morado,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _metricaCard(String valor, String label, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: color.withOpacity(0.08),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(height: 4),
          Text(
            valor,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          Text(
            label,
            style: TextStyle(fontSize: 9, color: Colors.grey[600]),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────
  // CRECIMIENTO DEL PERÍODO (nuevas vs removidas vs restauradas)
  // ─────────────────────────────────────────────────────────

  Widget _buildCreditosCrecimiento(_DatosEstadisticas datos) {
    final pct = datos.crecimientoPorcentaje;
    final positivo = pct >= 0;
    // Si el período es un mes cerrado, el segundo número no es el total de
    // hoy sino el cierre de ese mes; la etiqueta lo dice.
    final incluyeMesActual =
        datos.meses.contains(_claveMes(DateTime.now()));

    const colorAzul = Colors.blue;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: _morado.withOpacity(0.06),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
        border: Border.all(color: _morado.withOpacity(0.15)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                positivo ? Icons.trending_up : Icons.trending_down,
                color: positivo ? _verde : Colors.red,
                size: 20,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  context.t('stat_growth_period'),
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                    color: Color(0xFF263238),
                  ),
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: (positivo ? _verde : Colors.red).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  '${positivo ? '+' : ''}${pct.toStringAsFixed(1)}%',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                    color: positivo ? _verde : Colors.red,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // ── Piso inicial │ Total del período (o de hoy si el mes está abierto)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.grey.shade50,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.grey.shade200),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    '${context.t('stat_initial_floor')}: ${datos.pisoInicial}',
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Colors.grey[700]),
                  ),
                ),
                Container(
                  width: 1,
                  height: 24,
                  color: Colors.grey.shade300,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    '${incluyeMesActual ? context.t('stat_total_now') : context.t('stat_total_periodo')}: ${datos.cierrePeriodo}',
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: _verde),
                  ),
                ),
                const SizedBox(width: 8),
                InkWell(
                  onTap: () => _editarPisoInicial(datos),
                  borderRadius: BorderRadius.circular(20),
                  child: Padding(
                    padding: const EdgeInsets.all(4),
                    child: Icon(Icons.edit, size: 18, color: _morado),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _miniCrecimiento(
                  '${datos.nuevasPeriodo}',
                  context.t('stat_new_addresses'),
                  colorAzul,
                  Icons.add_home_work,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _miniCrecimiento(
                  '${datos.restauradasPeriodo}',
                  context.t('stat_restored'),
                  _verde,
                  Icons.restore,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _miniCrecimiento(
                  '${datos.removidasPeriodo}',
                  context.t('stat_removed'),
                  Colors.red,
                  Icons.person_off,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _miniCrecimiento(
                  '${datos.eliminadasPeriodo}',
                  context.t('stat_permanently_deleted'),
                  Colors.deepOrange,
                  Icons.delete_forever,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _editarPisoInicial(_DatosEstadisticas datos) async {
    final ctrl =
        TextEditingController(text: '${datos.pisoInicial}');
    final nuevo = await showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(context.t('stat_edit_floor')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: ctrl,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: context.t('stat_initial_floor'),
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              context.t('stat_edit_floor_hint'),
              style: TextStyle(fontSize: 11, color: Colors.grey[600]),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(context.t('cancel')),
          ),
          FilledButton(
            onPressed: () {
              final valor = int.tryParse(ctrl.text.trim());
              Navigator.pop(ctx, valor);
            },
            child: Text(context.t('save')),
          ),
        ],
      ),
    );

    if (nuevo == null || nuevo <= 0 || nuevo == datos.pisoInicial) return;

    try {
      await FirebaseFirestore.instance
          .collection('configuracion')
          .doc('estadisticas')
          .set({'piso_manual_${datos.meses.first}': nuevo},
              SetOptions(merge: true));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(context.t('stat_floor_saved')),
          backgroundColor: _verde,
        ));
        setState(() => _datosFutureKey = '');
      }
    } catch (e) {
      debugPrint('Error guardando piso inicial: $e');
    }
  }

  Widget _miniCrecimiento(
      String valor, String label, Color color, IconData icon) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.06),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(height: 4),
          Text(
            valor,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          Text(
            label,
            style: TextStyle(
                fontSize: 9, color: Colors.grey[600], height: 1.2),
            textAlign: TextAlign.center,
            maxLines: 2,
          ),
        ],
      ),
    );
  }

  Widget _buildGraficoBarras(_DatosEstadisticas datos) {
    final maxVal =
        datos.predicadasPorMes.values.fold<int>(0, (a, b) => a > b ? a : b) + 1;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            context.t('stat_addresses_by_month'),
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 13,
              color: Color(0xFF263238),
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 120,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: datos.meses.map((mes) {
                final val = datos.predicadasPorMes[mes] ?? 0;
                final altura = maxVal > 0 ? (val / maxVal) : 0.0;
                final esMesActual = mes ==
                    '${DateTime.now().year}-${DateTime.now().month.toString().padLeft(2, '0')}';

                return Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Text(
                      '$val',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: esMesActual ? _morado : Colors.grey,
                      ),
                    ),
                    const SizedBox(height: 4),
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 600),
                      width: 28,
                      height: (altura * 80).toDouble().clamp(4, 80),
                      decoration: BoxDecoration(
                        color: esMesActual ? _morado : _morado.withOpacity(0.3),
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _nombreMes(mes),
                      style: TextStyle(
                        fontSize: 9,
                        color: esMesActual ? _morado : Colors.grey,
                        fontWeight:
                            esMesActual ? FontWeight.bold : FontWeight.normal,
                      ),
                    ),
                  ],
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGraficoTorta(_DatosEstadisticas datos) {
    final total = datos.cierrePeriodo;
    if (total == 0) {
      return Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Center(
          child: Text(context.t('stat_no_data'),
              style: const TextStyle(color: Colors.grey)),
        ),
      );
    }

    final completadasPct = datos.cobertura / 100;
    final pendientesPct = datos.pendientesCierre / total;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          _barraDistribucion(context.t('stat_completed'),
              datos.completadasCierre, total, completadasPct, _verde),
          const SizedBox(height: 8),
          _barraDistribucion(context.t('stat_pending'),
              datos.pendientesCierre, total, pendientesPct, Colors.orange),
        ],
      ),
    );
  }

  Widget _barraDistribucion(
      String label, int valor, int total, double pct, Color color) {
    return Row(
      children: [
        SizedBox(
          width: 85,
          child: Text(
            label,
            style: TextStyle(fontSize: 11, color: Colors.grey[700]),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: pct.clamp(0.0, 1.0),
              minHeight: 12,
              backgroundColor: Colors.grey.shade100,
              valueColor: AlwaysStoppedAnimation<Color>(color),
            ),
          ),
        ),
        const SizedBox(width: 8),
        SizedBox(
          width: 55,
          child: Text(
            '$valor (${(pct * 100).toStringAsFixed(0)}%)',
            style: TextStyle(
              fontSize: 10,
              color: color,
              fontWeight: FontWeight.bold,
            ),
            textAlign: TextAlign.right,
            maxLines: 1,
          ),
        ),
      ],
    );
  }

  /// `true` si el rango [fechaInicio, fechaFin] de la campaña toca alguno de
  /// los meses del período mostrado. Un extremo nulo se trata como abierto
  /// (la campaña sigue vigente o no tiene inicio definido); si faltan ambas
  /// fechas, no hay forma de asignarle un mes y se muestra siempre.
  bool _campanaEnPeriodo(_DatosCampana c, List<String> meses) {
    if (meses.isEmpty) return true;
    if (c.fechaInicio == null && c.fechaFin == null) return true;
    final iniPartes = meses.first.split('-');
    final finPartes = meses.last.split('-');
    final periodoIni =
        DateTime(int.parse(iniPartes[0]), int.parse(iniPartes[1]), 1);
    // Primer día del mes siguiente: borde exclusivo, para no perder una
    // campaña que arranca el último día del mes a cualquier hora.
    final periodoFinExcl =
        DateTime(int.parse(finPartes[0]), int.parse(finPartes[1]) + 1, 1);
    if (c.fechaInicio != null && !c.fechaInicio!.isBefore(periodoFinExcl)) {
      return false;
    }
    if (c.fechaFin != null && c.fechaFin!.isBefore(periodoIni)) {
      return false;
    }
    return true;
  }

  Widget _buildSeccionCampanas(_DatosEstadisticas datos) {
    // Cada campaña aparece solo en los meses que abarca su rango de fechas:
    // una que corre de fines de octubre a principios de noviembre figura en
    // ambos meses y deja de figurar en diciembre. El progreso mostrado es el
    // acumulado de la campaña, no se corta por mes.
    final campanasPeriodo = datos.campanas
        .where((c) => _campanaEnPeriodo(c, datos.meses))
        .toList();

    if (campanasPeriodo.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Center(
          child: Text(
              datos.campanas.isEmpty
                  ? context.t('stat_no_campanas')
                  : context.t('stat_no_campanas_periodo'),
              style: TextStyle(color: Colors.grey, fontSize: 11)),
        ),
      );
    }

    return Column(
      children: [
        for (final c in campanasPeriodo)
          Container(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: c.activa ? _verde : Colors.grey,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        c.nombre,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                          color: Color(0xFF263238),
                        ),
                      ),
                    ),
                    Text(
                      c.activa
                          ? context.t('stat_campana_activa')
                          : context.t('stat_campana_inactiva'),
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        color: c.activa ? _verde : Colors.grey,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                // Rango de fechas
                Row(
                  children: [
                    Icon(Icons.event, size: 14, color: Colors.grey[600]),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        '${context.t('stat_period')}: '
                        '${_fmtFecha(c.fechaInicio)} - ${_fmtFecha(c.fechaFin)}',
                        style:
                            TextStyle(fontSize: 11, color: Colors.grey[600]),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                // Progreso
                if (c.sinRegistro)
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.orange.shade50,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.orange.shade200),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.info_outline,
                            size: 14, color: Colors.orange.shade800),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            '${c.totalDirecciones} '
                            '${context.t('stat_campana_trabajadas')} · '
                            '${context.t('stat_campana_sin_registro')}',
                            style: TextStyle(
                                fontSize: 10,
                                color: Colors.orange.shade900),
                          ),
                        ),
                      ],
                    ),
                  )
                else ...[
                  Row(
                    children: [
                      Expanded(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: LinearProgressIndicator(
                            value: (c.progreso / 100).clamp(0.0, 1.0),
                            minHeight: 10,
                            backgroundColor: Colors.grey.shade100,
                            valueColor: AlwaysStoppedAnimation<Color>(
                                c.activa ? _verde : Colors.orange),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        '${c.completadas}/${c.totalDirecciones} '
                        '(${c.progreso.toStringAsFixed(0)}%)',
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF263238),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '${c.completadas} de ${c.totalDirecciones} '
                    'con ${c.etiqueta} · ${c.pendientes} '
                    '${context.t('stat_campana_pendientes')}',
                    style: TextStyle(fontSize: 10, color: Colors.grey[600]),
                  ),
                ],
              ],
            ),
          ),
      ],
    );
  }

  String _fmtFecha(DateTime? fecha) {
    if (fecha == null) return '-';
    return '${fecha.day}/${fecha.month}/${fecha.year}';
  }

  Widget _buildTarjetaTerritorio(
      String nombre, _DatosTerritorio datos, _DatosEstadisticas global) {
    final porcentaje = datos.cobertura;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: _morado.withOpacity(0.06),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          // Header territorio
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: _morado.withOpacity(0.04),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(14),
                topRight: Radius.circular(14),
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: _morado.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.map, color: _morado, size: 18),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        nombre,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                          color: Color(0xFF263238),
                        ),
                      ),
                      Text(
                        context.t('stat_addr_count_cards', args: ['${datos.totalDirecciones}', '${datos.totalTarjetas}']),
                        style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                      ),
                    ],
                  ),
                ),
                // Porcentaje circular
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: porcentaje >= 80
                        ? _verde.withOpacity(0.1)
                        : porcentaje >= 50
                            ? Colors.orange.withOpacity(0.1)
                            : Colors.red.withOpacity(0.1),
                  ),
                  child: Center(
                    child: Text(
                      '${porcentaje.toStringAsFixed(0)}%',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: porcentaje >= 80
                            ? _verde
                            : porcentaje >= 50
                                ? Colors.orange
                                : Colors.red,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          // Barra progreso
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: porcentaje / 100,
                minHeight: 6,
                backgroundColor: Colors.grey.shade100,
                valueColor: AlwaysStoppedAnimation<Color>(
                  porcentaje >= 80
                      ? _verde
                      : porcentaje >= 50
                          ? Colors.orange
                          : Colors.red,
                ),
              ),
            ),
          ),
          // Métricas
          Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                _miniMetrica('${datos.completadas}',
                    context.t('stat_completed'), _verde),
                _miniMetrica('${datos.pendientes}',
                    context.t('stat_pending'), Colors.orange),
                _miniMetrica('${datos.removidas}', context.t('stat_removed'), Colors.red),
                _miniMetrica(
                    '${datos.tarjetasCompletadas}/${datos.totalTarjetas}',
                    context.t('stat_cards'),
                    _morado),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _miniMetrica(String valor, String label, Color color) {
    return Expanded(
      child: Column(
        children: [
          Text(
            valor,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          Text(
            label,
            style: TextStyle(fontSize: 9, color: Colors.grey[500]),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildBotonExportar(_DatosEstadisticas datos) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF1B5E20), Color(0xFF2E7D32)],
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.picture_as_pdf, color: Colors.white, size: 20),
              SizedBox(width: 8),
              Text(
                context.t('stat_export_report'),
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            context.t('stat_congregation_period', args: [_labelPeriodo()]),
            style: TextStyle(
              color: Colors.white.withOpacity(0.8),
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () => _exportarPDF(datos),
                  icon: const Icon(Icons.share, size: 16),
                  label: Text(context.t('stat_share_summary'),
                      style: TextStyle(fontSize: 12)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: _verde,
                    padding: const EdgeInsets.symmetric(vertical: 10),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────
  // EXPORTAR TEXTO
  // ─────────────────────────────────────────────────────────

  Future<void> _exportarPDF(_DatosEstadisticas datos) async {
    try {
      // Mostrar loading
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('📊 ${context.t('stat_generating_pdf')}'), duration: Duration(seconds: 30)),
      );

      final pdf = pw.Document();
      final ahora = DateTime.now();
      final periodoTexto = _labelPeriodoDatos(datos);
      final fechaGenerado =
          '${ahora.day.toString().padLeft(2, '0')}/${ahora.month.toString().padLeft(2, '0')}/${ahora.year}';

      // ── INFORME REDACTADO POR IA (Groq) ──────────────────
      String informeIA = '';
      try {
        informeIA = await GroqReporteService.generarInformeEjecutivo(
          resumen: {
            'periodo': periodoTexto,
            'meses_incluidos': datos.meses,
            'piso_inicial': datos.pisoInicial,
            'cierre_periodo': datos.cierrePeriodo,
            'direcciones_completadas': datos.completadasCierre,
            'direcciones_pendientes': datos.pendientesCierre,
            'cobertura_porcentaje': datos.cobertura.toStringAsFixed(1),
            'nuevas_periodo': datos.nuevasPeriodo,
            'removidas_periodo': datos.removidasPeriodo,
            'restauradas_periodo': datos.restauradasPeriodo,
            'eliminadas_permanente': datos.eliminadasPeriodo,
            'crecimiento_neto': datos.crecimientoNeto,
            'crecimiento_porcentaje': datos.crecimientoPorcentaje,
            'total_removidas_historico': datos.totalRemovidas,
            'total_territorios': datos.totalTerritorios,
          },
        );
      } catch (e) {
        debugPrint('Error generando informe IA: $e');
        informeIA = '';
      }

      // La fuente del PDF no trae guion largo ni comillas curvas: la IA a
      // veces los devuelve y se dibujaban como cuadros vacíos. Se normalizan
      // antes de armar el documento.
      informeIA = informeIA
          .replaceAll('\u2013', '-')
          .replaceAll('\u2014', '-')
          .replaceAll('\u2018', "'")
          .replaceAll('\u2019', "'")
          .replaceAll('\u201C', '"')
          .replaceAll('\u201D', '"')
          .replaceAll('\u2026', '...');

      // ── COLORES ──────────────────────────────────────────
      final colorVerde = PdfColor.fromHex('#1B5E20');
      final colorVerdeClaro = PdfColor.fromHex('#2E7D32');
      final colorMorado = PdfColor.fromHex('#4A148C');
      final colorGrisClaro = PdfColor.fromHex('#F5F5F5');
      final colorGrisMedio = PdfColor.fromHex('#E0E0E0');
      final colorBlanco = PdfColors.white;
      final colorTexto = PdfColor.fromHex('#212121');
      final colorTextoSuave = PdfColor.fromHex('#757575');
      final colorNaranja = PdfColor.fromHex('#E65100');
      final colorAzul = PdfColor.fromHex('#0277BD');

      // ── COHERENCIA TEMPORAL DEL PERÍODO ───────────────────
      // Si el período es un mes cerrado, el "total" del informe es el cierre
      // de ese mes, no el directorio de hoy; las etiquetas lo aclaran.
      final incluyeMesActual = datos.meses.contains(_claveMes(DateTime.now()));
      final etiquetaTotal = incluyeMesActual
          ? context.t('stat_total_now')
          : context.t('stat_total_periodo');

      // ── COBERTURA DEL PERÍODO ─────────────────────────────
      // Completadas acumuladas sobre el total de direcciones al cierre.
      final pct = datos.cobertura;

      // ── CAMPAÑAS DEL PERÍODO ──────────────────────────────
      // Mismo filtro que la pantalla: solo las campañas cuyo rango de fechas
      // toca los meses del informe. El progreso es el acumulado de cada una.
      final campanasPeriodo = datos.campanas
          .where((c) => _campanaEnPeriodo(c, datos.meses))
          .toList();

      // ── PÁGINA 1: RESUMEN EJECUTIVO ───────────────────────
      pdf.addPage(
        pw.Page(
          pageTheme: pw.PageTheme(
            pageFormat: PdfPageFormat.a4,
            margin: const pw.EdgeInsets.all(0),
          ),
          build: (pw.Context ctx) {
            return pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.stretch,
              children: [
                // Header
                pw.Container(
                  height: 120,
                  color: colorVerde,
                  padding: const pw.EdgeInsets.symmetric(horizontal: 40, vertical: 24),
                  child: pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    crossAxisAlignment: pw.CrossAxisAlignment.center,
                    children: [
                      pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        mainAxisAlignment: pw.MainAxisAlignment.center,
                        children: [
                          pw.Text('CONGREGACIÓN ESPAÑOLA',
                              style: pw.TextStyle(
                                  color: colorBlanco,
                                  fontSize: 10,
                                  letterSpacing: 2,
                                  fontWeight: pw.FontWeight.bold)),
                          pw.SizedBox(height: 4),
                          pw.Text('Araucária Sur',
                              style: pw.TextStyle(
                                  color: colorBlanco,
                                  fontSize: 26,
                                  fontWeight: pw.FontWeight.bold)),
                          pw.SizedBox(height: 4),
                          pw.Text('Informe de Estadísticas Territoriales',
                              style: pw.TextStyle(
                                  color: PdfColor.fromHex('#A5D6A7'),
                                  fontSize: 12)),
                        ],
                      ),
                      pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.end,
                        mainAxisAlignment: pw.MainAxisAlignment.center,
                        children: [
                          pw.Container(
                            padding: const pw.EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                            decoration: pw.BoxDecoration(
                              color: colorVerdeClaro,
                              borderRadius: pw.BorderRadius.circular(20),
                            ),
                            child: pw.Text('Período $periodoTexto',
                                style: pw.TextStyle(
                                    color: colorBlanco,
                                    fontSize: 11,
                                    fontWeight: pw.FontWeight.bold)),
                          ),
                          pw.SizedBox(height: 8),
                          pw.Text('Generado: $fechaGenerado',
                              style: pw.TextStyle(
                                  color: PdfColor.fromHex('#C8E6C9'),
                                  fontSize: 10)),
                        ],
                      ),
                    ],
                  ),
                ),

                // Contenido
                pw.Expanded(
                  child: pw.Padding(
                    padding: const pw.EdgeInsets.all(32),
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
                      children: [
                        // ── KPIs principales ──────────────────────────
                        pw.Text('RESUMEN DESCRIPTIVO',
                            style: pw.TextStyle(
                                fontSize: 11,
                                fontWeight: pw.FontWeight.bold,
                                color: colorTextoSuave,
                                letterSpacing: 1.5)),
                        pw.SizedBox(height: 12),
                        pw.Row(
                          children: [
                            _pdfKpi(
                                incluyeMesActual
                                    ? context.t('stat_total_addresses')
                                    : context.t('stat_addresses_at_close'),
                                '${datos.cierrePeriodo}',
                                colorMorado,
                                colorBlanco),
                            pw.SizedBox(width: 10),
                            _pdfKpi(context.t('stat_completed'),
                                '${datos.completadasCierre}', colorVerde, colorBlanco),
                            pw.SizedBox(width: 10),
                            _pdfKpi(context.t('stat_pending'),
                                '${datos.pendientesCierre}', colorNaranja, colorBlanco),
                            pw.SizedBox(width: 10),
                            _pdfKpi(context.t('stat_territories'),
                                '${datos.totalTerritorios}', colorAzul, colorBlanco),
                          ],
                        ),

                        pw.SizedBox(height: 24),

                        // ── Cobertura de predicación ───────────────────
                        pw.Text(context.t('stat_pdf_period_coverage').toUpperCase(),
                            style: pw.TextStyle(
                                fontSize: 11,
                                fontWeight: pw.FontWeight.bold,
                                color: colorTextoSuave,
                                letterSpacing: 1.5)),
                        pw.SizedBox(height: 10),
                        pw.Container(
                          padding: const pw.EdgeInsets.all(20),
                          decoration: pw.BoxDecoration(
                            color: colorGrisClaro,
                            borderRadius: pw.BorderRadius.circular(12),
                            border: pw.Border.all(color: colorGrisMedio),
                          ),
                          child: pw.Column(
                            crossAxisAlignment: pw.CrossAxisAlignment.start,
                            children: [
                              pw.Row(
                                mainAxisAlignment:
                                    pw.MainAxisAlignment.spaceBetween,
                                children: [
                                  pw.Text(
                                      '${context.t('stat_completed')} / ${context.t('stat_total_addresses').toLowerCase()}',
                                      style: pw.TextStyle(
                                          fontSize: 12, color: colorTexto)),
                                  pw.Text('${pct.toStringAsFixed(1)}%',
                                      style: pw.TextStyle(
                                          fontSize: 22,
                                          fontWeight: pw.FontWeight.bold,
                                          color: colorVerde)),
                                ],
                              ),
                              pw.SizedBox(height: 10),
                              pw.ClipRRect(
                                horizontalRadius: 4,
                                verticalRadius: 4,
                                child: pw.LinearProgressIndicator(
                                  value: pct / 100,
                                  backgroundColor: colorGrisMedio,
                                  valueColor: colorVerde,
                                  minHeight: 14,
                                ),
                              ),
                              pw.SizedBox(height: 8),
                              pw.Row(
                                mainAxisAlignment:
                                    pw.MainAxisAlignment.spaceBetween,
                                children: [
                                  pw.Text(
                                      '${datos.completadasCierre} ${context.t('stat_completed').toLowerCase()}',
                                      style: pw.TextStyle(
                                          fontSize: 10,
                                          color: colorVerde,
                                          fontWeight: pw.FontWeight.bold)),
                                  pw.Text(
                                      '${datos.pendientesCierre} ${context.t('stat_pending').toLowerCase()}',
                                      style: pw.TextStyle(
                                          fontSize: 10,
                                          color: colorNaranja,
                                          fontWeight: pw.FontWeight.bold)),
                                ],
                              ),
                              pw.SizedBox(height: 6),
                              pw.Text(
                                  context.t('stat_coverage_hint', args: [
                                    '${datos.cierrePeriodo}'
                                  ]),
                                  style: pw.TextStyle(
                                      fontSize: 8.5, color: colorTextoSuave)),
                            ],
                          ),
                        ),

                        pw.SizedBox(height: 22),

                        // ── Movimiento del período ─────────────────────
                        pw.Text('MOVIMIENTO DEL PERÍODO',
                            style: pw.TextStyle(
                                fontSize: 11,
                                fontWeight: pw.FontWeight.bold,
                                color: colorTextoSuave,
                                letterSpacing: 1.5)),
                        pw.SizedBox(height: 10),
                        pw.Row(
                          children: [
                            _pdfInfoCard(context.t('stat_new_addresses'),
                                '${datos.nuevasPeriodo}', colorAzul),
                            pw.SizedBox(width: 10),
                            _pdfInfoCard(context.t('stat_restored'),
                                '${datos.restauradasPeriodo}', colorVerde),
                            pw.SizedBox(width: 10),
                            _pdfInfoCard(context.t('stat_removed'),
                                '${datos.removidasPeriodo}', colorNaranja),
                            pw.SizedBox(width: 10),
                            _pdfInfoCard(
                                context.t('stat_permanently_deleted'),
                                '${datos.eliminadasPeriodo}',
                                PdfColor.fromHex('#B71C1C')),
                          ],
                        ),

                        pw.SizedBox(height: 18),

                        // ── Crecimiento del período ─────────────────────
                        pw.Container(
                          padding: const pw.EdgeInsets.all(16),
                          decoration: pw.BoxDecoration(
                            color: PdfColor.fromHex('#E8F5E9'),
                            borderRadius: pw.BorderRadius.circular(12),
                            border: pw.Border.all(color: colorVerde),
                          ),
                          child: pw.Row(
                            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                            crossAxisAlignment: pw.CrossAxisAlignment.center,
                            children: [
                              pw.Column(
                                crossAxisAlignment: pw.CrossAxisAlignment.start,
                                children: [
                                  pw.Text(context.t('stat_growth_period'),
                                      style: pw.TextStyle(
                                          fontSize: 11,
                                          fontWeight: pw.FontWeight.bold,
                                          color: colorVerde)),
                                  pw.SizedBox(height: 4),
                                  pw.Text(
                                    '${context.t('stat_initial_floor')} ${datos.pisoInicial} » $etiquetaTotal ${datos.cierrePeriodo}',
                                    style: pw.TextStyle(
                                        fontSize: 10,
                                        fontWeight: pw.FontWeight.bold,
                                        color: colorTexto),
                                  ),
                                  pw.SizedBox(height: 2),
                                  pw.Text(
                                    'Nuevas ${datos.nuevasPeriodo} · Restauradas ${datos.restauradasPeriodo} · Removidas ${datos.removidasPeriodo}',
                                    style: pw.TextStyle(
                                        fontSize: 9, color: colorTextoSuave),
                                  ),
                                ],
                              ),
                              pw.Text(
                                '${datos.crecimientoNeto >= 0 ? '+' : ''}${datos.crecimientoNeto} (${datos.crecimientoPorcentaje >= 0 ? '+' : ''}${datos.crecimientoPorcentaje.toStringAsFixed(1)}%)',
                                style: pw.TextStyle(
                                    fontSize: 18,
                                    fontWeight: pw.FontWeight.bold,
                                    color: datos.crecimientoNeto >= 0
                                        ? colorVerde
                                        : PdfColor.fromHex('#B71C1C')),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                // Footer
                pw.Container(
                  height: 36,
                  color: PdfColor.fromHex('#F9FBE7'),
                  padding: const pw.EdgeInsets.symmetric(horizontal: 40),
                  child: pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    crossAxisAlignment: pw.CrossAxisAlignment.center,
                    children: [
                      pw.Text('Congregación Española · Araucária Sur · Paraná, Brasil',
                          style: pw.TextStyle(fontSize: 8, color: colorTextoSuave)),
                      pw.Text('Página 1',
                          style: pw.TextStyle(fontSize: 8, color: colorTextoSuave)),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      );

      // ── PÁGINA 2: MOVIMIENTO MENSUAL ────────────────────
      pdf.addPage(
        pw.Page(
          pageTheme: pw.PageTheme(
            pageFormat: PdfPageFormat.a4,
            margin: const pw.EdgeInsets.all(0),
          ),
          build: (pw.Context ctx) {
            final maxMv = [
                  ...datos.nuevasPorMes.values,
                  ...datos.removidasPorMes.values,
                  ...datos.restauradasPorMes.values,
                ].fold<int>(0, (a, b) => a > b ? a : b) +
                1;

            // Fila por mes con el cierre acumulado: el piso del mes siguiente
            // es el cierre del anterior. Hace visible qué aportó cada mes,
            // incluido octubre cuando el período es trimestral.
            final filasMes = <List<String>>[];
            var pisoMes = datos.pisoInicial;
            for (final mes in datos.meses) {
              final n = datos.nuevasPorMes[mes] ?? 0;
              final r = datos.restauradasPorMes[mes] ?? 0;
              final x = datos.removidasPorMes[mes] ?? 0;
              final cierreMes = pisoMes + n + r - x;
              filasMes.add([
                _nombreMes(mes),
                '$pisoMes',
                '$n',
                '$r',
                '$x',
                '${datos.predicadasPorMes[mes] ?? 0}',
                '$cierreMes',
              ]);
              pisoMes = cierreMes;
            }

            return pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.stretch,
              children: [
                pw.Container(
                  height: 56,
                  color: colorVerde,
                  padding: const pw.EdgeInsets.symmetric(horizontal: 40),
                  child: pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    crossAxisAlignment: pw.CrossAxisAlignment.center,
                    children: [
                      pw.Text('MOVIMIENTO MENSUAL · $periodoTexto',
                          style: pw.TextStyle(
                              color: colorBlanco,
                              fontSize: 13,
                              fontWeight: pw.FontWeight.bold,
                              letterSpacing: 0.8)),
                      pw.Text(fechaGenerado,
                          style: pw.TextStyle(
                              color: PdfColor.fromHex('#C8E6C9'),
                              fontSize: 10)),
                    ],
                  ),
                ),
                pw.Expanded(
                  child: pw.Padding(
                    padding: const pw.EdgeInsets.all(32),
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
                      children: [
                        // Leyenda
                        pw.Row(
                          mainAxisAlignment: pw.MainAxisAlignment.center,
                          children: [
                            _pdfLeyenda(colorAzul, context.t('stat_new_addresses')),
                            pw.SizedBox(width: 16),
                            _pdfLeyenda(colorNaranja, context.t('stat_removed')),
                            pw.SizedBox(width: 16),
                            _pdfLeyenda(colorVerde, context.t('stat_restored')),
                          ],
                        ),
                        pw.SizedBox(height: 24),
                        // Barras agrupadas por mes: valor encima de cada barra
                        // (solo si es > 0), línea base y rótulos alineados.
                        pw.Expanded(
                          child: pw.Column(
                            children: [
                              pw.Expanded(
                                child: pw.Row(
                                  crossAxisAlignment: pw.CrossAxisAlignment.end,
                                  mainAxisAlignment: pw.MainAxisAlignment.spaceEvenly,
                                  children: datos.meses.map((mes) {
                                    final nuevas = datos.nuevasPorMes[mes] ?? 0;
                                    final removidas = datos.removidasPorMes[mes] ?? 0;
                                    final restauradas = datos.restauradasPorMes[mes] ?? 0;
                                    pw.Widget barra(int valor, double h, PdfColor color) {
                                      return pw.Column(
                                        mainAxisAlignment: pw.MainAxisAlignment.end,
                                        children: [
                                          if (valor > 0) ...[
                                            pw.Text('$valor',
                                                style: pw.TextStyle(
                                                    fontSize: 7.5,
                                                    fontWeight: pw.FontWeight.bold,
                                                    color: color)),
                                            pw.SizedBox(height: 2),
                                          ],
                                          pw.Container(
                                            width: 16,
                                            height: valor > 0
                                                ? (h * 100).clamp(4.0, 100.0)
                                                : 0.0,
                                            decoration: pw.BoxDecoration(
                                                color: color,
                                                borderRadius: pw.BorderRadius.vertical(
                                                    top: pw.Radius.circular(3))),
                                          ),
                                        ],
                                      );
                                    }

                                    return pw.Row(
                                      crossAxisAlignment: pw.CrossAxisAlignment.end,
                                      children: [
                                        barra(nuevas, maxMv > 0 ? nuevas / maxMv : 0.0, colorAzul),
                                        pw.SizedBox(width: 3),
                                        barra(removidas, maxMv > 0 ? removidas / maxMv : 0.0, colorNaranja),
                                        pw.SizedBox(width: 3),
                                        barra(restauradas, maxMv > 0 ? restauradas / maxMv : 0.0, colorVerde),
                                      ],
                                    );
                                  }).toList(),
                                ),
                              ),
                              // Línea base del gráfico.
                              pw.Container(height: 1.2, color: colorGrisMedio),
                              pw.SizedBox(height: 6),
                              pw.Row(
                                mainAxisAlignment: pw.MainAxisAlignment.spaceEvenly,
                                children: [
                                  for (final mes in datos.meses)
                                    pw.Expanded(
                                      child: pw.Text(
                                          _etiquetaMesCorta(mes),
                                          textAlign: pw.TextAlign.center,
                                          style: pw.TextStyle(
                                              fontSize: 9, color: colorTexto)),
                                    ),
                                ],
                              ),
                              pw.SizedBox(height: 12),
                              // Totales del período, para leer el mes sin sumar barras.
                              pw.Text(
                                  'Período: ${datos.nuevasPeriodo} altas · ${datos.removidasPeriodo} bajas · ${datos.restauradasPeriodo} restauradas · Neto ${datos.crecimientoNeto >= 0 ? '+' : ''}${datos.crecimientoNeto}',
                                  style: pw.TextStyle(
                                      fontSize: 9,
                                      fontWeight: pw.FontWeight.bold,
                                      color: colorTextoSuave)),
                              pw.SizedBox(height: 14),
                              // Detalle mensual: piso, movimiento y cierre.
                              pw.Table(
                                border: pw.TableBorder.all(
                                    color: colorGrisMedio, width: 0.6),
                                columnWidths: const {
                                  0: pw.FlexColumnWidth(2.2),
                                  1: pw.FlexColumnWidth(1),
                                  2: pw.FlexColumnWidth(1),
                                  3: pw.FlexColumnWidth(1),
                                  4: pw.FlexColumnWidth(1),
                                  5: pw.FlexColumnWidth(1),
                                  6: pw.FlexColumnWidth(1),
                                },
                                children: [
                                  pw.TableRow(
                                    decoration:
                                        pw.BoxDecoration(color: colorVerde),
                                    children: [
                                      for (final t in const [
                                        'MES',
                                        'PISO',
                                        'NUEVAS',
                                        'RESTAUR.',
                                        'REMOVIDAS',
                                        'COMPLET.',
                                        'CIERRE',
                                      ])
                                        pw.Padding(
                                          padding: const pw.EdgeInsets
                                              .symmetric(
                                                  vertical: 5, horizontal: 4),
                                          child: pw.Text(t,
                                              textAlign: t == 'MES'
                                                  ? pw.TextAlign.left
                                                  : pw.TextAlign.center,
                                              style: pw.TextStyle(
                                                  fontSize: 7.5,
                                                  fontWeight:
                                                      pw.FontWeight.bold,
                                                  color: colorBlanco,
                                                  letterSpacing: 0.4)),
                                        ),
                                    ],
                                  ),
                                  for (var i = 0; i < filasMes.length; i++)
                                    pw.TableRow(
                                      decoration: pw.BoxDecoration(
                                          color: i.isEven
                                              ? colorGrisClaro
                                              : colorBlanco),
                                      children: [
                                        for (var c = 0;
                                            c < filasMes[i].length;
                                            c++)
                                          pw.Padding(
                                            padding: const pw.EdgeInsets
                                                .symmetric(
                                                    vertical: 4.5,
                                                    horizontal: 4),
                                            child: pw.Text(filasMes[i][c],
                                                textAlign: c == 0
                                                    ? pw.TextAlign.left
                                                    : pw.TextAlign.center,
                                                style: pw.TextStyle(
                                                    fontSize: 8,
                                                    fontWeight: c == 0 ||
                                                            c == 6
                                                        ? pw.FontWeight.bold
                                                        : pw.FontWeight
                                                            .normal,
                                                    color: c == 6
                                                        ? colorVerde
                                                        : colorTexto)),
                                          ),
                                      ],
                                    ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        pw.SizedBox(height: 16),
                      ],
                    ),
                  ),
                ),
                pw.Container(
                  height: 36,
                  color: PdfColor.fromHex('#F9FBE7'),
                  padding: const pw.EdgeInsets.symmetric(horizontal: 40),
                  child: pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    crossAxisAlignment: pw.CrossAxisAlignment.center,
                    children: [
                      pw.Text('Congregación Española · Araucária Sur · Paraná, Brasil',
                          style: pw.TextStyle(fontSize: 8, color: colorTextoSuave)),
                      pw.Text('Página 2',
                          style: pw.TextStyle(fontSize: 8, color: colorTextoSuave)),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      );

      // ── PÁGINA 3: INFORME DESCRIPTIVO (IA) ──────────────
      pdf.addPage(
        pw.Page(
          pageTheme: pw.PageTheme(
            pageFormat: PdfPageFormat.a4,
            margin: const pw.EdgeInsets.all(0),
          ),
          build: (pw.Context ctx) {
            return pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.stretch,
              children: [
                pw.Container(
                  height: 56,
                  color: colorVerde,
                  padding: const pw.EdgeInsets.symmetric(horizontal: 40),
                  child: pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    crossAxisAlignment: pw.CrossAxisAlignment.center,
                    children: [
                      pw.Text('INFORME DESCRIPTIVO - REDACTADO POR IA',
                          style: pw.TextStyle(
                              color: colorBlanco,
                              fontSize: 14,
                              fontWeight: pw.FontWeight.bold,
                              letterSpacing: 1)),
                      pw.Text(fechaGenerado,
                          style: pw.TextStyle(
                              color: PdfColor.fromHex('#C8E6C9'),
                              fontSize: 10)),
                    ],
                  ),
                ),
                pw.Expanded(
                  child: pw.Padding(
                    padding: const pw.EdgeInsets.fromLTRB(40, 32, 40, 24),
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
                      children: [
                        pw.Row(
                          children: [
                            pw.Container(
                              width: 4,
                              height: 18,
                              color: colorAzul,
                            ),
                            pw.SizedBox(width: 8),
                            pw.Text('Resumen generado con inteligencia artificial',
                                style: pw.TextStyle(
                                    fontSize: 11,
                                    fontWeight: pw.FontWeight.bold,
                                    color: colorTextoSuave,
                                    letterSpacing: 0.5)),
                          ],
                        ),
                        pw.SizedBox(height: 14),
                        pw.Expanded(
                          child: pw.Container(
                            width: double.infinity,
                            padding: const pw.EdgeInsets.all(20),
                            decoration: pw.BoxDecoration(
                              color: colorGrisClaro,
                              borderRadius: pw.BorderRadius.circular(12),
                              border: pw.Border.all(color: colorGrisMedio),
                            ),
                            child: pw.Text(
                              informeIA.isNotEmpty
                                  ? informeIA
                                  : 'No se pudo generar el informe automático. Consulta las cifras del resumen ejecutivo.',
                              style: pw.TextStyle(
                                  fontSize: 11,
                                  color: colorTexto,
                                  height: 1.6),
                            ),
                          ),
                        ),
                        pw.SizedBox(height: 12),
                        pw.Container(
                          padding: const pw.EdgeInsets.symmetric(
                              horizontal: 14, vertical: 10),
                          decoration: pw.BoxDecoration(
                            color: PdfColor.fromHex('#E8F5E9'),
                            borderRadius: pw.BorderRadius.circular(8),
                          ),
                          child: pw.Text(
                            'Datos base · ${context.t('stat_initial_floor')} ${datos.pisoInicial} » ${datos.cierrePeriodo} ${incluyeMesActual ? 'activas' : 'activas al cierre'} · Completadas ${datos.completadasCierre} · Pendientes ${datos.pendientesCierre} (${datos.cobertura.toStringAsFixed(1)}% de cobertura) · Nuevas ${datos.nuevasPeriodo} · Restauradas ${datos.restauradasPeriodo} · Removidas ${datos.removidasPeriodo} · Eliminadas ${datos.eliminadasPeriodo} · ${datos.crecimientoNeto >= 0 ? '+' : ''}${datos.crecimientoPorcentaje.toStringAsFixed(1)}% de crecimiento',
                            style: pw.TextStyle(
                                fontSize: 8, color: colorTextoSuave),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                pw.Container(
                  height: 36,
                  color: PdfColor.fromHex('#F9FBE7'),
                  padding: const pw.EdgeInsets.symmetric(horizontal: 40),
                  child: pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    crossAxisAlignment: pw.CrossAxisAlignment.center,
                    children: [
                      pw.Text('Congregación Española · Araucária Sur · Paraná, Brasil',
                          style: pw.TextStyle(fontSize: 8, color: colorTextoSuave)),
                      pw.Text('Página 3',
                          style: pw.TextStyle(fontSize: 8, color: colorTextoSuave)),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      );

      // ── PÁGINA 4: DETALLE POR TERRITORIO ─────────────────
      if (datos.porTerritorio.isNotEmpty) {
        pdf.addPage(
          pw.Page(
            pageTheme: pw.PageTheme(
              pageFormat: PdfPageFormat.a4,
              margin: const pw.EdgeInsets.all(0),
            ),
            build: (pw.Context ctx) {
              final totalDir = datos.porTerritorio.values
                  .fold<int>(0, (a, b) => a + b.totalDirecciones);
              final totalCompl = datos.porTerritorio.values
                  .fold<int>(0, (a, b) => a + b.completadas);
              final totalPend = datos.porTerritorio.values
                  .fold<int>(0, (a, b) => a + b.pendientes);
              final totalTarj = datos.porTerritorio.values
                  .fold<int>(0, (a, b) => a + b.totalTarjetas);
              final totalTarjCompl = datos.porTerritorio.values
                  .fold<int>(0, (a, b) => a + b.tarjetasCompletadas);
              final pctGlobal =
                  totalDir > 0 ? (totalCompl / totalDir * 100) : 0.0;
              return pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.stretch,
                children: [
                  // Mini header
                  pw.Container(
                    height: 56,
                    color: colorVerde,
                    padding: const pw.EdgeInsets.symmetric(horizontal: 40),
                    child: pw.Row(
                      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                      crossAxisAlignment: pw.CrossAxisAlignment.center,
                      children: [
                        pw.Text('DETALLE POR TERRITORIO',
                            style: pw.TextStyle(
                                color: colorBlanco,
                                fontSize: 14,
                                fontWeight: pw.FontWeight.bold,
                                letterSpacing: 1)),
                        pw.Text(fechaGenerado,
                            style: pw.TextStyle(color: PdfColor.fromHex('#C8E6C9'), fontSize: 10)),
                      ],
                    ),
                  ),

                  pw.Expanded(
                    child: pw.Padding(
                      padding: const pw.EdgeInsets.all(32),
                      child: pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
                        children: [
                          pw.Text(
                              'Cobertura de predicación sobre el total del directorio · $periodoTexto',
                              style: pw.TextStyle(
                                  fontSize: 9, color: colorTextoSuave)),
                          pw.SizedBox(height: 12),
                          // Cabecera tabla
                          pw.Container(
                            padding: const pw.EdgeInsets.symmetric(
                                horizontal: 12, vertical: 8),
                            decoration: pw.BoxDecoration(color: colorVerde),
                            child: pw.Row(
                              children: [
                                pw.Expanded(
                                    flex: 9,
                                    child: pw.Text('TERRITORIO',
                                        style: pw.TextStyle(
                                            color: colorBlanco,
                                            fontSize: 8,
                                            fontWeight: pw.FontWeight.bold,
                                            letterSpacing: 0.4))),
                                for (final t in const [
                                  'DIRECCIONES',
                                  'COMPLETADAS',
                                  'PENDIENTES',
                                  'TARJETAS',
                                  '%',
                                ])
                                  pw.Expanded(
                                    flex: t == '%'
                                        ? 5
                                        : t == 'TARJETAS'
                                            ? 7
                                            : t == 'COMPLETADAS'
                                                ? 9
                                                : 8,
                                    child: pw.Text(t,
                                        style: pw.TextStyle(
                                            color: colorBlanco,
                                            fontSize: 8,
                                            fontWeight: pw.FontWeight.bold),
                                        textAlign: pw.TextAlign.center),
                                  ),
                              ],
                            ),
                          ),

                          // Filas ordenadas de mayor a menor por volumen.
                          ...datos.porTerritorio.entries.toList().asMap().entries.map((entry) {
                            final i = entry.key;
                            final nombre = entry.value.key;
                            final d = entry.value.value;
                            final pctTer = d.cobertura;
                            final bgColor = i.isEven ? colorGrisClaro : colorBlanco;
                            return pw.Container(
                              padding: const pw.EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                              decoration: pw.BoxDecoration(color: bgColor),
                              child: pw.Row(
                                children: [
                                  pw.Expanded(flex: 9, child: pw.Text(nombre, style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, color: colorTexto))),
                                  pw.Expanded(flex: 8, child: pw.Text('${d.totalDirecciones}', style: pw.TextStyle(fontSize: 10, color: colorTexto), textAlign: pw.TextAlign.center)),
                                  pw.Expanded(flex: 9, child: pw.Text('${d.completadas}', style: pw.TextStyle(fontSize: 10, color: colorVerde, fontWeight: pw.FontWeight.bold), textAlign: pw.TextAlign.center)),
                                  pw.Expanded(flex: 8, child: pw.Text('${d.pendientes}', style: pw.TextStyle(fontSize: 10, color: colorNaranja, fontWeight: pw.FontWeight.bold), textAlign: pw.TextAlign.center)),
                                  pw.Expanded(flex: 7, child: pw.Text('${d.tarjetasCompletadas}/${d.totalTarjetas}', style: pw.TextStyle(fontSize: 9, color: colorTexto), textAlign: pw.TextAlign.center)),
                                  pw.Expanded(
                                    flex: 5,
                                    child: pw.Container(
                                      margin: const pw.EdgeInsets.symmetric(horizontal: 6),
                                      padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                      decoration: pw.BoxDecoration(
                                        color: pctTer >= 80
                                            ? PdfColor.fromHex('#E8F5E9')
                                            : pctTer >= 50
                                                ? PdfColor.fromHex('#FFF8E1')
                                                : PdfColor.fromHex('#FFEBEE'),
                                        borderRadius: pw.BorderRadius.circular(10),
                                      ),
                                      child: pw.Text(
                                        '${pctTer.toStringAsFixed(0)}%',
                                        style: pw.TextStyle(
                                          fontSize: 8,
                                          fontWeight: pw.FontWeight.bold,
                                          color: pctTer >= 80
                                              ? colorVerde
                                              : pctTer >= 50
                                                  ? colorNaranja
                                                  : PdfColor.fromHex('#B71C1C'),
                                        ),
                                        textAlign: pw.TextAlign.center,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            );
                          }),

                          pw.SizedBox(height: 20),

                          // Totales que cierran con el resumen ejecutivo.
                          pw.Container(
                            padding: const pw.EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                            decoration: pw.BoxDecoration(
                              color: PdfColor.fromHex('#E8F5E9'),
                              border: pw.Border(top: pw.BorderSide(color: colorVerde, width: 2)),
                            ),
                            child: pw.Row(
                              children: [
                                pw.Expanded(flex: 9, child: pw.Text('TOTAL GENERAL', style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, color: colorVerde))),
                                pw.Expanded(flex: 8, child: pw.Text('$totalDir', style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, color: colorVerde), textAlign: pw.TextAlign.center)),
                                pw.Expanded(flex: 9, child: pw.Text('$totalCompl', style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, color: colorVerde), textAlign: pw.TextAlign.center)),
                                pw.Expanded(flex: 8, child: pw.Text('$totalPend', style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, color: colorNaranja), textAlign: pw.TextAlign.center)),
                                pw.Expanded(flex: 7, child: pw.Text('$totalTarjCompl/$totalTarj', style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold, color: colorVerde), textAlign: pw.TextAlign.center)),
                                pw.Expanded(flex: 5, child: pw.Text('${pctGlobal.toStringAsFixed(1)}%', style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, color: colorVerde), textAlign: pw.TextAlign.center)),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  // Footer
                  pw.Container(
                    height: 36,
                    color: PdfColor.fromHex('#F9FBE7'),
                    padding: const pw.EdgeInsets.symmetric(horizontal: 40),
                    child: pw.Row(
                      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                      crossAxisAlignment: pw.CrossAxisAlignment.center,
                      children: [
                        pw.Text('Congregación Española · Araucária Sur · Paraná, Brasil',
                            style: pw.TextStyle(fontSize: 8, color: colorTextoSuave)),
                        pw.Text('Página 4',
                            style: pw.TextStyle(fontSize: 8, color: colorTextoSuave)),
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
        );
      }

      // ── PÁGINA 5: CAMPAÑAS DEL PERÍODO ───────────────────
      if (campanasPeriodo.isNotEmpty) {
        final paginaCampanas = datos.porTerritorio.isNotEmpty ? 5 : 4;
        pdf.addPage(
          pw.Page(
            pageTheme: pw.PageTheme(
              pageFormat: PdfPageFormat.a4,
              margin: const pw.EdgeInsets.all(0),
            ),
            build: (pw.Context ctx) {
              return pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.stretch,
                children: [
                  // Mini header
                  pw.Container(
                    height: 56,
                    color: colorVerde,
                    padding: const pw.EdgeInsets.symmetric(horizontal: 40),
                    child: pw.Row(
                      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                      crossAxisAlignment: pw.CrossAxisAlignment.center,
                      children: [
                        pw.Text('CAMPAÑAS DEL PERÍODO',
                            style: pw.TextStyle(
                                color: colorBlanco,
                                fontSize: 14,
                                fontWeight: pw.FontWeight.bold,
                                letterSpacing: 1)),
                        pw.Text(fechaGenerado,
                            style: pw.TextStyle(
                                color: PdfColor.fromHex('#C8E6C9'),
                                fontSize: 10)),
                      ],
                    ),
                  ),
                  pw.Expanded(
                    child: pw.Padding(
                      padding: const pw.EdgeInsets.all(32),
                      child: campanasPeriodo.isEmpty
                          ? pw.Center(
                              child: pw.Text(
                                  context.t('stat_no_campanas_periodo'),
                                  style: pw.TextStyle(
                                      fontSize: 11, color: colorTextoSuave)),
                            )
                          : pw.Column(
                              crossAxisAlignment: pw.CrossAxisAlignment.stretch,
                              children: [
                                pw.Text(
                                    '${context.t('stat_section_campanas')} · ${_labelPeriodoDatos(datos)}',
                                    style: pw.TextStyle(
                                        fontSize: 10,
                                        fontWeight: pw.FontWeight.bold,
                                        color: colorTextoSuave,
                                        letterSpacing: 1.2)),
                                pw.SizedBox(height: 12),
                                for (final c in campanasPeriodo)
                                  pw.Container(
                                    margin: const pw.EdgeInsets.only(bottom: 14),
                                    padding: const pw.EdgeInsets.all(16),
                                    decoration: pw.BoxDecoration(
                                      color: colorBlanco,
                                      borderRadius: pw.BorderRadius.circular(10),
                                      border:
                                          pw.Border.all(color: colorGrisMedio),
                                    ),
                                    child: pw.Column(
                                      crossAxisAlignment:
                                          pw.CrossAxisAlignment.start,
                                      children: [
                                        pw.Row(
                                          mainAxisAlignment:
                                              pw.MainAxisAlignment.spaceBetween,
                                          crossAxisAlignment:
                                              pw.CrossAxisAlignment.center,
                                          children: [
                                            pw.Text(c.nombre,
                                                style: pw.TextStyle(
                                                    fontSize: 12,
                                                    fontWeight:
                                                        pw.FontWeight.bold,
                                                    color: colorTexto)),
                                            pw.Container(
                                              padding:
                                                  const pw.EdgeInsets.symmetric(
                                                      horizontal: 8,
                                                      vertical: 3),
                                              decoration: pw.BoxDecoration(
                                                color: c.activa
                                                    ? PdfColor.fromHex('#E8F5E9')
                                                    : colorGrisClaro,
                                                borderRadius:
                                                    pw.BorderRadius.circular(10),
                                              ),
                                              child: pw.Text(
                                                  c.activa
                                                      ? context.t(
                                                          'stat_campana_activa')
                                                      : context.t(
                                                          'stat_campana_inactiva'),
                                                  style: pw.TextStyle(
                                                      fontSize: 8,
                                                      fontWeight:
                                                          pw.FontWeight.bold,
                                                      color: c.activa
                                                          ? colorVerde
                                                          : colorTextoSuave)),
                                            ),
                                          ],
                                        ),
                                        pw.SizedBox(height: 4),
                                        pw.Text(
                                            '${context.t('stat_period')}: ${_fmtFecha(c.fechaInicio)} - ${_fmtFecha(c.fechaFin)}',
                                            style: pw.TextStyle(
                                                fontSize: 9,
                                                color: colorTextoSuave)),
                                        pw.SizedBox(height: 8),
                                        if (c.sinRegistro)
                                          pw.Container(
                                            padding:
                                                const pw.EdgeInsets.symmetric(
                                                    horizontal: 10,
                                                    vertical: 8),
                                            decoration: pw.BoxDecoration(
                                              color: PdfColor.fromHex('#FFF8E1'),
                                              borderRadius:
                                                  pw.BorderRadius.circular(6),
                                              border: pw.Border.all(
                                                  color: PdfColor.fromHex(
                                                      '#FFE082')),
                                            ),
                                            child: pw.Text(
                                                '${c.totalDirecciones} '
                                                '${context.t('stat_campana_trabajadas')} · '
                                                '${context.t('stat_campana_sin_registro')}',
                                                style: pw.TextStyle(
                                                    fontSize: 9,
                                                    color: PdfColor.fromHex(
                                                        '#E65100'))),
                                          )
                                        else ...[
                                          pw.ClipRRect(
                                            horizontalRadius: 4,
                                            verticalRadius: 4,
                                            child: pw.LinearProgressIndicator(
                                              value: (c.progreso / 100)
                                                  .clamp(0.0, 1.0)
                                                  .toDouble(),
                                              backgroundColor: colorGrisClaro,
                                              valueColor: c.activa
                                                  ? colorVerde
                                                  : colorNaranja,
                                              minHeight: 10,
                                            ),
                                          ),
                                          pw.SizedBox(height: 4),
                                          pw.Row(
                                            mainAxisAlignment:
                                                pw.MainAxisAlignment.spaceBetween,
                                            children: [
                                              pw.Text(
                                                  '${c.completadas} de ${c.totalDirecciones} con ${c.etiqueta} · ${c.pendientes} ${context.t('stat_campana_pendientes')}',
                                                  style: pw.TextStyle(
                                                      fontSize: 9,
                                                      color: colorTextoSuave)),
                                              pw.Text(
                                                  '${c.progreso.toStringAsFixed(0)}%',
                                                  style: pw.TextStyle(
                                                      fontSize: 11,
                                                      fontWeight:
                                                          pw.FontWeight.bold,
                                                      color: c.activa
                                                          ? colorVerde
                                                          : colorNaranja)),
                                            ],
                                          ),
                                        ],
                                      ],
                                    ),
                                  ),
                              ],
                            ),
                    ),
                  ),
                  // Footer
                  pw.Container(
                    height: 36,
                    color: PdfColor.fromHex('#F9FBE7'),
                    padding: const pw.EdgeInsets.symmetric(horizontal: 40),
                    child: pw.Row(
                      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                      crossAxisAlignment: pw.CrossAxisAlignment.center,
                      children: [
                        pw.Text(
                            'Congregación Española · Araucária Sur · Paraná, Brasil',
                            style: pw.TextStyle(
                                fontSize: 8, color: colorTextoSuave)),
                        pw.Text('Página $paginaCampanas',
                            style: pw.TextStyle(
                                fontSize: 8, color: colorTextoSuave)),
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
        );
      }

      if (mounted) ScaffoldMessenger.of(context).clearSnackBars();

      // Compartir/imprimir
      await Printing.layoutPdf(
        onLayout: (PdfPageFormat format) async => pdf.save(),
        name: 'estadisticas_araucaria_${fechaGenerado.replaceAll('/', '-')}.pdf',
      );

    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).clearSnackBars();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error generando PDF: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  // Helpers para widgets PDF
  pw.Widget _pdfKpi(String label, String value, PdfColor bg, PdfColor fg) {
    return pw.Expanded(
      child: pw.Container(
        padding: const pw.EdgeInsets.symmetric(vertical: 14, horizontal: 10),
        decoration: pw.BoxDecoration(
          color: bg,
          borderRadius: pw.BorderRadius.circular(10),
        ),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(value, style: pw.TextStyle(color: fg, fontSize: 22, fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 4),
            pw.Text(label, style: pw.TextStyle(color: PdfColor(fg.red, fg.green, fg.blue, 0.8), fontSize: 9)),
          ],
        ),
      ),
    );
  }

  pw.Widget _pdfInfoCard(String label, String value, PdfColor color) {
    return pw.Expanded(
      child: pw.Container(
        padding: const pw.EdgeInsets.symmetric(vertical: 12, horizontal: 14),
        decoration: pw.BoxDecoration(
          color: PdfColors.white,
          borderRadius: pw.BorderRadius.circular(10),
          border: pw.Border.all(color: color, width: 1.5),
        ),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(value, style: pw.TextStyle(color: color, fontSize: 18, fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 3),
            pw.Text(label, style: pw.TextStyle(color: PdfColor.fromHex('#757575'), fontSize: 9)),
          ],
        ),
      ),
    );
  }

  pw.Widget _pdfLeyenda(PdfColor color, String label) {
    return pw.Row(
      mainAxisSize: pw.MainAxisSize.min,
      children: [
        pw.Container(
          width: 10,
          height: 10,
          decoration: pw.BoxDecoration(
            color: color,
            borderRadius: pw.BorderRadius.circular(2),
          ),
        ),
        pw.SizedBox(width: 5),
        pw.Text(label,
            style: pw.TextStyle(fontSize: 10, color: PdfColor.fromHex('#757575'))),
      ],
    );
  }

  String _mesCorto(int mes) {
    const meses = ['Ene','Feb','Mar','Abr','May','Jun','Jul','Ago','Sep','Oct','Nov','Dic'];
    return meses[(mes - 1).clamp(0, 11)];
  }

  String _etiquetaMesCorta(String mes) {
    final parts = mes.split('-');
    if (parts.length < 2) return mes;
    final m = int.tryParse(parts[1]);
    return m == null ? mes : _mesCorto(m);
  }
}

// ─────────────────────────────────────────────────────────
// MODELOS DE DATOS
// ─────────────────────────────────────────────────────────

class _DatosEstadisticas {
  final int totalActivas;

  /// Total de direcciones al CIERRE del período. Si el período incluye el mes
  /// actual coincide con [totalActivas]; si es un mes cerrado, es el
  /// directorio al terminar ese mes (no el de hoy).
  final int cierrePeriodo;
  final int pisoInicial;

  /// Direcciones completadas al cierre del período: predicadas alguna vez y
  /// todavía en el directorio. Es la base de la cobertura, no las predicadas
  /// solo dentro de los meses mostrados (eso hacía ver 5% cuando el trabajo
  /// acumulado era del 77%).
  final int completadasCierre;
  final int totalRemovidas;
  final int totalTerritorios;
  final Map<String, int> predicadasPorMes;

  /// Mapas por mes del RANGO EXTENDIDO (desde el arranque del período hasta
  /// hoy). Los gráficos leen solo los meses del período ([meses], subconjunto).
  final Map<String, int> nuevasPorMes;
  final Map<String, int> removidasPorMes;
  final Map<String, int> restauradasPorMes;
  final Map<String, int> eliminadasPorMes;

  /// Movimiento del PERÍODO mostrado (suma de los meses seleccionados).
  final int nuevasPeriodo;
  final int removidasPeriodo;
  final int restauradasPeriodo;
  final int eliminadasPeriodo;
  final List<String> meses;
  final Map<String, _DatosTerritorio> porTerritorio;

  // Estadísticas de campañas.
  final List<_DatosCampana> campanas;

  /// Crecimiento real del período: cierre del período menos el piso inicial
  /// (direcciones que había al comenzar). Es el neto de altas, bajas y
  /// restauraciones del período; con el piso derivado queda coherente por
  /// construcción, sin depender de fotos guardadas que se desactualizan.
  int get crecimientoNeto => cierrePeriodo - pisoInicial;

  /// Direcciones del cierre que aún no fueron predicadas.
  int get pendientesCierre =>
      (cierrePeriodo - completadasCierre).clamp(0, cierrePeriodo).toInt();

  /// Cobertura del período: completadas sobre el total de direcciones.
  double get cobertura {
    if (cierrePeriodo <= 0) return 0;
    return (completadasCierre / cierrePeriodo * 100).clamp(0, 100);
  }

  /// Tasa de crecimiento en porcentaje relativa al piso inicial.
  double get crecimientoPorcentaje {
    if (pisoInicial <= 0) return crecimientoNeto > 0 ? 100 : 0;
    return (crecimientoNeto / pisoInicial * 100);
  }

  _DatosEstadisticas({
    required this.totalActivas,
    required this.cierrePeriodo,
    required this.pisoInicial,
    required this.completadasCierre,
    required this.totalRemovidas,
    required this.totalTerritorios,
    required this.predicadasPorMes,
    required this.meses,
    required this.porTerritorio,
    required this.nuevasPeriodo,
    required this.removidasPeriodo,
    required this.restauradasPeriodo,
    required this.eliminadasPeriodo,
    required this.nuevasPorMes,
    required this.removidasPorMes,
    required this.restauradasPorMes,
    required this.eliminadasPorMes,
    this.campanas = const [],
  });
}

class _DatosCampana {
  final String slot;
  final String nombre;
  final bool activa;
  final DateTime? fechaInicio;
  final DateTime? fechaFin;
  final int totalDirecciones;
  final int completadas;
  final String etiqueta;

  /// `true` cuando la campaña cerró con pendientes pero sin ninguna marca de
  /// entrega: la app no guardó esas entregas y el informe no debe afirmar que
  /// fueron cero.
  final bool sinRegistro;

  int get pendientes => totalDirecciones - completadas;
  double get progreso =>
      totalDirecciones <= 0 ? 0 : (completadas / totalDirecciones * 100);

  _DatosCampana({
    required this.slot,
    required this.nombre,
    required this.activa,
    required this.fechaInicio,
    required this.fechaFin,
    required this.totalDirecciones,
    required this.completadas,
    this.etiqueta = 'material entregado',
    this.sinRegistro = false,
  });
}

class _DatosTerritorio {
  final int totalDirecciones;
  final int completadas;
  final int removidas;
  final int totalTarjetas;
  final int tarjetasCompletadas;

  int get pendientes =>
      (totalDirecciones - completadas).clamp(0, totalDirecciones).toInt();
  double get cobertura =>
      totalDirecciones <= 0 ? 0 : (completadas / totalDirecciones * 100);

  _DatosTerritorio({
    required this.totalDirecciones,
    required this.completadas,
    required this.removidas,
    required this.totalTarjetas,
    required this.tarjetasCompletadas,
  });
}
