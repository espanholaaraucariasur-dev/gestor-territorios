import 'dart:math';
import 'package:flutter/material.dart';
import '../../../../core/l10n/translation_service.dart';
import '../../data/arreglo_service.dart';
import '../../data/notificacion_service.dart';
import '../../models/funcion_model.dart';
import '../../models/arreglo_model.dart';
import '../../models/usuario_eco2_model.dart';

class CrearArregloScreen extends StatefulWidget {
  final Funcion funcion;
  final List<UsuarioEco2> usuariosDisponibles;
  final Color color;
  final Arreglo? arregloExistente;

  const CrearArregloScreen({
    super.key,
    required this.funcion,
    required this.usuariosDisponibles,
    required this.color,
    this.arregloExistente,
  });

  @override
  State<CrearArregloScreen> createState() => _CrearArregloScreenState();
}

class _CrearArregloScreenState extends State<CrearArregloScreen> {
  final _tituloCtrl = TextEditingController();
  String _duracion = '1_mes';
  DateTime _fechaInicio = DateTime.now();
  late List<SlotArreglo> _slots;
  bool _guardando = false;

  @override
  void initState() {
    super.initState();
    if (widget.arregloExistente != null) {
      final arr = widget.arregloExistente!;
      _tituloCtrl.text = arr.titulo;
      _duracion = arr.duracion;
      _fechaInicio = arr.fechaInicio;
      _slots = List.from(arr.slots);
    } else {
      _tituloCtrl.text = '${widget.funcion.nombre} - ${_mesNombre(_fechaInicio.month)} ${_fechaInicio.year}';
      _slots = [];
    }
    _generarSlots();
  }

  @override
  void dispose() {
    _tituloCtrl.dispose();
    super.dispose();
  }

  void _generarSlots() {
    final semanas = _duracion == '1_semana'
        ? 1
        : _duracion == '1_mes'
            ? 4
            : 13;

    final nuevosSlots = <SlotArreglo>[];
    for (int semana = 1; semana <= semanas; semana++) {
      final inicioSemana =
          _fechaInicio.add(Duration(days: (semana - 1) * 7));
      for (final reunion in widget.funcion.reuniones) {
        final diaSemana = reunion == 'entre_semana'
            ? _diaSemana(inicioSemana.add(const Duration(days: 2)))
            : _diaSemana(inicioSemana.add(const Duration(days: 5)));
        final hora = reunion == 'entre_semana' ? '19:00' : '10:00';
        for (final campo in widget.funcion.campos) {
          final existente = _slots.firstWhere(
            (s) =>
                s.campoId == campo.id &&
                s.reunionTipo == reunion &&
                s.semanaNumero == semana,
            orElse: () => SlotArreglo(
              slotId: '',
              campoId: '',
              reunionTipo: '',
              diaSemana: '',
              hora: '',
              semanaNumero: 0,
            ),
          );
          nuevosSlots.add(SlotArreglo(
            slotId:
                existente.slotId.isNotEmpty ? existente.slotId : _generarId(),
            campoId: campo.id,
            reunionTipo: reunion,
            diaSemana: diaSemana,
            hora: hora,
            usuarioUid: existente.estaAsignado ? existente.usuarioUid : null,
            estado: existente.estado != 'asignado'
                ? existente.estado
                : 'asignado',
            motivoRecusa: existente.motivoRecusa,
            semanaNumero: semana,
          ));
        }
      }
    }
    setState(() => _slots = nuevosSlots);
  }

  String _generarId() {
    final rand = Random();
    final ts = DateTime.now().millisecondsSinceEpoch;
    final suffix = rand.nextInt(999999).toString().padLeft(6, '0');
    return '${ts}_$suffix';
  }

  String _diaSemana(DateTime fecha) {
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

  @override
  Widget build(BuildContext context) {
    final semanas = _duracion == '1_semana'
        ? 1
        : _duracion == '1_mes'
            ? 4
            : 13;

    return Scaffold(
      backgroundColor: const Color(0xFFF1F8E9),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        flexibleSpace: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                widget.color,
                widget.color.withValues(alpha: 0.7)
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
        ),
        title: Text(
          widget.arregloExistente != null
              ? context.t('eco2_editar_arreglo')
              : context.t('eco2_crear_arreglo'),
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
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildFormularioBase(),
            const SizedBox(height: 16),
            _buildSeccionesSemanales(semanas),
            const SizedBox(height: 20),
            _buildBotonesAccion(),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  Widget _buildFormularioBase() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            context.t('eco2_datos_arreglo'),
            style: const TextStyle(
                fontWeight: FontWeight.bold, fontSize: 15),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _tituloCtrl,
            decoration: InputDecoration(
              labelText: context.t('eco2_titulo_arreglo'),
              border: const OutlineInputBorder(),
              isDense: true,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<String>(
                  value: _duracion,
                  decoration: InputDecoration(
                    labelText: context.t('eco2_duracion'),
                    border: const OutlineInputBorder(),
                    isDense: true,
                  ),
                  items: [
                    DropdownMenuItem(
                        value: '1_semana',
                        child: Text(context.t('eco2_duracion_semana'))),
                    DropdownMenuItem(
                        value: '1_mes',
                        child: Text(context.t('eco2_duracion_mes'))),
                    DropdownMenuItem(
                        value: '3_meses',
                        child: Text(context.t('eco2_duracion_trimestre'))),
                  ],
                  onChanged: (v) {
                    if (v != null) {
                      setState(() {
                        _duracion = v;
                        _tituloCtrl.text =
                            '${widget.funcion.nombre} - ${_mesNombre(_fechaInicio.month)} ${_fechaInicio.year}';
                        _generarSlots();
                      });
                    }
                  },
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: InkWell(
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: _fechaInicio,
                      firstDate: DateTime.now(),
                      lastDate:
                          DateTime.now().add(const Duration(days: 365)),
                    );
                    if (picked != null) {
                      setState(() {
                        _fechaInicio = picked;
                        _tituloCtrl.text =
                            '${widget.funcion.nombre} - ${_mesNombre(picked.month)} ${picked.year}';
                        _generarSlots();
                      });
                    }
                  },
                  child: InputDecorator(
                    decoration: InputDecoration(
                      labelText: context.t('eco2_fecha_inicio'),
                      border: const OutlineInputBorder(),
                      isDense: true,
                    ),
                    child: Text(
                      '${_fechaInicio.day}/${_fechaInicio.month}/${_fechaInicio.year}',
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSeccionesSemanales(int semanas) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '${context.t('eco2_slots_titulo')} ($semanas ${semanas == 1 ? context.t('eco2_semana') : context.t('eco2_semanas')})',
          style: const TextStyle(
              fontWeight: FontWeight.bold, fontSize: 15),
        ),
        const SizedBox(height: 8),
        ...List.generate(semanas, (i) => _buildSeccionSemana(i + 1)),
      ],
    );
  }

  Widget _buildSeccionSemana(int numeroSemana) {
    final inicioSemana =
        _fechaInicio.add(Duration(days: (numeroSemana - 1) * 7));
    final finSemana = inicioSemana.add(const Duration(days: 6));

    final slotsSemana = _slots
        .where((s) => s.semanaNumero == numeroSemana)
        .toList();

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${context.t('eco2_semana')} $numeroSemana (${inicioSemana.day}/${inicioSemana.month} - ${finSemana.day}/${finSemana.month})',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 13,
              color: widget.color,
            ),
          ),
          const SizedBox(height: 8),
          ...widget.funcion.reuniones.map((reunion) {
            final reunionLabel = reunion == 'entre_semana'
                ? context.t('eco2_entre_semana')
                : context.t('eco2_fin_semana');
            final slotsReunion =
                slotsSemana.where((s) => s.reunionTipo == reunion).toList();

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  reunionLabel,
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 12,
                    color: Colors.grey.shade700,
                  ),
                ),
                const SizedBox(height: 4),
                ...slotsReunion.map((slot) => _buildSlotEditor(slot)),
                const SizedBox(height: 8),
              ],
            );
          }),
        ],
      ),
    );
  }

  Widget _buildSlotEditor(SlotArreglo slot) {
    final index = _slots.indexWhere((s) => s.slotId == slot.slotId);
    if (index == -1) return const SizedBox.shrink();

    final campo = widget.funcion.campos.firstWhere(
      (c) => c.id == slot.campoId,
      orElse: () => widget.funcion.campos.first,
    );

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: slot.estaRecusado
            ? Colors.red.withValues(alpha: 0.05)
            : slot.estaAceptado
                ? Colors.green.withValues(alpha: 0.05)
                : widget.color.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: slot.estaRecusado
              ? Colors.red.withValues(alpha: 0.3)
              : slot.estaAceptado
                  ? Colors.green.withValues(alpha: 0.3)
                  : widget.color.withValues(alpha: 0.15),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: widget.color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Icon(
              slot.campoId == 'audio' ? Icons.volume_up : Icons.videocam,
              color: widget.color,
              size: 16,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${campo.label} · ${slot.diaSemana} ${slot.hora}',
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 11,
                  ),
                ),
                const SizedBox(height: 2),
                  DropdownButtonFormField<String>(
                    value: slot.usuarioUid,
                    isDense: true,
                    isExpanded: true,
                    hint: Text(
                    context.t('eco2_seleccionar_publicador'),
                    style: const TextStyle(fontSize: 11),
                  ),
                  items: widget.usuariosDisponibles.map((u) {
                    return DropdownMenuItem(
                      value: u.uid,
                      child: Text(
                        u.nombre,
                        style: const TextStyle(fontSize: 11),
                      ),
                    );
                  }).toList(),
                  onChanged: (uid) {
                    setState(() {
                      _slots[index] = _slots[index].copyWith(
                        usuarioUid: uid,
                        clearUsuario: uid == null,
                      );
                    });
                  },
                ),
              ],
            ),
          ),
          if (slot.estaRecusado)
            Icon(Icons.warning_amber, color: Colors.red.shade400, size: 18),
        ],
      ),
    );
  }

  Widget _buildBotonesAccion() {
    final asignados = _slots.where((s) => s.estaAsignado).length;
    final total = _slots.length;

    return Column(
      children: [
        Row(
          children: [
            Icon(Icons.info_outline, color: Colors.grey.shade500, size: 16),
            const SizedBox(width: 6),
            Text(
              '$asignados/$total ${context.t('eco2_slots_asignados')} ',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.grey.shade700,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
                onPressed: _guardando ? null : () => _guardar(false),
                child: Text(context.t('eco2_guardar_borrador')),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: ElevatedButton.icon(
                icon: _guardando
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.publish, size: 18),
                style: ElevatedButton.styleFrom(
                  backgroundColor: widget.color,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
                onPressed: _guardando ? null : () => _guardar(true),
                label: Text(context.t('eco2_publicar_arreglo')),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Future<void> _guardar(bool publicar) async {
    if (_tituloCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(context.t('eco2_titulo_requerido')),
          backgroundColor: Colors.orange.shade700,
        ),
      );
      return;
    }

    setState(() => _guardando = true);

    try {
      final fechaFin = Arreglo.calcularFechaFinDateTime(
          _fechaInicio, _duracion);

      final arreglo = Arreglo(
        id: widget.arregloExistente?.id ?? '',
        funcionId: widget.funcion.id,
        gestionadoPor: widget.arregloExistente?.gestionadoPor ?? '',
        titulo: _tituloCtrl.text.trim(),
        duracion: _duracion,
        fechaInicio: _fechaInicio,
        fechaFin: fechaFin,
        publicado: publicar,
        activo: true,
        slots: _slots,
        createdAt: widget.arregloExistente?.createdAt,
      );

      String arregloId;
      if (widget.arregloExistente != null) {
        await ArregloService.actualizar(
            widget.arregloExistente!.id, arreglo.toMap());
        arregloId = widget.arregloExistente!.id;
      } else {
        arregloId = await ArregloService.crear(arreglo);
      }

      if (publicar) {
        await ArregloService.publicar(arregloId);
        for (final slot in _slots) {
          if (slot.estaAsignado) {
            await NotificacionService.crearAsignacion(
              paraUid: slot.usuarioUid!,
              deUid: widget.arregloExistente?.gestionadoPor ?? '',
              funcionId: widget.funcion.id,
              arregloId: arregloId,
              slotId: slot.slotId,
              titulo:
                  '${context.t("eco2_nueva_asignacion")} ${slot.campoId.toUpperCase()}',
              mensaje:
                  '${slot.campoId.toUpperCase()} - ${slot.reunionTipo == "entre_semana" ? context.t("eco2_entre_semana") : context.t("eco2_fin_semana")} · ${slot.diaSemana} ${slot.hora}',
            );
          }
        }
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(publicar
                ? context.t('eco2_arreglo_publicado')
                : context.t('eco2_arreglo_guardado')),
            backgroundColor: widget.color,
          ),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${context.t('eco2_error_guardar')}: $e'),
            backgroundColor: Colors.red.shade700,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }
}
