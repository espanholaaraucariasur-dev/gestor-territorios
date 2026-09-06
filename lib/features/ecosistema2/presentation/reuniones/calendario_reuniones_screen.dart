import 'package:flutter/material.dart';
import '../../../../core/l10n/translation_service.dart';
import '../../data/arreglo_service.dart';
import '../../data/funcion_service.dart';
import '../../models/arreglo_model.dart';
import '../../models/funcion_model.dart';

class CalendarioReunionesScreen extends StatefulWidget {
  const CalendarioReunionesScreen({super.key});

  @override
  State<CalendarioReunionesScreen> createState() =>
      _CalendarioReunionesScreenState();
}

class _CalendarioReunionesScreenState extends State<CalendarioReunionesScreen> {
  DateTime _mesActual = DateTime.now();

  @override
  Widget build(BuildContext context) {
    final inicioMes = DateTime(_mesActual.year, _mesActual.month, 1);
    final finMes = DateTime(_mesActual.year, _mesActual.month + 1, 0);

    return Scaffold(
      backgroundColor: const Color(0xFFF1F8E9),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        flexibleSpace: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFF1B5E20), Color(0xFF43A047)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
        ),
        title: Text(
          context.t('eco2_reuniones_titulo'),
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 15,
          ),
        ),
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: Column(
        children: [
          _buildSelectorMes(),
          Expanded(
            child: StreamBuilder<List<Arreglo>>(
              stream: ArregloService.obtenerPublicados(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                final todos = snapshot.data ?? [];
                final delMes = todos.where((a) {
                  return a.fechaInicio.month == _mesActual.month &&
                      a.fechaInicio.year == _mesActual.year;
                }).toList();

                if (delMes.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.event_busy,
                            size: 64, color: Colors.grey.shade300),
                        const SizedBox(height: 12),
                        Text(
                          context.t('eco2_sin_reuniones'),
                          style: TextStyle(
                            color: Colors.grey.shade500,
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                  );
                }

                return _buildCalendario(delMes, inicioMes, finMes);
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSelectorMes() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      color: const Color(0xFFE8F5E9),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          IconButton(
            icon: const Icon(Icons.chevron_left, color: Color(0xFF1B5E20)),
            onPressed: () {
              setState(() {
                _mesActual = DateTime(_mesActual.year, _mesActual.month - 1);
              });
            },
          ),
          Text(
            '${_mesNombre(_mesActual.month)} ${_mesActual.year}',
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 16,
              color: Color(0xFF1B5E20),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.chevron_right, color: Color(0xFF1B5E20)),
            onPressed: () {
              setState(() {
                _mesActual = DateTime(_mesActual.year, _mesActual.month + 1);
              });
            },
          ),
        ],
      ),
    );
  }

  Widget _buildCalendario(
      List<Arreglo> arreglos, DateTime inicioMes, DateTime finMes) {
    final diasEnMes = finMes.day;
    final primerDiaSemana = inicioMes.weekday % 7;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Row(
            children: ['L', 'M', 'X', 'J', 'V', 'S', 'D'].map((d) {
              return Expanded(
                child: Center(
                  child: Text(
                    d,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                      color: Colors.grey.shade600,
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 8),
          ...List.generate((diasEnMes + primerDiaSemana + 6) ~/ 7, (semana) {
            return Row(
              children: List.generate(7, (diaSemana) {
                final dia =
                    semana * 7 + diaSemana - primerDiaSemana + 1;
                if (dia < 1 || dia > diasEnMes) {
                  return const Expanded(child: SizedBox(height: 60));
                }

                final fechaDia = DateTime(
                    _mesActual.year, _mesActual.month, dia);
                final arreglosDia =
                    _arreglosParaDia(arreglos, fechaDia);

                return Expanded(
                  child: GestureDetector(
                    onTap: arreglosDia.isNotEmpty
                        ? () => _mostrarDetalleDia(
                            fechaDia, arreglosDia)
                        : null,
                    child: Container(
                      height: 60,
                      margin: const EdgeInsets.all(2),
                      decoration: BoxDecoration(
                        color: arreglosDia.isNotEmpty
                            ? const Color(0xFF1B5E20)
                                .withValues(alpha: 0.08)
                            : null,
                        borderRadius: BorderRadius.circular(8),
                        border: arreglosDia.isNotEmpty
                            ? Border.all(
                                color: const Color(0xFF1B5E20)
                                    .withValues(alpha: 0.3),
                              )
                            : null,
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            '$dia',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: arreglosDia.isNotEmpty
                                  ? FontWeight.bold
                                  : FontWeight.normal,
                              color: arreglosDia.isNotEmpty
                                  ? const Color(0xFF1B5E20)
                                  : Colors.grey.shade700,
                            ),
                          ),
                          if (arreglosDia.isNotEmpty) ...[
                            const SizedBox(height: 2),
                            ...arreglosDia.take(2).map((a) {
                              return Container(
                                height: 6,
                                width: 20,
                                margin: const EdgeInsets.only(top: 1),
                                decoration: BoxDecoration(
                                  color: _colorFuncion(a.funcionId),
                                  borderRadius: BorderRadius.circular(2),
                                ),
                              );
                            }),
                          ],
                        ],
                      ),
                    ),
                  ),
                );
              }),
            );
          }),
          const SizedBox(height: 16),
          _buildLeyenda(arreglos),
        ],
      ),
    );
  }

  List<Arreglo> _arreglosParaDia(List<Arreglo> arreglos, DateTime fecha) {
    return arreglos.where((a) {
      return fecha.isAfter(a.fechaInicio.subtract(const Duration(days: 1))) &&
          fecha.isBefore(a.fechaFin.add(const Duration(days: 1)));
    }).toList();
  }

  Color _colorFuncion(String funcionId) {
    const colores = {
      'audio_video': Color(0xFF00695C),
      'limpieza': Color(0xFF6A1B9A),
      'microfono': Color(0xFF1565C0),
      'acomodador': Color(0xFFEF6C00),
    };
    return colores[funcionId] ?? const Color(0xFF1B5E20);
  }

  Widget _buildLeyenda(List<Arreglo> arreglos) {
    final funcionIds = arreglos.map((a) => a.funcionId).toSet().toList();
    if (funcionIds.isEmpty) return const SizedBox.shrink();

    return FutureBuilder<List<Funcion?>>(
      future: Future.wait(
          funcionIds.map((id) => FuncionService.obtenerPorIdUnaVez(id))),
      builder: (context, snapshot) {
        final funciones = snapshot.data ?? [];
        return Wrap(
          spacing: 12,
          runSpacing: 6,
          children: funciones.whereType<Funcion>().map((f) {
            return Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    color: _colorFuncion(f.id),
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
                const SizedBox(width: 4),
                Text(f.nombre, style: const TextStyle(fontSize: 11)),
              ],
            );
          }).toList(),
        );
      },
    );
  }

  void _mostrarDetalleDia(DateTime fecha, List<Arreglo> arreglos) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
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
            Text(
              '${_diaSemanaCompleto(fecha)} ${fecha.day} de ${_mesNombre(fecha.month)}',
              style: const TextStyle(
                  fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            ...arreglos.map((arreglo) {
              final slotsDia = arreglo.slots.where((s) {
                return s.diaSemana ==
                    _diaSemanaCompleto(fecha);
              }).toList();

              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    arreglo.titulo,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                      color: _colorFuncion(arreglo.funcionId),
                    ),
                  ),
                  ...slotsDia.map((slot) {
                    return Container(
                      margin: const EdgeInsets.only(
                          left: 8, top: 4, bottom: 4),
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.grey.withValues(alpha: 0.05),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            slot.campoId == 'audio'
                                ? Icons.volume_up
                                : Icons.videocam,
                            size: 16,
                            color: _colorFuncion(arreglo.funcionId),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment:
                                  CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '${slot.campoId.toUpperCase()} · ${slot.hora}',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                    fontSize: 12,
                                  ),
                                ),
                                Text(
                                  slot.usuarioUid ??
                                      context.t('eco2_sin_asignar'),
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: Colors.grey.shade600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    );
                  }),
                  const SizedBox(height: 8),
                ],
              );
            }),
          ],
        ),
      ),
    );
  }

  String _diaSemanaCompleto(DateTime fecha) {
    const dias = [
      'Lunes',
      'Martes',
      'Miércoles',
      'Jueves',
      'Viernes',
      'Sábado',
      'Domingo'
    ];
    return dias[fecha.weekday - 1];
  }

  String _mesNombre(int mes) {
    const meses = [
      '',
      'Enero',
      'Febrero',
      'Marzo',
      'Abril',
      'Mayo',
      'Junio',
      'Julio',
      'Agosto',
      'Septiembre',
      'Octubre',
      'Noviembre',
      'Diciembre'
    ];
    return meses[mes];
  }
}
