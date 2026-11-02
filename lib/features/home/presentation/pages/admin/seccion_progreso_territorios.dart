import 'package:araucaria_sur/core/l10n/translation_service.dart';
import 'package:araucaria_sur/core/services/sesiones_territorio_service.dart';
import 'package:araucaria_sur/core/utils/date_utils.dart';
import 'package:flutter/material.dart';

/// Sección EXTRA de Estadísticas: cuánto se ha predicado de cada territorio y
/// cuánto se tardó en terminarlo.
///
/// Qué es y qué no es
///
/// Es un extracto independiente. No reemplaza ni modifica ninguna de las
/// estadísticas que ya existen, no toca el publicador, ni las tarjetas, ni el
/// reinicio mensual, ni un solo campo de las direcciones. La única escritura
/// que hace es archivar el cierre de cada ciclo en la colección nueva
/// `sesiones_territorio`, porque el reinicio mensual borra `fecha_predicacion`
/// y sin ese archivo el tiempo invertido se pierde para siempre.
///
/// Qué mide
///
/// SOLO las direcciones marcadas como `completada` ("se predicó"). Las que
/// están en la bandeja de temporales, las que se dejaron como no predicadas y
/// las que se retiraron NO cuentan como avance, por pedido explícito: la barra
/// responde "cuántas se predicaron", no "cuántas se visitaron".
///
/// Territorio dinámico
///
/// Cuando entra una dirección nueva, el denominador crece y la barra baja. Eso
/// no se esconde: cada llegada queda registrada aparte y se puede abrir una por
/// una con su fecha. Y mientras haya llegadas sin trabajar, el territorio NO se
/// marca como completo aunque el resto esté al 100%.
class SeccionProgresoTerritorios extends StatefulWidget {
  const SeccionProgresoTerritorios({super.key});

  @override
  State<SeccionProgresoTerritorios> createState() =>
      _SeccionProgresoTerritoriosState();
}

class _SeccionProgresoTerritoriosState
    extends State<SeccionProgresoTerritorios> {
  /// Se guarda el Future para no releer Firestore en cada rebuild. Se rehace
  /// solo cuando el usuario pide recargar.
  late Future<ResumenSesionesTerritorio> _futuro;

  @override
  void initState() {
    super.initState();
    _futuro = SesionesTerritorioService.cargar();
  }

  void _recargar() {
    setState(() {
      _futuro = SesionesTerritorioService.cargar();
    });
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<ResumenSesionesTerritorio>(
      future: _futuro,
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return _cajaNota(
            child: Row(
              children: [
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: _acento,
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  context.t('ses_loading'),
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ],
            ),
          );
        }

        final resumen = snap.data;
        final sesiones = resumen?.sesiones ?? const <SesionTerritorio>[];

        if (sesiones.isEmpty) {
          return _cajaNota(child: Text(context.t('ses_empty')));
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _cajaNota(child: _textoNota(context, sesiones)),
            if (resumen != null && !resumen.cobertura.completa) ...[
              const SizedBox(height: 8),
              _cajaNota(child: _textoCobertura(context, resumen.cobertura)),
            ],
            const SizedBox(height: 12),
            ...sesiones.map((s) => _tarjeta(context, s)),
          ],
        );
      },
    );
  }

  /// Las direcciones que quedaron fuera de los denominadores se dicen
  /// explícitamente. Un total que esconde 12 direcciones sin decir nada se lee
  /// como "esas direcciones no existen", que es falso.
  Widget _textoCobertura(BuildContext context, CoberturaDirecciones c) {
    final partes = <String>[
      if (c.enTerritoriosBase > 0)
        context.t('ses_cov_base', args: ['${c.enTerritoriosBase}']),
      if (c.sinTerritorio > 0)
        context.t('ses_cov_sin_territorio', args: ['${c.sinTerritorio}']),
    ];
    return Text(
      context.t('ses_cov_total',
          args: ['${c.medidas}', '${c.total}', partes.join(' ')]),
      style: const TextStyle(
          fontSize: 10, color: Colors.orangeAccent, height: 1.4),
    );
  }

  // ── Encabezado y resumen ────────────────────────────────────────────

  Widget _textoNota(BuildContext context, List<SesionTerritorio> sesiones) {
    final completas = sesiones.where((s) => s.completo).length;
    final preds = sesiones.fold<int>(
      0,
      (a, s) => a + (s.progreso?.idsPredicadas.length ?? 0),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.flag_outlined, size: 16, color: _acento),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                context.t('ses_section_title'),
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: _acento,
                ),
              ),
            ),
            IconButton(
              onPressed: _recargar,
              icon: const Icon(Icons.refresh, size: 16, color: _acento),
              tooltip: context.t('ses_refresh'),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          context.t('ses_note'),
          style: const TextStyle(fontSize: 10, color: Colors.grey, height: 1.4),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            _chip(
              context.t('ses_predicated', args: ['$preds']),
              _acento,
              icon: Icons.check_circle_outline,
            ),
            const SizedBox(width: 6),
            _chip(
              context.t('ses_complete_count', args: ['$completas']),
              _verde,
              icon: Icons.verified_outlined,
            ),
            const SizedBox(width: 6),
            _chip(
              context.t('ses_total_count', args: ['${sesiones.length}']),
              Colors.grey,
              icon: Icons.map_outlined,
            ),
          ],
        ),
        const SizedBox(height: 12),
        _barraGeneral(context, ProgresoGeneral.deSesiones(sesiones)),
      ],
    );
  }

  /// Barra de progreso general: el total de todos los territorios juntos.
  ///
  /// Va arriba de las barras individuales y usa la misma escala de color, para
  /// que se lea "el conjunto va en X" y abajo el detalle de por qué.
  Widget _barraGeneral(BuildContext context, ProgresoGeneral g) {
    final pct = g.porcentaje;
    final color = _colorBarra(pct);
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  context.t('ses_overall'),
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF263238),
                  ),
                ),
              ),
              Text(
                '${g.completadas} / ${g.total}',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: color,
                ),
              ),
              const SizedBox(width: 6),
              SizedBox(
                width: 46,
                child: Text(
                  '${pct.toStringAsFixed(1)}%',
                  textAlign: TextAlign.right,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: color,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          _barra(pct, color),
          const SizedBox(height: 6),
          Text(
            context.t('ses_overall_pending', args: ['${g.pendientes}']),
            style:
                const TextStyle(fontSize: 10, color: Colors.grey, height: 1.4),
          ),
        ],
      ),
    );
  }

  // ── Tarjeta de un territorio ─────────────────────────────────────────

  Widget _tarjeta(BuildContext context, SesionTerritorio s) {
    final p = s.progreso;
    // `porcentajeMostrado` y no `p.porcentaje`: un territorio que ya estaba
    // completo cuando se lo miró tiene denominador 0 y su progreso real no
    // significa nada, pero la barra tiene que verse llena porque lo está.
    final pct = s.porcentajeMostrado;
    final preds = p?.idsPredicadas.length ?? 0;
    final total = p?.totalEnJuego ?? 0;
    final color = _colorBarra(pct);

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _acento.withOpacity(0.18)),
        boxShadow: [
          BoxShadow(
            color: _acento.withOpacity(0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => _abrirDetalle(context, s),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          s.territorioNombre,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                            color: Color(0xFF263238),
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          context.t('ses_predicated_of', args: [
                            '$preds',
                            '$total',
                          ]),
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.grey[600],
                          ),
                        ),
                      ],
                    ),
                  ),
                  _estadoBadge(context, s),
                  const SizedBox(width: 8),
                  Text(
                    '${pct.toStringAsFixed(0)}%',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      color: color,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              _barra(pct, color),
              const SizedBox(height: 10),
              _chips(context, s),
              if (s.duracion != null) ...[
                const SizedBox(height: 10),
                _lineaTiempo(context, s),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _barra(double pct, Color color) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: LinearProgressIndicator(
        value: (pct / 100).clamp(0, 1),
        minHeight: 8,
        backgroundColor: Colors.grey.shade100,
        valueColor: AlwaysStoppedAnimation<Color>(color),
      ),
    );
  }

  Widget _chips(BuildContext context, SesionTerritorio s) {
    final p = s.progreso;
    final chips = <Widget>[];

    // Llegadas: el dato que explica por qué la barra retrocedió.
    if (s.idsLlegados.isNotEmpty) {
      final pend = s.llegadosPendientes;
      chips.add(
        _chip(
          context.t('ses_arrived', args: ['${s.idsLlegados.length}']),
          pend > 0 ? Colors.orange : _verde,
          icon: Icons.call_received,
        ),
      );
    }
    if ((p?.idsEnTemporal.length ?? 0) > 0) {
      chips.add(
        _chip(
          context.t('ses_in_temporal', args: ['${p!.idsEnTemporal.length}']),
          Colors.blueGrey,
          icon: Icons.schedule,
        ),
      );
    }
    if (s.completadasPrevias > 0) {
      chips.add(
        _chip(
          context.t('ses_previous', args: ['${s.completadasPrevias}']),
          Colors.grey,
          icon: Icons.history,
        ),
      );
    }
    if ((p?.retiradas ?? 0) > 0) {
      chips.add(
        _chip(
          context.t('ses_retired', args: ['${p!.retiradas}']),
          Colors.grey,
          icon: Icons.remove_circle_outline,
        ),
      );
    }

    if (chips.isEmpty) return const SizedBox.shrink();

    return Wrap(spacing: 6, runSpacing: 6, children: chips);
  }

  /// Línea de tiempo compacta: sirve para escanear sin abrir el detalle.
  Widget _lineaTiempo(BuildContext context, SesionTerritorio s) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: _acento.withOpacity(0.05),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          const Icon(Icons.timer_outlined, size: 14, color: _acento),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              s.cierreEn != null
                  ? context.t('ses_finished_in', args: [
                      _duracion(s.duracion),
                      _fecha(s.cierreEn!),
                    ])
                  : context.t('ses_running_for', args: [
                      _duracion(s.transcurrido),
                      s.ritmo.toStringAsFixed(1),
                    ]),
              style: const TextStyle(
                fontSize: 11,
                color: Color(0xFF00695C),
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _estadoBadge(BuildContext context, SesionTerritorio s) {
    late String label;
    late Color color;
    if (s.sinMedir) {
      label = context.t('ses_state_no_measure');
      color = _verde;
    } else if (s.completo) {
      label = context.t('ses_state_closed');
      color = _verde;
    } else if (s.estado == kSesionEnCurso) {
      label = context.t('ses_state_running');
      color = Colors.orange;
    } else {
      label = context.t('ses_state_open');
      color = Colors.grey;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style:
            TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: color),
      ),
    );
  }

  // ── Detalle ──────────────────────────────────────────────────────────

  Future<void> _abrirDetalle(BuildContext context, SesionTerritorio s) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _HojaDetalleSesion(sesion: s, alRecargar: _recargar),
    );
  }

  // ── Utilidades ───────────────────────────────────────────────────────

  static const Color _acento = Color(0xFF00796B);
  static const Color _verde = Color(0xFF1B5E20);

  static Color _colorBarra(double pct) {
    if (pct >= 100) return _verde;
    if (pct >= 50) return Colors.orange;
    return Colors.red.shade700;
  }

  Widget _cajaNota({required Widget child}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _acento.withOpacity(0.04),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _acento.withOpacity(0.15)),
      ),
      child: child,
    );
  }

  Widget _chip(String texto, Color color, {IconData? icon}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 11, color: color),
            const SizedBox(width: 4),
          ],
          Text(
            texto,
            style: TextStyle(
                fontSize: 10, fontWeight: FontWeight.w600, color: color),
          ),
        ],
      ),
    );
  }

  static String _fecha(DateTime d) => AppDateUtils.formatearFechaHora(d);

  /// "2d 4h" / "4h 30m" / "12m"
  static String _duracion(Duration? d) {
    if (d == null) return '—';
    if (d.inDays > 0) return '${d.inDays}d ${d.inHours % 24}h';
    if (d.inHours > 0) return '${d.inHours}h ${d.inMinutes % 60}m';
    return '${d.inMinutes}m';
  }
}

/// Hoja de detalle de una sesión: el panel de tiempo completo.
class _HojaDetalleSesion extends StatefulWidget {
  final SesionTerritorio sesion;
  final VoidCallback alRecargar;

  const _HojaDetalleSesion({required this.sesion, required this.alRecargar});

  @override
  State<_HojaDetalleSesion> createState() => _HojaDetalleSesionState();
}

class _HojaDetalleSesionState extends State<_HojaDetalleSesion> {
  Future<List<SesionTerritorio>>? _historial;
  bool _llegadosAbierto = false;

  @override
  void initState() {
    super.initState();
    // El historial se pide al abrir la hoja, no en la carga general: son
    // documentos que casi nadie mira y no vale la pena traerlos siempre.
    _historial =
        SesionesTerritorioService.historial(widget.sesion.territorioId);
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.sesion;
    final p = s.progreso;
    final pct = p?.porcentaje ?? 0;
    final color = _SeccionProgresoTerritoriosState._colorBarra(pct);

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.85,
      ),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),

            // ── Barra grande ────────────────────────────────────────
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        s.territorioNombre,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF263238),
                        ),
                      ),
                      Text(
                        context.t('ses_cycle', args: [s.ciclo]),
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.grey[600],
                        ),
                      ),
                    ],
                  ),
                ),
                Text(
                  '${pct.toStringAsFixed(0)}%',
                  style: TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.bold,
                    color: color,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(5),
              child: LinearProgressIndicator(
                value: (pct / 100).clamp(0, 1),
                minHeight: 10,
                backgroundColor: Colors.grey.shade100,
                valueColor: AlwaysStoppedAnimation<Color>(color),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              context.t('ses_predicated_of', args: [
                '${p?.idsPredicadas.length ?? 0}',
                '${p?.totalEnJuego ?? 0}',
              ]),
              style: TextStyle(fontSize: 11, color: Colors.grey[600]),
            ),

            const SizedBox(height: 16),

            // ── Anti 100% falso ────────────────────────────────────
            // OJO: la condición es `!completo`, no `completo`. `completo` ya
            // exige `llegadosPendientes == 0`, así que la versión anterior de
            // esta línea era dead code y el aviso no se mostraba nunca, que es
            // justo lo contrario de lo que debía hacer.
            if (!s.completo && s.llegadosPendientes > 0)
              _aviso(
                context.t('ses_anti_false', args: ['${s.llegadosPendientes}']),
                Colors.orange,
              ),
            if (s.sinMedir)
              _aviso(context.t('ses_no_measure_hint'), Colors.blueGrey),
            if ((p?.retiradasSinRastro ?? 0) > 0)
              _aviso(
                context.t('ses_no_follow', args: ['${p!.retiradasSinRastro}']),
                Colors.red,
              ),

            const SizedBox(height: 4),
            _panelTiempo(context, s),
            const SizedBox(height: 14),

            if (s.completadasPrevias > 0)
              Text(
                context
                    .t('ses_previous_note', args: ['${s.completadasPrevias}']),
                style: const TextStyle(
                  fontSize: 10,
                  color: Colors.grey,
                  height: 1.4,
                ),
              ),

            // ── Llegadas ──────────────────────────────────────────
            if (s.idsLlegados.isNotEmpty) ...[
              const SizedBox(height: 14),
              _bloqueLlegadas(context, s),
            ],

            // ── Tiempo por tarjeta ────────────────────────────────
            if ((p?.tarjetas.isNotEmpty ?? false)) ...[
              const SizedBox(height: 14),
              _bloqueTarjetas(context, s),
            ],

            // ── Historial ─────────────────────────────────────────
            const SizedBox(height: 14),
            _bloqueHistorial(context),
          ],
        ),
      ),
    );
  }

  Widget _panelTiempo(BuildContext context, SesionTerritorio s) {
    // Sin medición no hay fechas que mostrar. Decir "esperando la primera
    // dirección" acá sería mentir: no se está esperando nada, el trabajo ya
    // estaba hecho antes de que existiera la sesión.
    if (s.sinMedir) {
      return _aviso(context.t('ses_no_measure_hint'), Colors.blueGrey);
    }
    if (s.inicioEn == null) {
      return _aviso(context.t('ses_waiting_first'), Colors.blueGrey);
    }

    final filas = <Widget>[
      _fila(
        context.t('ses_start'),
        _SeccionProgresoTerritoriosState._fecha(s.inicioEn!),
      ),
    ];

    if (s.cierreEn != null) {
      filas.add(
        _fila(
          context.t('ses_close'),
          _SeccionProgresoTerritoriosState._fecha(s.cierreEn!),
        ),
      );
      filas.add(
        _fila(
          context.t('ses_duration'),
          _SeccionProgresoTerritoriosState._duracion(s.duracion),
        ),
      );
    } else {
      filas.add(
        _fila(
          context.t('ses_elapsed'),
          _SeccionProgresoTerritoriosState._duracion(s.transcurrido),
        ),
      );
      final proy = s.proyeccion;
      if (proy != null) {
        filas.add(
          _fila(
            context.t('ses_projection'),
            AppDateUtils.formatearFecha(proy),
          ),
        );
      }
    }

    filas.add(
      _fila(
        context.t('ses_pace'),
        '${s.ritmo.toStringAsFixed(1)} / día',
      ),
    );

    if (s.reaperturas > 0) {
      filas.add(
        _fila(
          context.t('ses_reopenings'),
          '${s.reaperturas}',
        ),
      );
    }

    if (s.cierrePrimeraVezEn != null && s.reaperturas > 0) {
      filas.add(
        _fila(
          context.t('ses_first_close'),
          _SeccionProgresoTerritoriosState._fecha(s.cierrePrimeraVezEn!),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF00796B).withOpacity(0.05),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFF00796B).withOpacity(0.15)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            context.t('ses_time_title'),
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: Color(0xFF00796B),
            ),
          ),
          const SizedBox(height: 8),
          ...filas,
        ],
      ),
    );
  }

  Widget _fila(String label, String valor) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: const TextStyle(fontSize: 11, color: Colors.grey),
            ),
          ),
          Text(
            valor,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: Color(0xFF263238),
            ),
          ),
        ],
      ),
    );
  }

  Widget _bloqueLlegadas(BuildContext context, SesionTerritorio s) {
    final pend = s.llegadosPendientes;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: () => setState(() => _llegadosAbierto = !_llegadosAbierto),
          child: Row(
            children: [
              const Icon(Icons.call_received,
                  size: 14, color: Color(0xFF00796B)),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  context.t('ses_arrived_title',
                      args: ['${s.idsLlegados.length}']),
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF263238),
                  ),
                ),
              ),
              if (pend > 0)
                Text(
                  context.t('ses_arrived_pending', args: ['$pend']),
                  style: const TextStyle(
                    fontSize: 10,
                    color: Colors.orange,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              Icon(
                _llegadosAbierto ? Icons.expand_less : Icons.expand_more,
                size: 18,
                color: Colors.grey,
              ),
            ],
          ),
        ),
        const SizedBox(height: 6),
        Text(
          context.t('ses_arrived_note'),
          style: const TextStyle(fontSize: 10, color: Colors.grey, height: 1.4),
        ),
        if (_llegadosAbierto) ...[
          const SizedBox(height: 8),
          ...s.llegadas.map(
            (l) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(
                children: [
                  Icon(
                    l.completada
                        ? Icons.check_circle
                        : Icons.radio_button_unchecked,
                    size: 13,
                    color: l.completada ? Colors.green : Colors.orange,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      l.calle,
                      style: const TextStyle(fontSize: 11),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Text(
                    l.creadaEn != null
                        ? AppDateUtils.formatearFecha(l.creadaEn!)
                        : '—',
                    style: const TextStyle(fontSize: 10, color: Colors.grey),
                  ),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _bloqueTarjetas(BuildContext context, SesionTerritorio s) {
    final tarjetas = s.progreso!.tarjetas;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          context.t('ses_cards_title'),
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: Color(0xFF263238),
          ),
        ),
        const SizedBox(height: 6),
        ...tarjetas.map(
          (t) => Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Row(
              children: [
                Icon(
                  t.completada
                      ? Icons.check_box
                      : Icons.check_box_outline_blank,
                  size: 13,
                  color: t.completada ? Colors.green : Colors.grey,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    t.nombre,
                    style: const TextStyle(fontSize: 11),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Text(
                  t.duracion != null
                      ? _SeccionProgresoTerritoriosState._duracion(t.duracion)
                      : '—',
                  style: const TextStyle(fontSize: 10, color: Colors.grey),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _bloqueHistorial(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          context.t('ses_history'),
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: Color(0xFF263238),
          ),
        ),
        const SizedBox(height: 6),
        FutureBuilder<List<SesionTerritorio>>(
          future: _historial,
          builder: (context, snap) {
            if (snap.connectionState == ConnectionState.waiting) {
              return const Padding(
                padding: EdgeInsets.all(8),
                child: LinearProgressIndicator(minHeight: 2),
              );
            }
            final lista = (snap.data ?? const <SesionTerritorio>[])
                .where((e) => e.ciclo != widget.sesion.ciclo)
                .toList();
            if (lista.isEmpty) {
              return Text(
                context.t('ses_no_history'),
                style: const TextStyle(fontSize: 10, color: Colors.grey),
              );
            }
            return Column(
              children: lista.map((e) {
                final d = e.duracion;
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          e.ciclo,
                          style: const TextStyle(fontSize: 11),
                        ),
                      ),
                      Text(
                        d != null
                            ? _SeccionProgresoTerritoriosState._duracion(d)
                            : (e.estado == kSesionCerrada
                                ? '—'
                                : context.t('ses_state_open')),
                        style: const TextStyle(
                          fontSize: 10,
                          color: Colors.grey,
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
            );
          },
        ),
      ],
    );
  }

  Widget _aviso(String texto, Color color) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.warning_amber_rounded, size: 14, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              texto,
              style: TextStyle(fontSize: 10, color: color, height: 1.4),
            ),
          ),
        ],
      ),
    );
  }
}
