import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:araucaria_sur/core/l10n/translation_service.dart';
import 'package:araucaria_sur/core/services/groq_reporte_service.dart';
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
              _seccionTitulo(context.t('stat_section_global_summary'), _labelPeriodo()),
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

              // ── Fecha de movimiento de direcciones ──────
              _seccionTitulo(context.t('stat_section_movement'),
                  _fechaMesActual()),
              const SizedBox(height: 20),

              // ── Gráfico de torta ────────────────────────
              _buildGraficoTorta(datos),
              const SizedBox(height: 20),

              // ── Campañas ─────────────────────────────────
              _seccionTitulo(context.t('stat_section_campanas'), ''),
              const SizedBox(height: 12),
              _buildSeccionCampanas(datos),
              const SizedBox(height: 20),

              // ── Por territorio ──────────────────────────
              _seccionTitulo(context.t('stat_section_by_territory'), ''),
              const SizedBox(height: 12),
              ...datos.porTerritorio.entries
                  .map((e) => _buildTarjetaTerritorio(e.key, e.value, datos)),
              const SizedBox(height: 20),

              // ── Removidas / restauradas / eliminadas ────
              _buildResumenMovimientos(datos),
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

    // Estadísticas mensuales guardadas
    final statsFutures = meses.map(
        (mes) => db.collection('estadisticas').doc('removidas_$mes').get());
    final statsSnaps = await Future.wait(statsFutures);

    // Totales globales: el total considera TODO el directorio global.
    // Sólo se descartan las removidas, que viven en direcciones_removidas
    // y ya no pertenecen al directorio.
    final totalActivas = dirs.where((d) {
      final data = (d.data() as Map<String, dynamic>?) ?? {};
      return data['estado'] != 'removida';
    }).length;

    // Piso inicial (direcciones que había al comienzo del período).
    // Se guarda en configuracion/estadisticas para poder editarlo sin
    // recompilar. Rollover automático: al cambiar de mes, el piso del nuevo
    // mes pasa a ser el total con el que cerró el mes anterior
    // (cierre_ultimo), reiniciando así la cuenta de nuevas direcciones.
    // Sin configuración previa, el período arranca con el total actual
    // (crecimiento 0) en vez de un número fijo histórico.
    final int pisoPorDefecto = totalActivas;
    final pisoDoc = await db.collection('configuracion').doc('estadisticas').get();
    final pisoData = pisoDoc.data() ?? {};

    final mesActual = _claveMes(DateTime.now());
    final pisoMesGuardado = pisoData['piso_mes']?.toString();
    final pisoRegistrado = (pisoData['piso_inicial'] as num?)?.toInt();
    final cierreUltimo = (pisoData['cierre_ultimo'] as num?)?.toInt();

    int pisoInicial;
    if (pisoMesGuardado != null && pisoMesGuardado != mesActual) {
      // Cambió el mes: el piso pasa a ser el total con el que cerró el mes anterior
      pisoInicial = cierreUltimo ?? pisoRegistrado ?? pisoPorDefecto;
    } else {
      // Mismo mes (o primera vez): usar el piso guardado o el predeterminado
      pisoInicial = pisoRegistrado ??
          (pisoData['total_inicial'] as num?)?.toInt() ??
          pisoPorDefecto;
    }

    // Persistir solo cuando cambió: abrir la pestaña no debe escribir Firestore.
    final requiereGuardar =
        (pisoData['piso_inicial'] as num?)?.toInt() != pisoInicial ||
            pisoData['piso_mes']?.toString() != mesActual ||
            (pisoData['cierre_ultimo'] as num?)?.toInt() != totalActivas;
    if (requiereGuardar) {
      await db.collection('configuracion').doc('estadisticas').set({
        'piso_inicial': pisoInicial,
        'piso_mes': mesActual,
        'cierre_ultimo': totalActivas,
      }, SetOptions(merge: true));
    }

    final predicadasPeriodo = dirs.where((d) {
      final data = (d.data() as Map<String, dynamic>?) ?? {};
      final mes = data['mes_predicacion']?.toString();
      return data['predicado'] == true && mes != null && meses.contains(mes);
    }).length;

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
    for (final mes in meses) {
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

    // Removidas por mes (fecha de remoción en direcciones_removidas).
    final Map<String, int> removidasPorMes = {};
    for (final mes in meses) {
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

    // Estadísticas de removidas/restauradas por mes
    int totalRestauradas = 0;
    int totalEliminadasPermanente = 0;
    for (final snap in statsSnaps) {
      if (snap.exists) {
        final data = snap.data() ?? {};
        totalRestauradas += ((data['restauradas'] ?? 0) as num).toInt();
        totalEliminadasPermanente +=
            ((data['eliminadas_permanente'] ?? 0) as num).toInt();
      }
    }

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

      final predicadasTer = dirsTer.where((d) {
        final data = (d.data() as Map<String, dynamic>?) ?? {};
        final mes = data['mes_predicacion']?.toString();
        return data['predicado'] == true && mes != null && meses.contains(mes);
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
        predicadas: predicadasTer,
        removidas: removidasTer,
        totalTarjetas: totalTarjetas,
        tarjetasCompletadas: tarjetasCompletadas,
      );
    }

    // ── Estadísticas de campañas ───────────────────────────────────
    // El progreso se cuenta sobre el directorio global completo: cada
    // dirección con 'campana_invitacion_{nombre}' == true recibió el
    // material (folleto/invitación). El total = todas las direcciones.
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

        final totalDirecciones = dirs.length;
        final completadas = dirs.where((d) {
          final dd = (d.data() as Map<String, dynamic>?) ?? {};
          return dd['campana_invitacion_$nombre'] == true;
        }).length;

        campanas.add(_DatosCampana(
          slot: slot,
          nombre: nombre,
          activa: activa,
          fechaInicio: fechaInicio,
          fechaFin: fechaFin,
          totalDirecciones: totalDirecciones,
          completadas: completadas,
          etiqueta: etiqueta,
        ));
      } catch (_) {
        // Si el doc no existe, no hay campaña en ese slot.
      }
    }

    return _DatosEstadisticas(
      totalActivas: totalActivas,
      pisoInicial: pisoInicial,
      predicadasPeriodo: predicadasPeriodo,
      totalRemovidas: totalRemovidas,
      predicadasPorMes: predicadasPorMes,
      meses: meses,
      porTerritorio: porTerritorio,
      totalRestauradas: totalRestauradas,
      totalEliminadasPermanente: totalEliminadasPermanente,
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
    final porcentaje = datos.totalActivas > 0
        ? (datos.predicadasPeriodo / datos.totalActivas * 100)
            .clamp(0, 100)
            .toDouble()
        : 0.0;

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
                    context.t('stat_predicated_count', args: ['${datos.predicadasPeriodo}']),
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.8),
                      fontSize: 12,
                    ),
                  ),
                  Text(
                    context.t('stat_total_count', args: ['${datos.totalActivas}']),
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.8),
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Builder(
                builder: (context) {
                  final ahora = DateTime.now();
                  final mesActual =
                      '${ahora.year.toString().padLeft(4, '0')}-${ahora.month.toString().padLeft(2, '0')}';
                  final predActual = datos.predicadasPorMes[mesActual] ?? 0;
                  final heredadas = (datos.predicadasPeriodo - predActual)
                      .clamp(0, datos.predicadasPeriodo);
                  return Column(
                    children: [
                      Text(
                        'Mes actual: $predActual • Heredado (meses anteriores): $heredadas',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.7),
                          fontSize: 11,
                          height: 1.3,
                        ),
                      ),
                      if (datos.predicadasPorMes.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Text(
                          'Desglose por mes: ${datos.predicadasPorMes.entries.map((e) => '${e.key}: ${e.value}').join(' • ')}',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.6),
                            fontSize: 9,
                            height: 1.3,
                          ),
                        ),
                      ],
                    ],
                  );
                },
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),

        // 3 métricas
        Row(
          children: [
            Expanded(
              child: _metricaCard(
                '${datos.totalTerritorios}',
                context.t('stat_territories'),
                Icons.map,
                _morado,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _metricaCard(
                '${datos.totalActivas}',
                context.t('stat_addresses'),
                Icons.home_work_outlined,
                Colors.blue,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _metricaCard(
                '${datos.totalRemovidas}',
                context.t('stat_removed'),
                Icons.person_off_outlined,
                Colors.red,
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
          // ── Piso inicial │ Total actual ─────────────────
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
                    '${context.t('stat_total_now')}: ${datos.totalActivas}',
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
                  '${datos.crecimientoNeto > 0 ? '+' : ''}${datos.crecimientoNeto}',
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
          .set({'piso_inicial': nuevo}, SetOptions(merge: true));
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
    // totalActivas = directorio global completo (sin las removidas).
    final activasFijas = datos.totalActivas;
    // El bloque lleva el mes en el título: las removidas que se muestran son las
    // del período, no el acumulado histórico. Si no, una baja de septiembre
    // seguiría figurando como "movimiento" de octubre.
    final removidasPeriodo = datos.removidasPeriodo;
    final total = datos.totalActivas + datos.totalRemovidas;
    if (total == 0) {
      return Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Center(
          child: Text(context.t('stat_no_data'), style: TextStyle(color: Colors.grey)),
        ),
      );
    }

    final activasPct = total > 0 ? activasFijas / total : 0.0;
    final removPct = total > 0 ? removidasPeriodo / total : 0.0;
    final nuevasNeto = datos.crecimientoNeto > 0 ? datos.crecimientoNeto : 0;
    final nuevasPct = total > 0 ? nuevasNeto / total : 0.0;
    final predicPct = datos.totalActivas > 0
        ? datos.predicadasPeriodo / datos.totalActivas
        : 0.0;

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
          // Barras horizontales como torta simplificada
          _barraDistribucion(context.t('stat_dist_predicated'), datos.predicadasPeriodo,
              datos.totalActivas, predicPct, _verde),
          const SizedBox(height: 8),
          _barraDistribucion(context.t('stat_dist_new'), nuevasNeto,
              total, nuevasPct, Colors.blue),
          const SizedBox(height: 8),
          _barraDistribucion(
              context.t('stat_dist_active'), activasFijas, total, activasPct, _morado),
          const SizedBox(height: 8),
          _barraDistribucion(
              context.t('stat_dist_removed'), removidasPeriodo, total, removPct, Colors.red),
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

  Widget _buildSeccionCampanas(_DatosEstadisticas datos) {
    if (datos.campanas.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Center(
          child: Text(context.t('stat_no_campanas'),
              style: TextStyle(color: Colors.grey, fontSize: 11)),
        ),
      );
    }

    return Column(
      children: [
        for (final c in datos.campanas)
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
                        '${_fmtFecha(c.fechaInicio)} – ${_fmtFecha(c.fechaFin)}',
                        style:
                            TextStyle(fontSize: 11, color: Colors.grey[600]),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                // Progreso
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
                  'con ${c.etiqueta}',
                  style: TextStyle(fontSize: 10, color: Colors.grey[600]),
                ),
              ],
            ),
          ),
      ],
    );
  }

  String _fmtFecha(DateTime? fecha) {
    if (fecha == null) return '—';
    return '${fecha.day}/${fecha.month}/${fecha.year}';
  }

  String _fechaMesActual() {
    final ahora = DateTime.now();
    final es = context.currentLanguage == 'PT';
    const mesesES = [
      'Enero', 'Febrero', 'Marzo', 'Abril', 'Mayo', 'Junio',
      'Julio', 'Agosto', 'Septiembre', 'Octubre', 'Noviembre', 'Diciembre'
    ];
    const mesesPT = [
      'Janeiro', 'Fevereiro', 'Março', 'Abril', 'Maio', 'Junho',
      'Julho', 'Agosto', 'Setembro', 'Outubro', 'Novembro', 'Dezembro'
    ];
    final meses = es ? mesesPT : mesesES;
    final idx = (ahora.month - 1).clamp(0, 11);
    return '${meses[idx]} ${ahora.year}';
  }

  Widget _buildTarjetaTerritorio(
      String nombre, _DatosTerritorio datos, _DatosEstadisticas global) {
    final porcentaje = datos.totalDirecciones > 0
        ? (datos.predicadas / datos.totalDirecciones * 100)
            .clamp(0, 100)
            .toDouble()
        : 0.0;

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
                _miniMetrica('${datos.predicadas}', context.t('stat_dist_predicated'), _verde),
                _miniMetrica('${datos.totalDirecciones - datos.predicadas}',
                    context.t('stat_pending'), Colors.grey),
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

  Widget _buildResumenMovimientos(_DatosEstadisticas datos) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
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
            context.t('stat_movements'),
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 13,
              color: Color(0xFF263238),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _movimientoItem(
                  Icons.person_off,
                  context.t('stat_removed'),
                  datos.totalRemovidas,
                  Colors.red,
                  context.t('stat_removed_not_hispanic'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _movimientoItem(
                  Icons.restore,
                  context.t('stat_restored'),
                  datos.totalRestauradas,
                  _verde,
                  context.t('stat_restored_desc'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _movimientoItem(
                  Icons.delete_forever,
                  context.t('stat_permanently_deleted'),
                  datos.totalEliminadasPermanente,
                  Colors.grey,
                  context.t('stat_permanently_deleted_desc'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _movimientoItem(
      IconData icon, String label, int valor, Color color, String sublabel) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.06),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(height: 4),
          Text(
            '$valor',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          Text(
            label,
            style: TextStyle(
                fontSize: 11, fontWeight: FontWeight.w600, color: color),
          ),
          Text(
            sublabel,
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
      final periodoTexto = _mesesSeleccionados == 1
          ? context.t('stat_period_monthly')
          : _mesesSeleccionados == 3
              ? context.t('stat_period_quarterly')
              : _mesesSeleccionados == 6
                  ? context.t('stat_period_semiannual')
                  : context.t('stat_period_annual');
      final fechaGenerado =
          '${ahora.day.toString().padLeft(2, '0')}/${ahora.month.toString().padLeft(2, '0')}/${ahora.year}';

      // ── INFORME REDACTADO POR IA (Groq) ──────────────────
      String informeIA = '';
      try {
        informeIA = await GroqReporteService.generarInformeEjecutivo(
          resumen: {
            'periodo': periodoTexto,
            'piso_inicial': datos.pisoInicial,
            'total_activas': datos.totalActivas,
            'predicadas_periodo': datos.predicadasPeriodo,
            'nuevas_periodo': datos.crecimientoNeto,
            'removidas_periodo': datos.removidasPeriodo,
            'restauradas_periodo': datos.restauradasPeriodo,
            'eliminadas_permanente': datos.eliminadasPeriodo,
            'crecimiento_neto': datos.crecimientoNeto,
            'crecimiento_porcentaje': datos.crecimientoPorcentaje,
            'total_removidas': datos.totalRemovidas,
            'total_territorios': datos.totalTerritorios,
          },
        );
      } catch (e) {
        debugPrint('Error generando informe IA: $e');
        informeIA = '';
      }

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

      // ── PORCENTAJE COMPLETADO ─────────────────────────────
      final pct = datos.totalActivas > 0
          ? (datos.predicadasPeriodo / datos.totalActivas * 100).clamp(0, 100)
          : 0.0;

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
                        pw.Text('RESUMEN EJECUTIVO',
                            style: pw.TextStyle(
                                fontSize: 11,
                                fontWeight: pw.FontWeight.bold,
                                color: colorTextoSuave,
                                letterSpacing: 1.5)),
                        pw.SizedBox(height: 12),
                        pw.Row(
                          children: [
                            _pdfKpi('Direcciones activas', '${datos.totalActivas}', colorVerde, colorBlanco),
                            pw.SizedBox(width: 12),
                            _pdfKpi('Predicadas período', '${datos.predicadasPeriodo}', colorMorado, colorBlanco),
                            pw.SizedBox(width: 12),
                            _pdfKpi(context.t('stat_territories'), '${datos.totalTerritorios}', PdfColor.fromHex('#0277BD'), colorBlanco),
                          ],
                        ),

                        pw.SizedBox(height: 24),

                        // ── Barra de progreso ──────────────────────────
                        pw.Text('PROGRESO DE PREDICACIÓN',
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
                                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                                children: [
                                  pw.Text('Cobertura del período',
                                      style: pw.TextStyle(fontSize: 12, color: colorTexto)),
                                  pw.Text('${pct.toStringAsFixed(1)}%',
                                      style: pw.TextStyle(
                                          fontSize: 20,
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
                                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                                children: [
                                  pw.Text(context.t('stat_predicated_count', args: ['${datos.predicadasPeriodo}']),
                                      style: pw.TextStyle(fontSize: 10, color: colorVerde, fontWeight: pw.FontWeight.bold)),
                                  pw.Text('${datos.totalActivas - datos.predicadasPeriodo} pendientes',
                                      style: pw.TextStyle(fontSize: 10, color: colorTextoSuave)),
                                ],
                              ),
                            ],
                          ),
                        ),

                        pw.SizedBox(height: 24),

                        // ── Gráfico de barras por mes ──────────────────
                        if (datos.predicadasPorMes.isNotEmpty) ...[
                          pw.Text('EVOLUCIÓN MENSUAL',
                              style: pw.TextStyle(
                                  fontSize: 11,
                                  fontWeight: pw.FontWeight.bold,
                                  color: colorTextoSuave,
                                  letterSpacing: 1.5)),
                          pw.SizedBox(height: 10),
                          pw.Container(
                            height: 150,
                            padding: const pw.EdgeInsets.all(16),
                            decoration: pw.BoxDecoration(
                              color: colorGrisClaro,
                              borderRadius: pw.BorderRadius.circular(12),
                              border: pw.Border.all(color: colorGrisMedio),
                            ),
                            child: pw.Column(
                              children: [
                                pw.Expanded(
                                  child: pw.Row(
                                    crossAxisAlignment: pw.CrossAxisAlignment.end,
                                    mainAxisAlignment: pw.MainAxisAlignment.spaceEvenly,
                                    children: () {
                                      final maxVal = datos.predicadasPorMes.values
                                          .fold(0, (a, b) => a > b ? a : b)
                                          .toDouble();
                                      return datos.meses.map((mes) {
                                        final val = datos.predicadasPorMes[mes] ?? 0;
                                        final h = maxVal > 0 ? (val / maxVal) : 0.0;
                                        final parts = mes.split('-');
                                        final label = parts.length >= 2 ? '${_mesCorto(int.parse(parts[1]))}' : mes;
                                        return pw.Column(
                                          mainAxisAlignment: pw.MainAxisAlignment.end,
                                          children: [
                                            pw.Text('$val', style: pw.TextStyle(fontSize: 8, color: colorVerde, fontWeight: pw.FontWeight.bold)),
                                            pw.SizedBox(height: 3),
                                            pw.Container(
                                              width: 28,
                                              height: (h * 80).clamp(4, 80),
                                              decoration: pw.BoxDecoration(
                                                color: colorVerde,
                                                borderRadius: pw.BorderRadius.only(
                                                  topLeft: const pw.Radius.circular(4),
                                                  topRight: const pw.Radius.circular(4),
                                                ),
                                              ),
                                            ),
                                            pw.SizedBox(height: 4),
                                            pw.Text(label, style: pw.TextStyle(fontSize: 8, color: colorTextoSuave)),
                                          ],
                                        );
                                      }).toList();
                                    }(),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],

                        pw.SizedBox(height: 24),

                        // ── Resumen removidas/restauradas ──────────────
                        pw.Row(
                          children: [
                            _pdfInfoCard(context.t('stat_new_addresses'), '${datos.nuevasPeriodo}', PdfColor.fromHex('#0277BD')),
                            pw.SizedBox(width: 12),
                            _pdfInfoCard(context.t('stat_removed_not_hispanic'), '${datos.totalRemovidas}', colorNaranja),
                            pw.SizedBox(width: 12),
                            _pdfInfoCard('Restauradas', '${datos.totalRestauradas}', colorVerde),
                            pw.SizedBox(width: 12),
                            _pdfInfoCard('Eliminadas', '${datos.totalEliminadasPermanente}', PdfColor.fromHex('#B71C1C')),
                          ],
                        ),

                        pw.SizedBox(height: 16),

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
                                    '${context.t('stat_initial_floor')} ${datos.pisoInicial} » ${context.t('stat_total_now')} ${datos.totalActivas} · Nuevas ${datos.crecimientoNeto > 0 ? '+' : ''}${datos.crecimientoNeto} · Restauradas ${datos.restauradasPeriodo} · Removidas ${datos.removidasPeriodo}',
                                    style: pw.TextStyle(
                                        fontSize: 9, color: colorTextoSuave),
                                  ),
                                ],
                              ),
                              pw.Text(
                                '${datos.crecimientoNeto >= 0 ? '+' : ''}${datos.crecimientoPorcentaje.toStringAsFixed(1)}%',
                                style: pw.TextStyle(
                                    fontSize: 22,
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
                      pw.Text('MOVIMIENTO MENSUAL DE DIRECCIONES',
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
                        // Barras agrupadas por mes
                        pw.Expanded(
                          child: pw.Row(
                            crossAxisAlignment: pw.CrossAxisAlignment.end,
                            mainAxisAlignment: pw.MainAxisAlignment.spaceEvenly,
                            children: datos.meses.map((mes) {
                              final nuevas = datos.nuevasPorMes[mes] ?? 0;
                              final removidas = datos.removidasPorMes[mes] ?? 0;
                              final restauradas = datos.restauradasPorMes[mes] ?? 0;
                              final hNuevas = maxMv > 0 ? nuevas / maxMv : 0.0;
                              final hRemovidas = maxMv > 0 ? removidas / maxMv : 0.0;
                              final hRestauradas = maxMv > 0 ? restauradas / maxMv : 0.0;
                              final parts = mes.split('-');
                              final label = parts.length >= 2
                                  ? '${_mesCorto(int.parse(parts[1]))}'
                                  : mes;
                              return pw.Column(
                                mainAxisAlignment: pw.MainAxisAlignment.end,
                                children: [
                                  pw.Text(
                                      '$nuevas / $removidas / $restauradas',
                                      style: pw.TextStyle(
                                          fontSize: 7,
                                          color: colorTextoSuave)),
                                  pw.SizedBox(height: 6),
                                  pw.Row(
                                    crossAxisAlignment: pw.CrossAxisAlignment.end,
                                    children: [
                                      pw.Container(
                                        width: 16,
                                        height: (hNuevas * 90).clamp(3, 90),
                                        decoration: pw.BoxDecoration(
                                            color: colorAzul,
                                            borderRadius: pw.BorderRadius.vertical(
                                                top: pw.Radius.circular(3))),
                                      ),
                                      pw.SizedBox(width: 3),
                                      pw.Container(
                                        width: 16,
                                        height: (hRemovidas * 90).clamp(3, 90),
                                        decoration: pw.BoxDecoration(
                                            color: colorNaranja,
                                            borderRadius: pw.BorderRadius.vertical(
                                                top: pw.Radius.circular(3))),
                                      ),
                                      pw.SizedBox(width: 3),
                                      pw.Container(
                                        width: 16,
                                        height: (hRestauradas * 90).clamp(3, 90),
                                        decoration: pw.BoxDecoration(
                                            color: colorVerde,
                                            borderRadius: pw.BorderRadius.vertical(
                                                top: pw.Radius.circular(3))),
                                      ),
                                    ],
                                  ),
                                  pw.SizedBox(height: 6),
                                  pw.Text(label,
                                      style: pw.TextStyle(
                                          fontSize: 9, color: colorTexto)),
                                ],
                              );
                            }).toList(),
                          ),
                        ),
                        pw.SizedBox(height: 24),
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

      // ── PÁGINA 3: INFORME EJECUTIVO (IA) ────────────────
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
                      pw.Text('INFORME EJECUTIVO — REDACTADO POR IA',
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
                            'Datos base: ${context.t('stat_initial_floor')} ${datos.pisoInicial} » ${datos.totalActivas} activas · Nuevas ${datos.crecimientoNeto > 0 ? '+' : ''}${datos.crecimientoNeto} · Restauradas ${datos.restauradasPeriodo} · Removidas ${datos.removidasPeriodo} · Eliminadas ${datos.eliminadasPeriodo} · ${datos.crecimientoNeto >= 0 ? '+' : ''}${datos.crecimientoPorcentaje.toStringAsFixed(1)}% de crecimiento',
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
                          // Cabecera tabla
                          pw.Container(
                            padding: const pw.EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            decoration: pw.BoxDecoration(color: colorVerde),
                            child: pw.Row(
                              children: [
                                pw.Expanded(flex: 3, child: pw.Text('TERRITORIO', style: pw.TextStyle(color: colorBlanco, fontSize: 9, fontWeight: pw.FontWeight.bold, letterSpacing: 1))),
                                pw.Expanded(flex: 1, child: pw.Text('DIRS.', style: pw.TextStyle(color: colorBlanco, fontSize: 9, fontWeight: pw.FontWeight.bold), textAlign: pw.TextAlign.center)),
                                pw.Expanded(flex: 1, child: pw.Text('PRED.', style: pw.TextStyle(color: colorBlanco, fontSize: 9, fontWeight: pw.FontWeight.bold), textAlign: pw.TextAlign.center)),
                                pw.Expanded(flex: 1, child: pw.Text('TARJ.', style: pw.TextStyle(color: colorBlanco, fontSize: 9, fontWeight: pw.FontWeight.bold), textAlign: pw.TextAlign.center)),
                                pw.Expanded(flex: 1, child: pw.Text('%', style: pw.TextStyle(color: colorBlanco, fontSize: 9, fontWeight: pw.FontWeight.bold), textAlign: pw.TextAlign.center)),
                              ],
                            ),
                          ),

                          // Filas
                          ...datos.porTerritorio.entries.toList().asMap().entries.map((entry) {
                            final i = entry.key;
                            final nombre = entry.value.key;
                            final d = entry.value.value;
                            final pctTer = d.totalDirecciones > 0
                                ? (d.predicadas / d.totalDirecciones * 100).clamp(0, 100)
                                : 0.0;
                            final bgColor = i.isEven ? colorGrisClaro : colorBlanco;
                            return pw.Container(
                              padding: const pw.EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                              decoration: pw.BoxDecoration(color: bgColor),
                              child: pw.Row(
                                children: [
                                  pw.Expanded(flex: 3, child: pw.Text(nombre, style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, color: colorTexto))),
                                  pw.Expanded(flex: 1, child: pw.Text('${d.totalDirecciones}', style: pw.TextStyle(fontSize: 10, color: colorTexto), textAlign: pw.TextAlign.center)),
                                  pw.Expanded(flex: 1, child: pw.Text('${d.predicadas}', style: pw.TextStyle(fontSize: 10, color: colorVerde, fontWeight: pw.FontWeight.bold), textAlign: pw.TextAlign.center)),
                                  pw.Expanded(flex: 1, child: pw.Text('${d.totalTarjetas}', style: pw.TextStyle(fontSize: 10, color: colorTexto), textAlign: pw.TextAlign.center)),
                                  pw.Expanded(
                                    flex: 1,
                                    child: pw.Container(
                                      margin: const pw.EdgeInsets.symmetric(horizontal: 4),
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
                                          fontSize: 9,
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

                          // Totales
                          pw.Container(
                            padding: const pw.EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                            decoration: pw.BoxDecoration(
                              color: PdfColor.fromHex('#E8F5E9'),
                              border: pw.Border(top: pw.BorderSide(color: colorVerde, width: 2)),
                            ),
                            child: pw.Row(
                              children: [
                                pw.Expanded(flex: 3, child: pw.Text('TOTAL GENERAL', style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, color: colorVerde))),
                                pw.Expanded(flex: 1, child: pw.Text('${datos.totalActivas}', style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, color: colorVerde), textAlign: pw.TextAlign.center)),
                                pw.Expanded(flex: 1, child: pw.Text('${datos.predicadasPeriodo}', style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, color: colorVerde), textAlign: pw.TextAlign.center)),
                                pw.Expanded(flex: 1, child: pw.Text('', style: pw.TextStyle(fontSize: 10))),
                                pw.Expanded(flex: 1, child: pw.Text('${pct.toStringAsFixed(1)}%', style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, color: colorVerde), textAlign: pw.TextAlign.center)),
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
}

// ─────────────────────────────────────────────────────────
// MODELOS DE DATOS
// ─────────────────────────────────────────────────────────

class _DatosEstadisticas {
  final int totalActivas;
  final int pisoInicial;
  final int predicadasPeriodo;
  final int totalRemovidas;
  final int totalRestauradas;
  final int totalEliminadasPermanente;
  final int totalTerritorios;
  final Map<String, int> predicadasPorMes;
  final Map<String, int> nuevasPorMes;
  final Map<String, int> removidasPorMes;
  final Map<String, int> restauradasPorMes;
  final Map<String, int> eliminadasPorMes;
  final List<String> meses;
  final Map<String, _DatosTerritorio> porTerritorio;

  // Estadísticas de campañas.
  final List<_DatosCampana> campanas;

  int get nuevasPeriodo =>
      nuevasPorMes.values.fold(0, (a, b) => a + b);
  int get removidasPeriodo =>
      removidasPorMes.values.fold(0, (a, b) => a + b);
  int get restauradasPeriodo =>
      restauradasPorMes.values.fold(0, (a, b) => a + b);
  int get eliminadasPeriodo =>
      eliminadasPorMes.values.fold(0, (a, b) => a + b);

  /// Crecimiento real del período: total actual menos el piso inicial
  /// (cantidad de direcciones que había al inicio del período).
  int get crecimientoNeto => totalActivas - pisoInicial;

  /// Tasa de crecimiento en porcentaje relativa al piso inicial.
  double get crecimientoPorcentaje {
    if (pisoInicial <= 0) return crecimientoNeto > 0 ? 100 : 0;
    return (crecimientoNeto / pisoInicial * 100);
  }

  _DatosEstadisticas({
    required this.totalActivas,
    required this.pisoInicial,
    required this.predicadasPeriodo,
    required this.totalRemovidas,
    required this.totalRestauradas,
    required this.totalEliminadasPermanente,
    required this.totalTerritorios,
    required this.predicadasPorMes,
    required this.meses,
    required this.porTerritorio,
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
  });
}

class _DatosTerritorio {
  final int totalDirecciones;
  final int predicadas;
  final int removidas;
  final int totalTarjetas;
  final int tarjetasCompletadas;

  _DatosTerritorio({
    required this.totalDirecciones,
    required this.predicadas,
    required this.removidas,
    required this.totalTarjetas,
    required this.tarjetasCompletadas,
  });
}
