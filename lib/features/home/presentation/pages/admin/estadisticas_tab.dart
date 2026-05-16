import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

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
  bool _cargando = false;

  static const Color _morado = Color(0xFF4A148C);
  static const Color _verde = Color(0xFF1B5E20);

  // ─────────────────────────────────────────────────────────
  // HELPERS DE FECHA
  // ─────────────────────────────────────────────────────────

  List<String> _getMesesPeriodo() {
    final ahora = DateTime.now();
    final meses = <String>[];
    for (int i = _mesesSeleccionados - 1; i >= 0; i--) {
      final fecha = DateTime(ahora.year, ahora.month - i, 1);
      meses.add('${fecha.year}-${fecha.month.toString().padLeft(2, '0')}');
    }
    return meses;
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
    switch (_mesesSeleccionados) {
      case 1:
        return 'Este mes';
      case 3:
        return 'Últimos 3 meses';
      case 6:
        return 'Últimos 6 meses';
      case 12:
        return 'Último año';
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
              const Text(
                'Congregación Española Araucaria Sur',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: _morado,
                ),
              ),
              const Text(
                'Informe de Territorio',
                style: TextStyle(fontSize: 11, color: Colors.grey),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  _periodoBtn('Mensual', 1),
                  const SizedBox(width: 8),
                  _periodoBtn('Trimestral', 3),
                  const SizedBox(width: 8),
                  _periodoBtn('Semestral', 6),
                  const SizedBox(width: 8),
                  _periodoBtn('Anual', 12),
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

  Widget _periodoBtn(String label, int meses) {
    final activo = _mesesSeleccionados == meses;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _mesesSeleccionados = meses),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: activo ? _morado : Colors.grey.shade100,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: activo ? Colors.white : Colors.grey,
            ),
          ),
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────
  // CONTENIDO PRINCIPAL
  // ─────────────────────────────────────────────────────────

  Widget _buildContenido() {
    final meses = _getMesesPeriodo();

    return FutureBuilder<_DatosEstadisticas>(
      future: _cargarDatos(meses),
      builder: (context, snap) {
        if (!snap.hasData) {
          return const Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                CircularProgressIndicator(color: _morado),
                SizedBox(height: 12),
                Text('Cargando estadísticas...',
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
              _seccionTitulo('RESUMEN GLOBAL', _labelPeriodo()),
              const SizedBox(height: 12),
              _buildResumenGlobal(datos),
              const SizedBox(height: 20),

              // ── Gráfico de barras mensual ────────────────
              if (_mesesSeleccionados > 1) ...[
                _seccionTitulo('PROGRESO MENSUAL', ''),
                const SizedBox(height: 12),
                _buildGraficoBarras(datos),
                const SizedBox(height: 20),
              ],

              // ── Gráfico de torta ────────────────────────
              _seccionTitulo('DISTRIBUCIÓN DE DIRECCIONES', ''),
              const SizedBox(height: 12),
              _buildGraficoTorta(datos),
              const SizedBox(height: 20),

              // ── Por territorio ──────────────────────────
              _seccionTitulo('POR TERRITORIO', ''),
              const SizedBox(height: 12),
              ...datos.porTerritorio.entries
                  .map((e) => _buildTarjetaTerritorio(e.key, e.value, datos)),
              const SizedBox(height: 20),

              // ── Removidas y temporales ──────────────────
              _buildResumenRemovidasTemporales(datos),
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

    // Totales globales
    final totalActivas = dirs.where((d) {
      final data = (d.data() as Map<String, dynamic>?) ?? {};
      return data['estado'] != 'removida' && data['estado'] != 'temporal';
    }).length;

    final predicadasPeriodo = dirs.where((d) {
      final data = (d.data() as Map<String, dynamic>?) ?? {};
      final mes = data['mes_predicacion']?.toString();
      return data['predicado'] == true && mes != null && meses.contains(mes);
    }).length;

    final temporales = dirs.where((d) {
      final data = (d.data() as Map<String, dynamic>?) ?? {};
      return data['estado'] == 'temporal';
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
      if (ter.id == 'temporales') continue;
      final terData = (ter.data() as Map<String, dynamic>?) ?? {};
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

      final tempTer = dirsTer.where((d) {
        final data = (d.data() as Map<String, dynamic>?) ?? {};
        return data['estado'] == 'temporal';
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
        temporales: tempTer,
        removidas: removidasTer,
        totalTarjetas: totalTarjetas,
        tarjetasCompletadas: tarjetasCompletadas,
      );
    }

    return _DatosEstadisticas(
      totalActivas: totalActivas,
      predicadasPeriodo: predicadasPeriodo,
      temporales: temporales,
      totalRemovidas: totalRemovidas,
      predicadasPorMes: predicadasPorMes,
      meses: meses,
      porTerritorio: porTerritorio,
      totalRestauradas: totalRestauradas,
      totalEliminadasPermanente: totalEliminadasPermanente,
      totalTerritorios: terSnap.docs.where((d) => d.id != 'temporales').length,
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
                  const Text(
                    'Progreso de predicación',
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
                    '${datos.predicadasPeriodo} predicadas',
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.8),
                      fontSize: 12,
                    ),
                  ),
                  Text(
                    '${datos.totalActivas} totales',
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.8),
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),

        // 4 métricas
        Row(
          children: [
            Expanded(
              child: _metricaCard(
                '${datos.totalTerritorios}',
                'Territorios',
                Icons.map,
                _morado,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _metricaCard(
                '${datos.totalActivas}',
                'Direcciones',
                Icons.home_work_outlined,
                Colors.blue,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _metricaCard(
                '${datos.temporales}',
                'Temporales',
                Icons.timer_outlined,
                Colors.orange,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _metricaCard(
                '${datos.totalRemovidas}',
                'Removidas',
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
          const Text(
            'Direcciones predicadas por mes',
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
    final total = datos.totalActivas + datos.temporales + datos.totalRemovidas;
    if (total == 0) {
      return Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
        ),
        child: const Center(
          child: Text('Sin datos', style: TextStyle(color: Colors.grey)),
        ),
      );
    }

    final activasPct = total > 0 ? datos.totalActivas / total : 0.0;
    final tempPct = total > 0 ? datos.temporales / total : 0.0;
    final removPct = total > 0 ? datos.totalRemovidas / total : 0.0;
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
          _barraDistribucion('Predicadas', datos.predicadasPeriodo,
              datos.totalActivas, predicPct, _verde),
          const SizedBox(height: 8),
          _barraDistribucion(
              'Activas', datos.totalActivas, total, activasPct, _morado),
          const SizedBox(height: 8),
          _barraDistribucion(
              'Temporales', datos.temporales, total, tempPct, Colors.orange),
          const SizedBox(height: 8),
          _barraDistribucion(
              'Removidas', datos.totalRemovidas, total, removPct, Colors.red),
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
                        '${datos.totalDirecciones} direcciones · ${datos.totalTarjetas} tarjetas',
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
                _miniMetrica('${datos.predicadas}', 'Predicadas', _verde),
                _miniMetrica('${datos.totalDirecciones - datos.predicadas}',
                    'Pendientes', Colors.grey),
                _miniMetrica(
                    '${datos.temporales}', 'Temporales', Colors.orange),
                _miniMetrica('${datos.removidas}', 'Removidas', Colors.red),
                _miniMetrica(
                    '${datos.tarjetasCompletadas}/${datos.totalTarjetas}',
                    'Tarjetas',
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

  Widget _buildResumenRemovidasTemporales(_DatosEstadisticas datos) {
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
          const Text(
            'Movimientos del período',
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
                  'Removidas',
                  datos.totalRemovidas,
                  Colors.red,
                  'No hispanohablantes',
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _movimientoItem(
                  Icons.restore,
                  'Restauradas',
                  datos.totalRestauradas,
                  _verde,
                  'Volvieron hispanos',
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _movimientoItem(
                  Icons.delete_forever,
                  'Eliminadas',
                  datos.totalEliminadasPermanente,
                  Colors.grey,
                  'Permanente',
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
          const Row(
            children: [
              Icon(Icons.picture_as_pdf, color: Colors.white, size: 20),
              SizedBox(width: 8),
              Text(
                'Exportar informe',
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
            'Congregación Española Araucaria Sur · ${_labelPeriodo()}',
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
                  label: const Text('Compartir resumen',
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
        const SnackBar(content: Text('📊 Generando PDF...'), duration: Duration(seconds: 30)),
      );

      final pdf = pw.Document();
      final ahora = DateTime.now();
      final periodoTexto = _mesesSeleccionados == 1
          ? 'Mensual'
          : _mesesSeleccionados == 3
              ? 'Trimestral'
              : _mesesSeleccionados == 6
                  ? 'Semestral'
                  : 'Anual';
      final fechaGenerado =
          '${ahora.day.toString().padLeft(2, '0')}/${ahora.month.toString().padLeft(2, '0')}/${ahora.year}';

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
                            _pdfKpi('Temporales', '${datos.temporales}', colorNaranja, colorBlanco),
                            pw.SizedBox(width: 12),
                            _pdfKpi('Territorios', '${datos.totalTerritorios}', PdfColor.fromHex('#0277BD'), colorBlanco),
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
                                  pw.Text('${datos.predicadasPeriodo} predicadas',
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
                            _pdfInfoCard('No hispanohablantes', '${datos.totalRemovidas}', colorNaranja),
                            pw.SizedBox(width: 12),
                            _pdfInfoCard('Restauradas', '${datos.totalRestauradas}', colorVerde),
                            pw.SizedBox(width: 12),
                            _pdfInfoCard('Eliminadas', '${datos.totalEliminadasPermanente}', PdfColor.fromHex('#B71C1C')),
                          ],
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

      // ── PÁGINA 2: DETALLE POR TERRITORIO ─────────────────
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
                                pw.Expanded(flex: 1, child: pw.Text('TEMP.', style: pw.TextStyle(color: colorBlanco, fontSize: 9, fontWeight: pw.FontWeight.bold), textAlign: pw.TextAlign.center)),
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
                                  pw.Expanded(flex: 1, child: pw.Text('${d.temporales}', style: pw.TextStyle(fontSize: 10, color: colorNaranja), textAlign: pw.TextAlign.center)),
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
                                pw.Expanded(flex: 1, child: pw.Text('${datos.temporales}', style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, color: colorNaranja), textAlign: pw.TextAlign.center)),
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

  String _mesCorto(int mes) {
    const meses = ['Ene','Feb','Mar','Abr','May','Jun','Jul','Ago','Sep','Oct','Nov','Dic'];
    return meses[(mes - 1).clamp(0, 11)];
  }

  void _exportarTexto(_DatosEstadisticas datos) {
    final ahora = DateTime.now();
    final fecha = '${ahora.day}/${ahora.month}/${ahora.year}';
    final porcentaje = datos.totalActivas > 0
        ? (datos.predicadasPeriodo / datos.totalActivas * 100)
            .toStringAsFixed(1)
        : '0';

    final buffer = StringBuffer();
    buffer.writeln('═══════════════════════════════');
    buffer.writeln('CONGREGACIÓN ESPAÑOLA ARAUCARIA SUR');
    buffer.writeln('Informe de Territorio — $fecha');
    buffer.writeln('Período: ${_labelPeriodo()}');
    buffer.writeln('═══════════════════════════════\n');
    buffer.writeln('RESUMEN GLOBAL');
    buffer.writeln('• Territorios: ${datos.totalTerritorios}');
    buffer.writeln('• Direcciones activas: ${datos.totalActivas}');
    buffer.writeln('• Predicadas: ${datos.predicadasPeriodo} ($porcentaje%)');
    buffer.writeln('• Temporales: ${datos.temporales}');
    buffer.writeln('• Removidas (no hispanos): ${datos.totalRemovidas}');
    buffer.writeln('• Restauradas: ${datos.totalRestauradas}');
    buffer.writeln('\nPOR TERRITORIO');
    for (final entry in datos.porTerritorio.entries) {
      final pct = entry.value.totalDirecciones > 0
          ? (entry.value.predicadas / entry.value.totalDirecciones * 100)
              .toStringAsFixed(0)
          : '0';
      buffer.writeln(
          '• ${entry.key}: ${entry.value.predicadas}/${entry.value.totalDirecciones} ($pct%)');
    }
    buffer.writeln('\n═══════════════════════════════');

    final texto = buffer.toString();

    showDialog(
      context: context,
      builder: (c) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.picture_as_pdf, color: _verde),
            SizedBox(width: 8),
            Text('Informe generado'),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.grey.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.grey.shade200),
                ),
                child: Text(
                  texto,
                  style: const TextStyle(fontSize: 11, fontFamily: 'monospace'),
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                'Copia este texto para compartir por WhatsApp o email.',
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c),
            child: const Text('Cerrar'),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────
// MODELOS DE DATOS
// ─────────────────────────────────────────────────────────

class _DatosEstadisticas {
  final int totalActivas;
  final int predicadasPeriodo;
  final int temporales;
  final int totalRemovidas;
  final int totalRestauradas;
  final int totalEliminadasPermanente;
  final int totalTerritorios;
  final Map<String, int> predicadasPorMes;
  final List<String> meses;
  final Map<String, _DatosTerritorio> porTerritorio;

  _DatosEstadisticas({
    required this.totalActivas,
    required this.predicadasPeriodo,
    required this.temporales,
    required this.totalRemovidas,
    required this.totalRestauradas,
    required this.totalEliminadasPermanente,
    required this.totalTerritorios,
    required this.predicadasPorMes,
    required this.meses,
    required this.porTerritorio,
  });
}

class _DatosTerritorio {
  final int totalDirecciones;
  final int predicadas;
  final int temporales;
  final int removidas;
  final int totalTarjetas;
  final int tarjetasCompletadas;

  _DatosTerritorio({
    required this.totalDirecciones,
    required this.predicadas,
    required this.temporales,
    required this.removidas,
    required this.totalTarjetas,
    required this.tarjetasCompletadas,
  });
}
