// eslint-disable-next-line prefer-const
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import '../../../../../core/services/notificacion_service.dart';
import '../../../../../core/utils/campanas_utils.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:geolocator/geolocator.dart';
// Servicios
import '../../../../../core/services/mapbox_service.dart';
import '../../../../../core/services/ruta_orden_service.dart';
import 'navegacion_screen.dart';

import '../../../../../core/services/auto_return_service.dart';
import '../../../../../core/services/offline_sync_service.dart';
// Traducciones
import '../../../../../core/l10n/translation_service.dart';
import 'enviar_direccion_card.dart';

/// Parada resuelta para la ruta en Google Maps: el valor que va en la URL
/// (coordenadas o dirección codificada) y su posición para ordenar por cercanía.
class _PuntoRuta {
  final String valor;
  final double? lat;
  final double? lng;
  final bool prioridad;

  const _PuntoRuta(this.valor, this.lat, this.lng, this.prioridad);
}

class PublicadorTab extends StatefulWidget {
  final Map<String, dynamic> usuarioData;
  final String usuarioEmail;
  final bool campanaEspecialActiva;
  final String nombreCampanaEspecial;
  final bool campanaGeneralActiva;
  final String anuncioGeneral;
  final VoidCallback onSolicitarTerritorio; // ✅ nuevo

  const PublicadorTab({
    super.key,
    required this.usuarioData,
    required this.usuarioEmail,
    required this.campanaEspecialActiva,
    required this.nombreCampanaEspecial,
    required this.campanaGeneralActiva,
    required this.anuncioGeneral,
    required this.onSolicitarTerritorio, // ✅ nuevo
  });

  @override
  State<PublicadorTab> createState() => _PublicadorTabState();
}

class _PublicadorTabState extends State<PublicadorTab> {
  static const List<Color> _tarjetaColores = [
    Color(0xFF1565C0),
    Color(0xFF2E7D32),
    Color(0xFF6A1B9A),
    Color(0xFFE65100),
    Color(0xFF00695C),
    Color(0xFFC62828),
    Color(0xFF4527A0),
    Color(0xFF558B2F),
    Color(0xFF00838F),
    Color(0xFF4E342E),
  ];

  final Map<String, Map<String, String>> _estadosPorTarjeta = {};
  final Map<String, Map<String, String>> _textosPorTarjeta = {};
  final Map<String, Map<String, bool>> _modificadosPorTarjeta = {};
  final Set<String> _tarjetasCompletadas = {};

  /// Tarjetas con una confirmación en curso.
  ///
  /// La confirmación escribe sobre varias colecciones con dos `commit()`
  /// separados, así que un doble toque lanzaba el guardado dos veces en
  /// paralelo. Con la botón deshabilitado el segundo toque ya no llega, pero
  /// el flag también protege al método: si la UI se reconstruye mientras la
  /// escritura sigue viva, `onPressed` vuelve a quedar habilitado y otro toque
  /// volvería a duplicar la operación.
  final Map<String, bool> _guardandoPorTarjeta = {};

  /// Direcciones con una confirmación individual en curso.
  ///
  /// Va por id de documento, no por tarjeta, porque con la confirmación
  /// individual el publicador puede tener varias direcciones de la misma tarjeta
  /// guardando a la vez. El flag es el mismo que en `_guardandoPorTarjeta`:
  /// guarda de reentrada en el método, `onPressed: null` en la UI, y
  /// `try/finally` para apagar el spinner.
  final Map<String, bool> _guardandoPorDireccion = {};

  /// Reconstrucción de cada tarjeta, guardada para poder apagar el botón
  /// cuando termina la escritura (que es asíncrona y sobrevive al build que
  /// la lanzó).
  final Map<String, StateSetter> _setStatePorTarjeta = {};

  Future<int?>? _completadasFuture;
  String _completadasFutureKey = '';

  /// Minutos sin tarjetas antes de enviar el mensaje motivacional.
  static const int _minutosSinTarjetasParaMotivacional = 10;

  Timer? _timerMotivacional;
  bool _tieneTarjetasActivas = false;

  /// Inicio del período que mide "Completadas este mes".
  ///
  /// Vive en `configuracion/progreso_mensual` para que sea el mismo para todos.
  /// Si todavía no existe, se crea con la hora actual: así el contador arranca
  /// en cero y solo suma las direcciones predicadas de ahí en adelante.
  DateTime? _inicioProgreso;

  @override
  void initState() {
    super.initState();
    // Configurar callback para alertas en UI
    AutoReturnService().onMostrarAlerta = (mensaje, color) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(mensaje),
            backgroundColor: color,
            duration: const Duration(seconds: 8),
          ),
        );
        // Guardar aviso en Firestore
        NotificacionService.enviarAUser(
          destinatarioNombre:
              widget.usuarioData['nombre']?.toString() ?? widget.usuarioEmail,
          titulo: '⏰ Aviso de devolución',
          cuerpo: mensaje,
          tipo: TipoNotificacion.avisoDevolucion,
        );
      }
    };
    // Verificar tarjetas asignadas al iniciar
    final nombre = widget.usuarioData['nombre']?.toString() ?? '';
    if (nombre.isNotEmpty) {
      AutoReturnService().verificarTarjetasAlIniciar(nombre);
    }

    // Verificar si hay mensaje motivacional pendiente de enviar
    Future.delayed(
        const Duration(seconds: 3), () => _verificarTareaPendiente());

    // Cargar el inicio del período de "Completadas este mes"
    _cargarInicioProgreso();
  }

  Future<void> _cargarInicioProgreso() async {
    try {
      final ref = FirebaseFirestore.instance
          .collection('configuracion')
          .doc('progreso_mensual');
      final doc = await ref.get();
      final ts = doc.data()?['inicio'];
      DateTime inicio;
      if (ts is Timestamp) {
        inicio = ts.toDate();
      } else {
        inicio = DateTime.now();
        await ref.set({
          'inicio': Timestamp.fromDate(inicio),
          'creado_en': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      }
      if (mounted) setState(() => _inicioProgreso = inicio);
    } catch (_) {
      // Si falla, el contador del mes queda en cero.
    }
  }

  Future<void> _verificarTareaPendiente() async {
    try {
      final email = widget.usuarioEmail;
      final tareaDoc = await FirebaseFirestore.instance
          .collection('tareas_motivacionales')
          .doc(email)
          .get();
      if (!tareaDoc.exists) return;
      final tarea = tareaDoc.data() as Map<String, dynamic>;
      if (tarea['enviado'] == true) return;

      final enviarEn = (tarea['enviar_en'] as Timestamp?)?.toDate();
      if (enviarEn == null) return;

      if (DateTime.now().isAfter(enviarEn)) {
        // Ya pasaron los 10 min — enviar ahora
        await _enviarMensajeMotivacional();
      } else {
        // Programar para cuando corresponda
        final resta = enviarEn.difference(DateTime.now());
        _programarTimerMotivacional(resta);
        debugPrint('⏰ Mensaje motivacional en ${resta.inMinutes} min');
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    _timerMotivacional?.cancel();
    AutoReturnService().onMostrarAlerta = null;
    super.dispose();
  }

  // ───────────────────────────────────────────────────────────
  // HELPERS
  // ───────────────────────────────────────────────────────────

  // ─────────────────────────────────────────────────────────
  // STREAM DE TARJETAS — sin collectionGroup (no requiere indice)
  // ─────────────────────────────────────────────────────────

  Stream<QuerySnapshot> _buildTarjetasStream() {
    final nombre = widget.usuarioData['nombre']?.toString() ?? '';
    return FirebaseFirestore.instance
        .collectionGroup('tarjetas')
        .where('asignado_a', isEqualTo: nombre)
        .where('completada', isEqualTo: false)
        .snapshots();
  }

  String _normalizarDireccion(String direccion) {
    var texto = direccion.toLowerCase();
    texto = texto.replaceAll(RegExp(r'cep[:\s]*\d{4,10}'), ' ');
    texto = texto.replaceAll(RegExp(r'\b\d{5}-?\d{3}\b'), ' ');
    texto = texto.replaceAll(RegExp(r'[^a-z0-9 ]'), ' ');
    texto = texto.replaceAll('apto', 'apartamento');
    texto = texto.replaceAll('apt', 'apartamento');
    texto = texto.replaceAll('dpto', 'departamento');
    texto = texto.replaceAll(RegExp(r'\s+'), ' ').trim();
    return texto;
  }

  Map<String, dynamic> _safeData(QueryDocumentSnapshot doc) {
    try {
      return (doc.data() as Map<String, dynamic>?) ?? {};
    } catch (_) {
      return {};
    }
  }

  /// Cuenta las direcciones completadas de las tarjetas asignadas.
  ///
  /// `whereIn` admite como máximo 30 valores, así que se consulta por lotes.
  Future<int> _contarCompletadas(List<String> tarjetaIds) async {
    var completadas = 0;
    for (var i = 0; i < tarjetaIds.length; i += 30) {
      final fin =
          (i + 30) < tarjetaIds.length ? i + 30 : tarjetaIds.length;
      final snap = await FirebaseFirestore.instance
          .collection('direcciones_globales')
          .where('tarjeta_id', whereIn: tarjetaIds.sublist(i, fin))
          .get();
      completadas += snap.docs.where((doc) {
        final d = _safeData(doc);
        return _esDirPredicada(d);
      }).length;
    }
    return completadas;
  }

  // Una dirección ya predicada: su resultado y su fecha ya están registrados
  // (tarjeta recibida). Solo se permite completar la entrega de campañas que
  // falten, sin reescribir el resultado de predicación.
  bool _esDirPredicada(Map<String, dynamic> data) {
    return data['predicado'] == true ||
        (data['estado_predicacion'] as String?) == 'completada';
  }

  // ───────────────────────────────────────────────────────────
  // WIDGETS REUTILIZABLES
  // ───────────────────────────────────────────────────────────

  Widget _statCard(String title, int value, IconData icon) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: const Color(0xFF1B5E20), size: 22),
          const SizedBox(height: 6),
          Text(
            value.toString(),
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Color(0xFF1B5E20),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            title,
            style: TextStyle(
              color: Colors.grey[600],
              fontSize: 11,
            ),
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  Widget _miniStat(String title, int value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(height: 4),
          Text(
            title,
            style: TextStyle(
                fontSize: 10, fontWeight: FontWeight.w600, color: color),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 2),
          Text(
            value.toString(),
            style: TextStyle(
                fontSize: 15, fontWeight: FontWeight.bold, color: color),
          ),
        ],
      ),
    );
  }

  Widget _alertaBanner({
    required IconData icon,
    required Color color,
    required Color bgColor,
    required String title,
    required String body,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 24),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: color,
                        fontSize: 14)),
                const SizedBox(height: 4),
                Text(body,
                    style:
                        TextStyle(color: color.withOpacity(0.8), fontSize: 13)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ───────────────────────────────────────────────────────────
  // DEVOLVER TARJETA
  // ───────────────────────────────────────────────────────────

  Future<void> _devolverTarjeta(String territorioId, String tarjetaId) async {
    final nombre =
        widget.usuarioData['nombre'] as String? ?? widget.usuarioEmail;
    try {
      final write = FirebaseFirestore.instance
          .collection('territorios')
          .doc(territorioId)
          .collection('tarjetas')
          .doc(tarjetaId)
          .update({
        'asignado_a': null,
        'asignado_en': null,
        'enviado_a': null,
        'enviado_nombre': null,
        'enviado_en': null,
        'enviado_tipo': null,
        'conductor_email': null,
        'publicador_email': null,
        'publicador_nombre': null,
        'tomado_por': null,
        'tomado_en': null,
        'estatus_envio': 'disponible',
        // Devolver NO bloquea la tarjeta: mientras tenga direcciones
        // pendientes y la campaña siga activa, vuelve a estar disponible.
        'bloqueado': false,
        'disponible_para_publicadores': true,
        'devuelta_por': nombre,
        'devuelta_en': Timestamp.now(),
        'completada': false,
      });

      // Las escrituras de Firestore se reflejan localmente y se sincronizan en
      // segundo plano; no esperar la confirmación de red para cerrar la acción.
      unawaited(write.catchError((Object error) {
        debugPrint('Devolución pendiente/no confirmada: $error');
      }));
      // Notificar a admins es secundario y no bloquea la devolución.
      unawaited(NotificacionService.enviarAAdminTerritorios(
        titulo: '↩️ Tarjeta devuelta',
        cuerpo: '$nombre devolvió la tarjeta "$tarjetaId"',
        tipo: TipoNotificacion.devolucionTarjeta,
        extra: {'territorio_id': territorioId, 'tarjeta_id': tarjetaId},
      ).catchError((Object error) {
        debugPrint('Notificación de devolución pendiente: $error');
      }));

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Tarjeta devuelta correctamente'),
          backgroundColor: Colors.orange,
        ),
      );
      // Verificar si ya terminó todas → programar motivacional
      unawaited(_programarMensajeMotivacional());
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error al devolver tarjeta: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  // Agenda el envío local para dentro de [espera].
  void _programarTimerMotivacional(Duration espera) {
    _timerMotivacional?.cancel();
    if (espera <= Duration.zero) {
      _enviarMensajeMotivacional();
      return;
    }
    _timerMotivacional = Timer(espera, _enviarMensajeMotivacional);
  }

  /// El publicador tomó o recibió una tarjeta: el ciclo vuelve a empezar.
  Future<void> _reiniciarCicloMotivacional() async {
    _timerMotivacional?.cancel();
    try {
      await FirebaseFirestore.instance
          .collection('tareas_motivacionales')
          .doc(widget.usuarioEmail)
          .set({
        'enviado': false,
        'enviar_en': FieldValue.delete(),
        'actualizado_en': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      debugPrint('🔄 Ciclo motivacional reiniciado (tomó tarjeta)');
    } catch (e) {
      debugPrint('Error reiniciando motivacional: $e');
    }
  }

  // Programa un mensaje motivacional en Firestore — se envía al verificar al iniciar
  Future<void> _programarMensajeMotivacional() async {
    try {
      final nombre = widget.usuarioData['nombre'] as String? ?? '';
      final email = widget.usuarioEmail;
      if (nombre.isEmpty) return;

      // Verificar si aún tiene tarjetas activas
      final activas = await FirebaseFirestore.instance
          .collectionGroup('tarjetas')
          .where('asignado_a', isEqualTo: nombre)
          .where('completada', isEqualTo: false)
          .get();

      // Si ya no tiene tarjetas, programar mensaje para dentro de 5 min
      final activasReales = activas.docs
          .where((d) =>
              (d.data() as Map<String, dynamic>?)?['enviado_tipo'] !=
              'conductor')
          .toList();
      if (activasReales.isEmpty) {
        // Verificar si ya hay una tarea pendiente o enviada recientemente
        final tareaExistente = await FirebaseFirestore.instance
            .collection('tareas_motivacionales')
            .doc(email)
            .get();

        if (tareaExistente.exists) {
          final t = tareaExistente.data() as Map<String, dynamic>;
          // Solo hay "tarea pendiente" si existe una programación vigente
          // (`enviar_en` en el futuro y aún sin enviar). Un ciclo reiniciado
          // deja `enviado:false` SIN `enviar_en`; antes eso bloqueaba la
          // reprogramación para siempre y el mensaje no volvía a llegar.
          final enviarEn = (t['enviar_en'] as Timestamp?)?.toDate();
          if (t['enviado'] != true &&
              enviarEn != null &&
              enviarEn.isAfter(DateTime.now())) {
            debugPrint(
                '📅 Ya hay tarea motivacional programada — no crear otra');
            return;
          }
          // Cooldown de 2h desde el último envío real.
          final ultimoEnvio = (t['ultimo_envio'] as Timestamp?)?.toDate();
          if (ultimoEnvio != null &&
              DateTime.now().difference(ultimoEnvio).inHours < 2) {
            debugPrint('⏳ Cooldown activo — no programar nuevo mensaje');
            return;
          }
        }

        final enviarEn = DateTime.now()
            .add(const Duration(minutes: _minutosSinTarjetasParaMotivacional));
        await FirebaseFirestore.instance
            .collection('tareas_motivacionales')
            .doc(email)
            .set({
          'email': email,
          'nombre': nombre,
          'enviar_en': Timestamp.fromDate(enviarEn),
          'enviado': false,
          'created_at': FieldValue.serverTimestamp(),
        });
        debugPrint(
            '📅 Mensaje motivacional programado para $nombre en $_minutosSinTarjetasParaMotivacional min');

        // Temporizador local (se cancela si vuelve a tomar una tarjeta)
        _programarTimerMotivacional(DateTime.now()
            .add(const Duration(minutes: _minutosSinTarjetasParaMotivacional))
            .difference(DateTime.now()));
      }
    } catch (e) {
      debugPrint('Error programando motivacional: $e');
    }
  }

  // Envía el mensaje motivacional si la tarea está pendiente
  Future<void> _enviarMensajeMotivacional() async {
    try {
      final nombre = widget.usuarioData['nombre'] as String? ?? '';
      final email = widget.usuarioEmail;
      if (nombre.isEmpty) return;

      // Verificar que la tarea aún existe y no fue enviada
      final tareaDoc = await FirebaseFirestore.instance
          .collection('tareas_motivacionales')
          .doc(email)
          .get();
      if (!tareaDoc.exists) return;
      final tarea = tareaDoc.data() as Map<String, dynamic>;
      if (tarea['enviado'] == true) return;

      // Cooldown: no enviar si ya se envió uno en las últimas 2 horas
      final ultimoEnvio = (tarea['ultimo_envio'] as Timestamp?)?.toDate();
      if (ultimoEnvio != null &&
          DateTime.now().difference(ultimoEnvio).inHours < 2) {
        debugPrint(
            '⏳ Cooldown motivacional activo — último envío hace ${DateTime.now().difference(ultimoEnvio).inMinutes} min');
        return;
      }

      // Verificar que sigue sin tarjetas
      final activas = await FirebaseFirestore.instance
          .collectionGroup('tarjetas')
          .where('asignado_a', isEqualTo: nombre)
          .where('completada', isEqualTo: false)
          .get();
      if (activas.docs
          .where((d) =>
              (d.data() as Map<String, dynamic>?)?['enviado_tipo'] !=
              'conductor')
          .isNotEmpty) {
        // Volvió a tomar/recibir tarjeta → reiniciar el ciclo, NO borrar
        await _reiniciarCicloMotivacional();
        return;
      }

      // ── Verificar que se cumplieron los 10 min sin tarjetas ──
      // (protege contra timers viejos que disparen antes de tiempo)
      final enviarEn = (tarea['enviar_en'] as Timestamp?)?.toDate();
      if (enviarEn != null && DateTime.now().isBefore(enviarEn)) {
        debugPrint(
            '⏰ Aún no cumplen 10 min — reprogramando en ${enviarEn.difference(DateTime.now()).inMinutes + 1} min');
        _programarTimerMotivacional(enviarEn.difference(DateTime.now()));
        return;
      }

      // Obtener mensaje aleatorio activo
      final msgsSnap = await FirebaseFirestore.instance
          .collection('configuracion')
          .doc('mensajes_motivacionales')
          .collection('mensajes')
          .where('activo', isEqualTo: true)
          .get();
      if (msgsSnap.docs.isEmpty) {
        // Sin mensajes configurados: cerrar la tarea para no reintentar en
        // silencio en cada apertura (antes quedaba pendiente para siempre).
        try {
          await FirebaseFirestore.instance
              .collection('tareas_motivacionales')
              .doc(email)
              .update({
            'enviado': true,
            'enviar_en': FieldValue.delete(),
            'ultimo_envio': FieldValue.serverTimestamp(),
          });
        } catch (_) {}
        debugPrint(
            'ℹ️ Sin mensajes motivacionales configurados — tarea cerrada');
        return;
      }

      final idx = DateTime.now().millisecondsSinceEpoch % msgsSnap.docs.length;
      final msgData = msgsSnap.docs[idx].data();
      final texto =
          (msgData['texto'] as String? ?? '').replaceAll('{nombre}', nombre);
      if (texto.isEmpty) return;

      // Enviar solo el mensaje configurado, sin título redundante
      await NotificacionService.enviarAUser(
        destinatarioNombre: nombre,
        titulo: '🌟 Mensaje para ti',
        cuerpo: texto,
        tipo: TipoNotificacion.motivacional,
      );

      // Marcar tarea como enviada con timestamp para cooldown
      await FirebaseFirestore.instance
          .collection('tareas_motivacionales')
          .doc(email)
          .update({
        'enviado': true,
        'ultimo_envio': FieldValue.serverTimestamp(),
      });

      debugPrint('✅ Mensaje motivacional enviado a $nombre');
    } catch (e) {
      debugPrint('Error enviando motivacional: $e');
    }
  }

  // ───────────────────────────────────────────────────────────
  // WIDGET DIRECCIONES POR TARJETA
  // ───────────────────────────────────────────────────────────

  Widget _buildDireccionesTarjeta(
      String tarjetaId, String territorioId, String tarjetaNombre,
      [String tipoTarjeta = 'normal']) {
    return StatefulBuilder(
      builder: (context, setLocalState) {
        if (!_estadosPorTarjeta.containsKey(tarjetaId)) {
          _estadosPorTarjeta[tarjetaId] = {};
          _textosPorTarjeta[tarjetaId] = {};
          _modificadosPorTarjeta[tarjetaId] = {};
        }

        // La escritura de la confirmación es asíncrona y termina después de
        // este build. Guardar el rebuilder es lo que permite apagar el botón
        // al terminar, en lugar de dejarlo habilitado para siempre.
        _setStatePorTarjeta[tarjetaId] = setLocalState;
        final guardando = _guardandoPorTarjeta[tarjetaId] == true;

        return FutureBuilder<List<DocumentSnapshot>>(
          future: Future.wait([
            FirebaseFirestore.instance
                .collection('configuracion')
                .doc('campana_1')
                .get(),
            FirebaseFirestore.instance
                .collection('configuracion')
                .doc('campana_2')
                .get(),
          ]),
          builder: (context, campSnap) {
            if (!campSnap.hasData) return const SizedBox.shrink();
            final campanasActivas = campSnap.data!.where((d) {
              final data = (d.data() as Map<String, dynamic>?) ?? {};
              return (data['activa'] as bool?) == true;
            }).toList();

            return FutureBuilder<QuerySnapshot>(
              // No se filtra `estado` en la query: `isNotEqualTo` descarta los
              // documentos SIN el campo `estado` (los que crea una versión
              // antigua de la app), y quedaban invisibles en la tarjeta aunque
              // sí contaran en el total. Se filtra en memoria.
              future: FirebaseFirestore.instance
                  .collection('direcciones_globales')
                  .where('tarjeta_id', isEqualTo: tarjetaId)
                  .get(),
              builder: (context, snapshot) {
                if (!snapshot.hasData) {
                  return const Padding(
                    padding: EdgeInsets.all(12),
                    child: Text('Sin direcciones pendientes.',
                        style: TextStyle(color: Colors.grey)),
                  );
                }

                final direcciones = snapshot.data!.docs
                    .where((d) =>
                        (_safeData(d)['estado'] as String?) != 'removida')
                    .toList();
                if (direcciones.isEmpty) {
                  return const Padding(
                    padding: EdgeInsets.all(12),
                    child: Text('Sin direcciones pendientes.',
                        style: TextStyle(color: Colors.grey)),
                  );
                }

                // Ordenar: prioridades del mes anterior primero
                final dirs = [...direcciones];
                dirs.sort((a, b) {
                  final aP =
                      (_safeData(a)['prioridad_mes_anterior'] as bool?) == true
                          ? 0
                          : 1;
                  final bP =
                      (_safeData(b)['prioridad_mes_anterior'] as bool?) == true
                          ? 0
                          : 1;
                  return aP.compareTo(bP);
                });

                final cantPrioridad = dirs
                    .where((d) =>
                        (_safeData(d)['prioridad_mes_anterior'] as bool?) ==
                        true)
                    .length;

                // ── Avance de la tarjeta ──────────────────────────────
                //
                // Se deriva de las direcciones, no de un contador guardado. Es
                // el invariante que ya declara `_camposResultadoNuevo`: no hay
                // campo que resetear ni que se pueda desfasar del mes.
                //
                // "Pendientes" son las que siguen sin resultado. Cuando llega
                // a cero, la tarjeta está lista para cerrarse: eso es el cierre
                // automático de la Fase 4 (§5.5), que todavía no existe, así que
                // por ahora la barra solo informa.
                //
                // Las direcciones confirmadas con resultado negativo se van de
                // la tarjeta (`tarjeta_id: ''` y `estado: 'removida'`), así que
                // la suma no es el total original: es lo que queda en la tarjeta
                // ahora. Por eso el texto dice "en esta tarjeta" y no "de la
                // tarjeta".
                // Criterio único de "completada" (igual que el resto de la app):
                // `predicado == true` o `estado_predicacion == 'completada'`.
                // Antes esta barra solo miraba `estado_predicacion`, así que una
                // dirección ya predicada con ese campo ausente seguía contando
                // como pendiente e inflaba la lista de pendientes.
                final cntCompletadas =
                    dirs.where((d) => _esDirPredicada(_safeData(d))).length;
                final cntPendientes = dirs.where((d) {
                  final data = _safeData(d);
                  if (_esDirPredicada(data)) return false;
                  final e =
                      (data['estado_predicacion'] as String?) ?? 'pendiente';
                  return e == 'pendiente' || e == 'asignada';
                }).length;
                final cntEnJuego = cntCompletadas + cntPendientes;
                final avance =
                    cntEnJuego > 0 ? cntCompletadas / cntEnJuego : 0.0;

                if (_estadosPorTarjeta[tarjetaId]!.isEmpty) {
                  for (final dir in dirs) {
                    final data = _safeData(dir);
                    _estadosPorTarjeta[tarjetaId]![dir.id] =
                        _esDirPredicada(data)
                            ? 'completada'
                            : ((data['estado_predicacion'] as String?) ??
                                'pendiente');
                    _textosPorTarjeta[tarjetaId]![dir.id] = '';
                    _modificadosPorTarjeta[tarjetaId]![dir.id] = false;
                    for (final campDoc in campanasActivas) {
                      final cd =
                          (campDoc.data() as Map<String, dynamic>?) ?? {};
                      final n = (cd['nombre'] as String?) ?? '';
                      if (n.isEmpty) continue;
                      final k = 'campana_inv_${n}_${dir.id}';
                      final entregada = data['campana_invitacion_$n'] == true ||
                          data['campana_estado'] == 'entregada';
                      _estadosPorTarjeta[tarjetaId]![k] =
                          entregada ? 'true' : 'false';
                    }
                  }
                }

                return Column(
                  children: [
                    // Banner de prioridades si hay pendientes del mes anterior
                    if (cantPrioridad > 0)
                      Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: Colors.orange.shade50,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: Colors.orange.shade300),
                        ),
                        child: Row(children: [
                          const Icon(Icons.priority_high,
                              color: Colors.orange, size: 16),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              '⚠️ $cantPrioridad dirección(es) pendiente(s) del mes anterior',
                              style: const TextStyle(
                                  fontSize: 12,
                                  color: Colors.orange,
                                  fontWeight: FontWeight.w600),
                            ),
                          ),
                        ]),
                      ),

                    // ── Barra de avance de la tarjeta ─────────
                    Container(
                      margin: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 10),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1B5E20).withOpacity(0.05),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                            color: const Color(0xFF1B5E20).withOpacity(0.18)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(children: [
                            const Icon(Icons.donut_large,
                                size: 15, color: Color(0xFF1B5E20)),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                'Avance de la tarjeta',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.grey[800],
                                ),
                              ),
                            ),
                            Text(
                              '$cntCompletadas / $cntEnJuego',
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF1B5E20),
                              ),
                            ),
                          ]),
                          const SizedBox(height: 8),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(6),
                            child: LinearProgressIndicator(
                              value: avance,
                              minHeight: 7,
                              backgroundColor: Colors.grey.shade300,
                              valueColor: AlwaysStoppedAnimation<Color>(
                                cntPendientes == 0
                                    ? const Color(0xFF2E7D32)
                                    : const Color(0xFF1B5E20),
                              ),
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            cntPendientes == 0
                                ? 'Sin pendientes en esta tarjeta.'
                                : '$cntPendientes pendiente(s) por confirmar.',
                            style: TextStyle(
                                fontSize: 11, color: Colors.grey[600]),
                          ),
                        ],
                      ),
                    ),

                    // ── Lista de direcciones ──────────────────
                    ...dirs.map((dirDoc) {
                      final data = _safeData(dirDoc);
                      final estadoLocal =
                          _estadosPorTarjeta[tarjetaId]![dirDoc.id] ??
                              'pendiente';
                      final esComercial = tipoTarjeta == 'zona';
                      final otroTexto =
                          _textosPorTarjeta[tarjetaId]![dirDoc.id] ?? '';
                      final comentarioActivo = _estadosPorTarjeta[tarjetaId]![
                              'comentario_${dirDoc.id}'] ==
                          'true';
                      // Una dirección que ya está predicada dentro de una
                      // tarjeta recibida es de SOLO LECTURA: no se puede volver
                      // a marcar ni reenviar, su resultado ya está registrado.
                      final esPredicada = (data['predicado'] == true) ||
                          (data['estado_predicacion'] as String?) ==
                              'completada';
                      // Campañas activas que todavía no se entregaron en esta
                      // dirección. Para una dirección ya predicada (solo
                      // lectura) es lo único que se puede completar.
                      final campanasNoEntregadas = esComercial
                          ? const <String>[]
                          : campanasActivas
                              .map((c) {
                                final cd =
                                    (c.data() as Map<String, dynamic>?) ?? {};
                                return (cd['nombre'] as String?) ?? '';
                              })
                              .where((n) =>
                                  n.isNotEmpty &&
                                  data['campana_invitacion_$n'] != true &&
                                  data['campana_estado'] != 'entregada')
                              .toList();
                      final hayCampanaMarcada = campanasNoEntregadas.any((n) =>
                          _estadosPorTarjeta[tarjetaId]![
                              'campana_inv_${n}_${dirDoc.id}'] ==
                          'true');
                      final calle = (data['calle'] as String?) ?? '';
                      final complemento =
                          (data['complemento'] as String?) ?? '';
                      final detalles = (data['detalles'] as String?) ?? '';
                      final esPrioridad =
                          (data['prioridad_mes_anterior'] as bool?) == true;
                      final direccionCompleta = calle;

                      Color accentColor = const Color(0xFFB0BEC5);
                      IconData estadoIcon = Icons.radio_button_unchecked;
                      if (estadoLocal == 'completada') {
                        accentColor = const Color(0xFF2E7D32);
                        estadoIcon = Icons.check_circle;
                      } else if (estadoLocal == 'comercio_cerrado') {
                        accentColor = const Color(0xFFC62828);
                        estadoIcon = Icons.store_mall_directory_outlined;
                      } else if (estadoLocal == 'no_hispano') {
                        accentColor = const Color(0xFF1565C0);
                        estadoIcon = Icons.public_off;
                      }

                      return Container(
                        margin: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                        decoration: BoxDecoration(
                          color: Theme.of(context).cardColor,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                              color: accentColor.withOpacity(0.25), width: 1),
                          boxShadow: [
                            BoxShadow(
                              color: accentColor.withOpacity(0.12),
                              blurRadius: 10,
                              offset: const Offset(0, 3),
                            ),
                          ],
                        ),
                        child: Column(
                          children: [
                            // Borde superior de color
                            Container(
                              height: 4,
                              decoration: BoxDecoration(
                                color: accentColor,
                                borderRadius: const BorderRadius.only(
                                  topLeft: Radius.circular(16),
                                  topRight: Radius.circular(16),
                                ),
                              ),
                            ),
                            Padding(
                              padding:
                                  const EdgeInsets.fromLTRB(16, 12, 16, 12),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  // Cabecera
                                  Row(
                                    children: [
                                      Icon(Icons.location_on,
                                          color: accentColor, size: 16),
                                      const SizedBox(width: 6),
                                      Expanded(
                                        child: Text(
                                          direccionCompleta,
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w700,
                                            fontSize: 14,
                                            color: Color(0xFF263238),
                                          ),
                                        ),
                                      ),
                                      if (estadoLocal != 'pendiente')
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 8, vertical: 3),
                                          decoration: BoxDecoration(
                                            color:
                                                accentColor.withOpacity(0.12),
                                            borderRadius:
                                                BorderRadius.circular(20),
                                          ),
                                          child: Icon(estadoIcon,
                                              size: 16, color: accentColor),
                                        ),

                                      // ── Enviar dirección (Fase 2) ──
                                      //
                                      // Confirma SOLO esta dirección. El botón
                                      // de la tarjeta entera sigue abajo, para
                                      // cuando el publicador prefiera working
                                      // de una sentada.
                                      //
                                      // Se habilita solo con una opción de
                                      // estado marcada: los mismos valores que
                                      // valida `_confirmarProcesamientoTarjetaInterno`,
                                      // porque una dirección de zona no admite
                                      // "No vive hispano".
                                      Builder(builder: (ctxFila) {
                                        final guardandoDir =
                                            _guardandoPorDireccion[dirDoc.id] ==
                                                true;
                                        final estadosOk = esComercial
                                            ? const {
                                                'completada',
                                                'comercio_cerrado'
                                              }
                                            : const {
                                                'completada',
                                                'no_hispano'
                                              };
                                        return Padding(
                                          padding:
                                              const EdgeInsets.only(left: 8),
                                          child: SizedBox(
                                            height: 30,
                                            child: ElevatedButton.icon(
                                              onPressed: ((estadosOk.contains(
                                                                  estadoLocal) &&
                                                              (!esPredicada ||
                                                                  estadoLocal ==
                                                                      'no_hispano')) ||
                                                          hayCampanaMarcada) &&
                                                      !guardandoDir
                                                  ? () => _confirmarDireccion(
                                                        tarjetaId,
                                                        territorioId,
                                                        tarjetaNombre,
                                                        dirDoc,
                                                        ctxFila,
                                                        tipoTarjeta,
                                                      )
                                                  : null,
                                              icon: guardandoDir
                                                  ? const SizedBox(
                                                      width: 12,
                                                      height: 12,
                                                      child:
                                                          CircularProgressIndicator(
                                                        strokeWidth: 2,
                                                        color: Colors.white,
                                                      ),
                                                    )
                                                  : const Icon(Icons.send,
                                                      size: 13),
                                              label: Text(
                                                guardandoDir ? '…' : 'Enviar',
                                                style: const TextStyle(
                                                    fontSize: 11,
                                                    fontWeight:
                                                        FontWeight.bold),
                                              ),
                                              style: ElevatedButton.styleFrom(
                                                backgroundColor:
                                                    const Color(0xFF1B5E20),
                                                foregroundColor: Colors.white,
                                                disabledBackgroundColor:
                                                    Colors.grey.shade300,
                                                disabledForegroundColor:
                                                    Colors.grey.shade600,
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                        horizontal: 10),
                                              ),
                                            ),
                                          ),
                                        );
                                      }),
                                    ],
                                  ),

                                  // Complemento
                                  if (complemento.isNotEmpty) ...[
                                    const SizedBox(height: 4),
                                    Row(children: [
                                      const SizedBox(width: 22),
                                      const Icon(Icons.apartment,
                                          size: 13, color: Colors.blueGrey),
                                      const SizedBox(width: 4),
                                      Expanded(
                                        child: Text(
                                          complemento,
                                          style: const TextStyle(
                                            fontSize: 13,
                                            color: Color(0xFF455A64),
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                      ),
                                    ]),
                                  ],

                                  // Detalles / observaciones
                                  if (detalles.isNotEmpty) ...[
                                    const SizedBox(height: 4),
                                    Container(
                                      margin: const EdgeInsets.only(left: 22),
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 8, vertical: 5),
                                      decoration: BoxDecoration(
                                        color: Colors.amber.shade50,
                                        borderRadius: BorderRadius.circular(8),
                                        border: Border.all(
                                            color: Colors.amber.shade200),
                                      ),
                                      child: Row(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          const Icon(Icons.info_outline,
                                              size: 13, color: Colors.amber),
                                          const SizedBox(width: 4),
                                          Expanded(
                                            child: Text(
                                              detalles,
                                              style: TextStyle(
                                                fontSize: 12,
                                                color: Colors.amber.shade900,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],

                                  // Badge prioridad mes anterior
                                  if (esPrioridad) ...[
                                    const SizedBox(height: 4),
                                    Container(
                                      margin: const EdgeInsets.only(left: 22),
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 8, vertical: 3),
                                      decoration: BoxDecoration(
                                        color: Colors.orange.shade50,
                                        borderRadius: BorderRadius.circular(8),
                                        border: Border.all(
                                            color: Colors.orange.shade300),
                                      ),
                                      child: const Row(children: [
                                        Icon(Icons.history,
                                            size: 12, color: Colors.orange),
                                        SizedBox(width: 4),
                                        Text('Pendiente del mes anterior',
                                            style: TextStyle(
                                                fontSize: 11,
                                                color: Colors.orange,
                                                fontWeight: FontWeight.w600)),
                                      ]),
                                    ),
                                  ],

                                  const SizedBox(height: 10),
                                  Divider(
                                      height: 1,
                                      thickness: 1,
                                      color: Colors.grey.shade100),
                                  const SizedBox(height: 8),

                                  // Aviso de solo lectura para direcciones ya
                                  // predicadas que vinieron dentro de la
                                  // tarjeta recibida.
                                  if (esPredicada) ...[
                                    Container(
                                      margin: const EdgeInsets.only(bottom: 8),
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 8, vertical: 6),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFF2E7D32)
                                            .withOpacity(0.06),
                                        borderRadius: BorderRadius.circular(8),
                                        border: Border.all(
                                            color: const Color(0xFF2E7D32)
                                                .withOpacity(0.2)),
                                      ),
                                      child: const Row(children: [
                                        Icon(Icons.lock_outline,
                                            size: 13, color: Color(0xFF2E7D32)),
                                        SizedBox(width: 6),
                                        Expanded(
                                          child: Text(
                                            'Ya predicada — no editable en esta tarjeta',
                                            style: TextStyle(
                                                fontSize: 11,
                                                color: Color(0xFF2E7D32),
                                                fontWeight: FontWeight.w600),
                                          ),
                                        ),
                                      ]),
                                    ),
                                  ],

                                  // ── Opciones de predicación ──
                                  ...(esComercial
                                          ? [
                                              {
                                                'label':
                                                    '✅ Sí visité el comercio',
                                                'value': 'completada',
                                                'color':
                                                    const Color(0xFF2E7D32),
                                                'icon':
                                                    Icons.check_circle_outline,
                                              },
                                              {
                                                'label':
                                                    '🚫 El comercio ya no existe',
                                                'value': 'comercio_cerrado',
                                                'color':
                                                    const Color(0xFFC62828),
                                                'icon': Icons
                                                    .store_mall_directory_outlined,
                                              },
                                            ]
                                          : [
                                              {
                                                'label': 'Se predicó',
                                                'value': 'completada',
                                                'color':
                                                    const Color(0xFF2E7D32),
                                                'icon':
                                                    Icons.check_circle_outline,
                                              },
                                              {
                                                'label':
                                                    'No vive hispanohablante',
                                                'value': 'no_hispano',
                                                'color':
                                                    const Color(0xFF1565C0),
                                                'icon': Icons.public_off,
                                              },
                                            ])
                                      .map((opcion) {
                                    final val = opcion['value'] as String;
                                    final color = opcion['color'] as Color;
                                    final isSelected = estadoLocal == val;

                                    // Una dirección ya predicada es de solo
                                    // lectura, salvo "No vive hispanohablante":
                                    // sacarla del listado sigue siendo una
                                    // decisión válida y no reescribe la
                                    // predicación. Sin esta excepción no había
                                    // forma de remover una dirección predicada.
                                    final bloqueada =
                                        esPredicada && val != 'no_hispano';
                                    return InkWell(
                                      onTap: bloqueada
                                          ? null
                                          : () => setLocalState(() {
                                                _estadosPorTarjeta[tarjetaId]![
                                                    dirDoc.id] = val;
                                                _modificadosPorTarjeta[
                                                        tarjetaId]![dirDoc.id] =
                                                    true;
                                              }),
                                      borderRadius: BorderRadius.circular(8),
                                      child: Padding(
                                        padding: const EdgeInsets.symmetric(
                                            vertical: 3),
                                        child: Row(
                                          children: [
                                            Radio<String>(
                                              value: val,
                                              groupValue: estadoLocal,
                                              onChanged: bloqueada
                                                  ? null
                                                  : (v) => setLocalState(() {
                                                        _estadosPorTarjeta[
                                                                tarjetaId]![
                                                            dirDoc.id] = v!;
                                                        _modificadosPorTarjeta[
                                                                tarjetaId]![
                                                            dirDoc.id] = true;
                                                      }),
                                              activeColor: color,
                                              materialTapTargetSize:
                                                  MaterialTapTargetSize
                                                      .shrinkWrap,
                                              visualDensity:
                                                  VisualDensity.compact,
                                            ),
                                            Icon(
                                              opcion['icon'] as IconData,
                                              size: 16,
                                              color: isSelected
                                                  ? color
                                                  : Colors.grey.shade400,
                                            ),
                                            const SizedBox(width: 6),
                                            Text(
                                              opcion['label'] as String,
                                              style: TextStyle(
                                                fontSize: 13,
                                                fontWeight: isSelected
                                                    ? FontWeight.w600
                                                    : FontWeight.w400,
                                                color: isSelected
                                                    ? color
                                                    : const Color(0xFF546E7A),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    );
                                  }).toList(),

                                  // ── Checkbox comentario en paralelo ──
                                  InkWell(
                                    onTap: esPredicada
                                        ? null
                                        : () => setLocalState(() {
                                              final key =
                                                  'comentario_${dirDoc.id}';
                                              _estadosPorTarjeta[tarjetaId]![
                                                      key] =
                                                  (comentarioActivo)
                                                      ? 'false'
                                                      : 'true';
                                              _modificadosPorTarjeta[
                                                  tarjetaId]![dirDoc.id] = true;
                                            }),
                                    borderRadius: BorderRadius.circular(8),
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(
                                          vertical: 3),
                                      child: Row(children: [
                                        Checkbox(
                                          value: comentarioActivo,
                                          onChanged: esPredicada
                                              ? null
                                              : (v) => setLocalState(() {
                                                    _estadosPorTarjeta[
                                                                tarjetaId]![
                                                            'comentario_${dirDoc.id}'] =
                                                        (v ?? false)
                                                            ? 'true'
                                                            : 'false';
                                                    _modificadosPorTarjeta[
                                                            tarjetaId]![
                                                        dirDoc.id] = true;
                                                  }),
                                          activeColor: const Color(0xFF6A1B9A),
                                          materialTapTargetSize:
                                              MaterialTapTargetSize.shrinkWrap,
                                          visualDensity: VisualDensity.compact,
                                        ),
                                        const Icon(Icons.edit_note,
                                            size: 16, color: Color(0xFF6A1B9A)),
                                        const SizedBox(width: 6),
                                        Text(
                                          '💬 Comentario',
                                          style: TextStyle(
                                            fontSize: 13,
                                            fontWeight: comentarioActivo
                                                ? FontWeight.w600
                                                : FontWeight.w400,
                                            color: comentarioActivo
                                                ? const Color(0xFF6A1B9A)
                                                : const Color(0xFF546E7A),
                                          ),
                                        ),
                                      ]),
                                    ),
                                  ),

                                  // Campo texto del comentario
                                  if (comentarioActivo)
                                    Padding(
                                      padding: const EdgeInsets.only(
                                          left: 36, top: 6, bottom: 4),
                                      child: TextField(
                                        readOnly: esPredicada,
                                        controller: TextEditingController(
                                            text: otroTexto)
                                          ..selection =
                                              TextSelection.fromPosition(
                                            TextPosition(
                                                offset: otroTexto.length),
                                          ),
                                        decoration: InputDecoration(
                                          hintText: esComercial
                                              ? 'Escribe un comentario...'
                                              : 'Escribe una nota...',
                                          border: OutlineInputBorder(
                                            borderRadius:
                                                BorderRadius.circular(8),
                                            borderSide: BorderSide(
                                                color: Colors.purple.shade200),
                                          ),
                                          isDense: true,
                                          filled: true,
                                          fillColor: Colors.purple.shade50,
                                        ),
                                        maxLines: 2,
                                        onChanged: (value) => setLocalState(() {
                                          _textosPorTarjeta[tarjetaId]![
                                              dirDoc.id] = value;
                                        }),
                                      ),
                                    ),

                                  // ── Checkboxes de campaña ────
                                  if (!esComercial &&
                                      campanasActivas.isNotEmpty) ...[
                                    const SizedBox(height: 8),
                                    Container(
                                      padding: const EdgeInsets.all(10),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFFE65100)
                                            .withOpacity(0.05),
                                        borderRadius: BorderRadius.circular(8),
                                        border: Border.all(
                                          color: const Color(0xFFE65100)
                                              .withOpacity(0.2),
                                        ),
                                      ),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            children: [
                                              const Icon(Icons.campaign,
                                                  color: Color(0xFFE65100),
                                                  size: 14),
                                              const SizedBox(width: 4),
                                              const Text(
                                                'Campaña especial',
                                                style: TextStyle(
                                                  fontSize: 11,
                                                  fontWeight: FontWeight.bold,
                                                  color: Color(0xFFE65100),
                                                ),
                                              ),
                                              const Spacer(),
                                              InkWell(
                                                onTap: esPredicada
                                                    ? null
                                                    : () => setLocalState(() {
                                                          _estadosPorTarjeta[
                                                                      tarjetaId]![
                                                                  'campana_oculta_${dirDoc.id}'] =
                                                              'true';
                                                        }),
                                                child: const Icon(Icons.close,
                                                    size: 16,
                                                    color: Color(0xFFE65100)),
                                              ),
                                            ],
                                          ),
                                          const SizedBox(height: 6),
                                          ...campanasActivas.map((campDoc) {
                                            final campData = (campDoc.data()
                                                    as Map<String, dynamic>?) ??
                                                {};
                                            final campNombre =
                                                (campData['nombre']
                                                        as String?) ??
                                                    'Campaña';
                                            final campKey =
                                                'campana_inv_${campNombre}_${dirDoc.id}';
                                            final marcada = _estadosPorTarjeta[
                                                    tarjetaId]![campKey] ==
                                                'true';
                                            // Ya entregada en esta dirección:
                                            // no se puede volver a marcar.
                                            final entregada =
                                                data['campana_invitacion_$campNombre'] ==
                                                        true ||
                                                    data['campana_estado'] ==
                                                        'entregada';
                                            // En una dirección ya predicada se
                                            // permite marcar solo las campañas
                                            // que todavía falten.
                                            final puedeMarcar = !entregada;

                                            return InkWell(
                                              onTap: puedeMarcar
                                                  ? () => setLocalState(() {
                                                        _estadosPorTarjeta[
                                                                    tarjetaId]![
                                                                campKey] =
                                                            marcada
                                                                ? 'false'
                                                                : 'true';
                                                      })
                                                  : null,
                                              child: Padding(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                        vertical: 2),
                                                child: Row(
                                                  children: [
                                                    Checkbox(
                                                      value: marcada,
                                                      onChanged: puedeMarcar
                                                          ? (v) =>
                                                              setLocalState(() {
                                                                _estadosPorTarjeta[
                                                                        tarjetaId]![
                                                                    campKey] = v ==
                                                                        true
                                                                    ? 'true'
                                                                    : 'false';
                                                              })
                                                          : null,
                                                      activeColor: const Color(
                                                          0xFFE65100),
                                                      materialTapTargetSize:
                                                          MaterialTapTargetSize
                                                              .shrinkWrap,
                                                      visualDensity:
                                                          VisualDensity.compact,
                                                    ),
                                                    const SizedBox(width: 4),
                                                    Expanded(
                                                      child: Text(
                                                        'Invitación entregada — $campNombre',
                                                        style: TextStyle(
                                                          fontSize: 12,
                                                          color: marcada
                                                              ? const Color(
                                                                  0xFFE65100)
                                                              : Colors
                                                                  .grey[600],
                                                          fontWeight: marcada
                                                              ? FontWeight.w600
                                                              : FontWeight
                                                                  .normal,
                                                        ),
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            );
                                          }).toList(),
                                        ],
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ],
                        ),
                      );
                    }).toList(),

                    // ── Botones ──────────────────────────────
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                      child: Column(
                        children: [
                          // Botón Ver Ruta
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton.icon(
                              onPressed: () =>
                                  _abrirRutaGoogleMapsConPestana(direcciones),
                              icon: const Icon(Icons.map_outlined, size: 18),
                              label: const Text('Ver ruta en Google Maps',
                                  style:
                                      TextStyle(fontWeight: FontWeight.bold)),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.blue.shade700,
                                foregroundColor: Colors.white,
                                padding:
                                    const EdgeInsets.symmetric(vertical: 12),
                              ),
                            ),
                          ),
                          const SizedBox(height: 8),
                          // Botón Navegar en la app
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton.icon(
                              onPressed: () => _abrirNavegacionInterna(
                                  direcciones, tarjetaNombre),
                              icon: const Icon(Icons.navigation_outlined,
                                  size: 18),
                              label: const Text('Navegar en la app',
                                  style:
                                      TextStyle(fontWeight: FontWeight.bold)),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF1565C0),
                                foregroundColor: Colors.white,
                                padding:
                                    const EdgeInsets.symmetric(vertical: 12),
                              ),
                            ),
                          ),
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              Expanded(
                                child: OutlinedButton(
                                  onPressed: () => setLocalState(() {
                                    for (final dir in direcciones) {
                                      final data = _safeData(dir);
                                      _estadosPorTarjeta[tarjetaId]![dir.id] =
                                          _esDirPredicada(data)
                                              ? 'completada'
                                              : ((data['estado_predicacion']
                                                      as String?) ??
                                                  'pendiente');
                                      _estadosPorTarjeta[tarjetaId]![
                                          'comentario_${dir.id}'] = 'false';
                                      _textosPorTarjeta[tarjetaId]![dir.id] = '';
                                      _modificadosPorTarjeta[tarjetaId]![
                                          dir.id] = false;
                                    }
                                  }),
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: Colors.black54,
                                    side:
                                        const BorderSide(color: Colors.black26),
                                    padding: const EdgeInsets.symmetric(
                                        vertical: 12),
                                  ),
                                  child: const Text('Cancelar'),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                flex: 2,
                                child: ElevatedButton.icon(
                                  onPressed: guardando
                                      ? null
                                      : () async =>
                                          _confirmarProcesamientoTarjeta(
                                            tarjetaId,
                                            territorioId,
                                            tarjetaNombre,
                                            direcciones,
                                            context,
                                            tipoTarjeta,
                                          ),
                                  icon: guardando
                                      ? const SizedBox(
                                          width: 18,
                                          height: 18,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                            color: Colors.white,
                                          ),
                                        )
                                      : const Icon(Icons.check_circle_outline,
                                          size: 18),
                                  label: Text(
                                      guardando ? 'Guardando…' : 'Confirmar',
                                      style: const TextStyle(
                                          fontWeight: FontWeight.bold)),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: const Color(0xFF1B5E20),
                                    foregroundColor: Colors.white,
                                    disabledBackgroundColor:
                                        Colors.green.shade900,
                                    padding: const EdgeInsets.symmetric(
                                        vertical: 14),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                );
              },
            );
          },
        );
      },
    );
  }

  // ───────────────────────────────────────────────────────────
  // RUTA GOOGLE MAPS
  // ───────────────────────────────────────────────────────────

  Future<void> _abrirRutaGoogleMapsConPestana(
      List<QueryDocumentSnapshot> direcciones) async {
    if (direcciones.isEmpty) return;

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('📍 Preparando ruta...'),
          duration: Duration(seconds: 10),
        ),
      );
    }

    // 1. Ubicación del usuario (origen y referencia para ordenar).
    double? origenLat;
    double? origenLng;
    try {
      final permiso = await Geolocator.requestPermission();
      if (permiso == LocationPermission.always ||
          permiso == LocationPermission.whileInUse) {
        final pos = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.high,
            timeLimit: Duration(seconds: 8),
          ),
        );
        origenLat = pos.latitude;
        origenLng = pos.longitude;
      }
    } catch (_) {}

    // 2. Resolver coordenadas (Firestore o Mapbox). Se conserva lat/lng para
    //    ordenar por cercanía; si no se pudo geocodificar, se deja el texto
    //    como último recurso para Google Maps.
    final puntos = <_PuntoRuta>[];
    for (final doc in direcciones) {
      final data = doc.data() as Map<String, dynamic>;
      final prioridad = data['prioridad_mes_anterior'] == true;

      final la = double.tryParse('${data['lat']}');
      final lo = double.tryParse('${data['lng']}');
      if (la != null && lo != null && !(la == 0 && lo == 0)) {
        puntos.add(_PuntoRuta('$la,$lo', la, lo, prioridad));
        continue;
      }

      final calle = (data['calle'] as String? ?? '').trim();
      final comp = (data['complemento'] as String? ?? '').trim();
      final texto = comp.isNotEmpty ? '$calle, $comp' : calle;

      final coords = await MapboxService.geocodificar(texto);
      if (coords != null) {
        FirebaseFirestore.instance
            .collection('direcciones_globales')
            .doc(doc.id)
            .update({'lat': coords[0], 'lng': coords[1]});
        puntos.add(_PuntoRuta(
            '${coords[0]},${coords[1]}', coords[0], coords[1], prioridad));
      } else {
        final full = comp.isNotEmpty
            ? '$calle, $comp, Araucária, PR'
            : '$calle, Araucária, PR';
        puntos.add(_PuntoRuta(
            Uri.encodeQueryComponent(full).replaceAll('+', '%20'),
            null,
            null,
            prioridad));
      }
    }

    if (mounted) ScaffoldMessenger.of(context).clearSnackBars();
    if (puntos.isEmpty) return;

    // 3. Ordenar por cercanía (prioridades primero) desde la ubicación actual.
    final coordsDirecciones = _ordenarPorCercania(puntos, origenLat, origenLng)
        .map((p) => p.valor)
        .toList();

    // 4. URL de Google Maps iniciando la navegación directamente.
    final origen = (origenLat != null && origenLng != null)
        ? '&origin=$origenLat,$origenLng'
        : '';
    const extras = '&travelmode=walking&dir_action=navigate';

    String urlString;
    if (coordsDirecciones.length == 1) {
      urlString = 'https://www.google.com/maps/dir/?api=1$origen'
          '&destination=${coordsDirecciones.first}$extras';
    } else {
      final destino = coordsDirecciones.last;
      // Waypoints = todas menos la última, separadas por | LITERAL
      final waypoints =
          coordsDirecciones.sublist(0, coordsDirecciones.length - 1).join('|');

      urlString = 'https://www.google.com/maps/dir/?api=1$origen'
          '&destination=$destino'
          '&waypoints=$waypoints$extras';
    }

    // En iOS, con un solo destino se prefiere Apple Maps; el resto usa Google Maps
    // y se fuerza una pestaña nueva. Usamos la pestaña ya abierta.
    if (defaultTargetPlatform == TargetPlatform.iOS &&
        coordsDirecciones.length == 1) {
      final latLng = coordsDirecciones.first;
      final appleUri = Uri.parse('https://maps.apple.com/?q=$latLng');
      try {
        final ok = await launchUrl(appleUri,
            mode: LaunchMode.externalApplication, webOnlyWindowName: '_blank');
        if (ok) return;
      } catch (_) {}
    }

    // Abrir Google Maps en la pestaña ya existente (solución para iOS)
    try {
      // Google Maps URL para todas las plataformas
      final String urlGoogleMaps = urlString;
      final ok = await launchUrl(Uri.parse(urlGoogleMaps),
          mode: LaunchMode.externalApplication, webOnlyWindowName: '_blank');
      if (!ok && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No se pudo abrir el mapa'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No se pudo abrir el mapa'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  // ───────────────────────────────────────────────────────────
  // NAVEGACIÓN CONTINUA DENTRO DE LA APP
  // ───────────────────────────────────────────────────────────

  /// Abre la navegación continua: el mapa avanza solo al llegar a cada parada.
  Future<void> _abrirNavegacionInterna(
      List<QueryDocumentSnapshot> direcciones, String tarjetaNombre) async {
    if (direcciones.isEmpty) return;

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('📍 Preparando navegación...'),
          duration: Duration(seconds: 10),
        ),
      );
    }

    // Ubicación actual para ordenar por cercanía (si el permiso lo permite).
    double? origenLat;
    double? origenLng;
    try {
      final permiso = await Geolocator.checkPermission();
      if (permiso == LocationPermission.always ||
          permiso == LocationPermission.whileInUse) {
        final pos = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.high,
            timeLimit: Duration(seconds: 8),
          ),
        );
        origenLat = pos.latitude;
        origenLng = pos.longitude;
      }
    } catch (_) {}

    final destinos = await RutaOrdenService.preparar(
      direcciones,
      origenLat: origenLat,
      origenLng: origenLng,
    );

    if (mounted) ScaffoldMessenger.of(context).clearSnackBars();
    if (!mounted) return;

    if (destinos.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No se pudieron ubicar las direcciones en el mapa'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    // `_RutaNavegacionTransparente` no absorbe toques (sin barrera modal):
    // al minimizar el mapa, la app de abajo sigue siendo usable.
    await Navigator.of(context).push(
      RutaNavegacionTransparente<Object?>(
        pageBuilder: (_, __, ___) => NavegacionScreen(
          titulo: tarjetaNombre,
          destinos: destinos,
        ),
      ),
    );
  }

  /// Ordena las paradas por vecino más cercano desde (lat,lng), dejando las
  /// prioridades del mes anterior primero y las sin coordenadas al final.
  List<_PuntoRuta> _ordenarPorCercania(
      List<_PuntoRuta> puntos, double? lat, double? lng) {
    if (lat == null || lng == null || puntos.length < 2) return puntos;

    final conCoord =
        puntos.where((p) => p.lat != null && p.lng != null).toList();
    final sinCoord =
        puntos.where((p) => p.lat == null || p.lng == null).toList();

    final prioridades = conCoord.where((p) => p.prioridad).toList();
    final resto = conCoord.where((p) => !p.prioridad).toList();

    final ordenados = <_PuntoRuta>[];
    var cLat = lat;
    var cLng = lng;

    for (final grupo in [prioridades, resto]) {
      final pendientes = [...grupo];
      while (pendientes.isNotEmpty) {
        var mejor = 0;
        var mejorDist = double.infinity;
        for (var i = 0; i < pendientes.length; i++) {
          final d = Geolocator.distanceBetween(
              cLat, cLng, pendientes[i].lat!, pendientes[i].lng!);
          if (d < mejorDist) {
            mejorDist = d;
            mejor = i;
          }
        }
        final elegido = pendientes.removeAt(mejor);
        ordenados.add(elegido);
        cLat = elegido.lat!;
        cLng = elegido.lng!;
      }
    }

    return [...ordenados, ...sinCoord];
  }

  // ───────────────────────────────────────────────────────────
  // REINTENTAR ENVIO RUTA
  // ───────────────────────────────────────────────────────────

  void reintentarEnvioRuta(String url) async {
    try {
      final uri = Uri.parse(url);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('No se puede abrir la URL'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al reintentar: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  // CONFIRMAR PROCESAMIENTO
  // ───────────────────────────────────────────────────────────

  /// Campos del modelo nuevo, escritos junto a los campos viejos.
  ///
  /// Esto es un puente, no un reemplazo. La pantalla actual sigue leyendo
  /// `predicado` y `estado_predicacion`, y las pantallas de estadísticas los leen
  /// directo de Firestore: quitar los campos viejos ahora haría que las
  /// estadísticas dejaran de cuadrar sin que nadie lo note. Escribiendo los dos,
  /// el modelo nuevo queda poblado y coherente desde el primer día, y los campos
  /// viejos se pueden retirar en un paso aparte y con las estadísticas a la vista.
  ///
  /// El avance NO se escribe acá a propósito. No hay ningún contador que
  /// resetear ni que se pueda desfasar: `trabajada` se deriva de que esta
  /// dirección tenga o no resultado, así que la verdad vive en un solo lugar.
  ///
  /// No incluye `campana_estado`: la invitación se resuelve en su propio bloque
  /// del bucle, más abajo.
  Map<String, dynamic> _camposResultadoNuevo(String resultado, String usuario) {
    final ahora = Timestamp.now();
    return {
      'resultado_predicacion': resultado,
      'avance_direccion': 'trabajada',
      'fecha_confirmacion': ahora,
      'resultado_por': usuario,
      'fecha_actualizacion': ahora,
    };
  }

  /// Confirmar una tarjeta completa.
  ///
  /// Envuelve a [._confirmarProcesamientoTarjetaInterno] solo para apagar el
  /// botón en tiempo seguro. Va aparte en lugar de un `try/finally` en el
  /// cuerpo porque ese método tiene varios `return` de validación y muchos
  /// cientos de líneas: envolverlo obligaría a reindentar todo y el diff
  ///Tapaba las partes que importan.
  Future<void> _confirmarProcesamientoTarjeta(
      String tarjetaId,
      String territorioId,
      String tarjetaNombre,
      List<QueryDocumentSnapshot> direcciones,
      BuildContext context,
      [String tipoTarjeta = 'normal',
      bool cerrarTarjeta = true]) async {
    if (_guardandoPorTarjeta[tarjetaId] == true) return;

    // Una confirmación individual en curso ya está escribiendo en direcciones de
    // esta misma tarjeta. Confirmar la entera ahora leería el estado local antes
    // de que el otro guardado termine y cerraría la tarjeta con direcciones sin
    // resultado. Se espera a que termine en lugar de solaparse.
    if (_guardandoPorDireccion.values.any((v) => v)) return;

    _guardandoPorTarjeta[tarjetaId] = true;
    _reconstruirTarjeta(tarjetaId);
    try {
      await _confirmarProcesamientoTarjetaInterno(
        tarjetaId,
        territorioId,
        tarjetaNombre,
        direcciones,
        context,
        tipoTarjeta,
        cerrarTarjeta,
      );
    } finally {
      _guardandoPorTarjeta[tarjetaId] = false;
      _reconstruirTarjeta(tarjetaId);
    }
  }

  /// Confirmar UNA dirección (Fase 2 del plan, §5.2).
  ///
  /// Reutiliza el mismo camino de escritura que la confirmación de tarjeta
  /// entera, y por eso no duplica ninguna de las reglas: los mismos destinos
  /// (`completada`, `comercio_cerrado`, `no_hispano`), la misma escritura doble
  /// de campos viejos y nuevos y el mismo aviso a administración.
  ///
  /// Lo que cambia es el alcance: se pasa una lista de una sola dirección, así
  /// que la validación "todas o nada" de la línea 1599 pasa a validar solo esa,
  /// y `cerrarTarjeta: false` evita que una sola dirección cierre la tarjeta
  /// entera.
  ///
  /// El cierre automático cuando ya no queda ninguna pendiente es la Fase 4
  /// (§5.5). Acá la tarjeta se queda abierta a propósito.
  Future<void> _confirmarDireccion(
    String tarjetaId,
    String territorioId,
    String tarjetaNombre,
    QueryDocumentSnapshot direccion,
    BuildContext context,
    String tipoTarjeta,
  ) async {
    if (_guardandoPorDireccion[direccion.id] == true) return;

    // Mismo motivo que en `_confirmarProcesamientoTarjeta`: mientras se guarda
    // la tarjeta entera, esta dirección se está tocando en el otro guardado.
    if (_guardandoPorTarjeta[tarjetaId] == true) return;

    _guardandoPorDireccion[direccion.id] = true;
    _reconstruirTarjeta(tarjetaId);
    try {
      await _confirmarProcesamientoTarjetaInterno(
        tarjetaId,
        territorioId,
        tarjetaNombre,
        [direccion],
        context,
        tipoTarjeta,
        false,
      );
    } finally {
      _guardandoPorDireccion[direccion.id] = false;
      _reconstruirTarjeta(tarjetaId);
    }
  }

  /// Reconstruye una tarjeta sin contexto.
  ///
  /// El rebuilder guardado puede quedar viejo si la tarjeta se colapsó mientras
  /// se guardaba. Refreshar la UI nunca vale una excepción, y sin esto un error
  /// de eso aparecería dentro del `finally` y ocultaría el resultado real del
  /// guardado.
  void _reconstruirTarjeta(String tarjetaId) {
    final rebuild = _setStatePorTarjeta[tarjetaId];
    if (rebuild == null || !mounted) return;
    try {
      rebuild(() {});
    } catch (_) {
      // La tarjeta ya no está en el árbol. No hay nada que refrescar.
    }
  }

  Future<void> _confirmarProcesamientoTarjetaInterno(
      String tarjetaId,
      String territorioId,
      String tarjetaNombre,
      List<QueryDocumentSnapshot> direcciones,
      BuildContext context,
      [String tipoTarjeta = 'normal',
      bool cerrarTarjeta = true]) async {
    final estados = _estadosPorTarjeta[tarjetaId] ?? {};
    final textos = _textosPorTarjeta[tarjetaId] ?? {};
    final esComercial = tipoTarjeta == 'zona';
    final estadosValidos = esComercial
        ? {'completada', 'comercio_cerrado'}
        : {'completada', 'no_hispano'};

    // Con la confirmación individual la lista trae una sola dirección, así que
    // este mensaje de "todas las direcciones" ya no corresponde.
    final esIndividual = !cerrarTarjeta;
    final calleIndividual = esIndividual
        ? ((_safeData(direcciones.first)['calle'] as String?) ?? '').trim()
        : '';

    // Validar que todas tengan estado obligatorio (el comentario es
    // opcional y NO cuenta como estado para confirmar).
    for (final dir in direcciones) {
      // Dirección ya predicada: no requiere estado (solo se le puede guardar
      // la campaña), así que no se valida como una dirección nueva.
      if (_esDirPredicada(_safeData(dir))) continue;
      final estado = estados[dir.id];
      if (estado == null ||
          estado == 'pendiente' ||
          estado.isEmpty ||
          !estadosValidos.contains(estado)) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(esIndividual
                ? 'Debes marcar una opción de estado en esta dirección '
                    '(el comentario es opcional y no confirma por sí solo)'
                : 'Debes marcar una opción de estado en todas las direcciones '
                    '(el comentario es opcional y no confirma por sí solo)'),
            backgroundColor: Colors.orange,
          ),
        );
        return;
      }
      if (estados['comentario_${dir.id}'] == 'true' &&
          (textos[dir.id]?.trim().isEmpty ?? true)) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(esComercial
                ? 'Para "Comentario" debes escribir algo'
                : 'Para el comentario debes escribir algo'),
            backgroundColor: Colors.orange,
          ),
        );
        return;
      }
    }

    // ── Contar el destino de cada dirección ─────────────────────────────
    // El publicador ya no ve este desglose (solo confirma), pero el conteo se
    // usa al final para el resumen de "tarjeta completada", y cada dirección
    // guarda su propio motivo para que el admin pueda revisarla.
    final Map<String, int> conteoDestinos = {};

    for (final dir in direcciones) {
      final estadoDir = estados[dir.id] ?? 'pendiente';
      final data = _safeData(dir);
      // Las direcciones ya predicadas no se cuentan: solo se les guardó la
      // campaña y su destino de predicación no cambió.
      if (_esDirPredicada(data)) continue;
      String destinoKey;

      if (estadoDir == 'completada') {
        destinoKey = 'queda';
      } else if (estadoDir == 'comercio_cerrado') {
        destinoKey = 'cerrado';
      } else {
        destinoKey = 'removidas';
      }

      conteoDestinos[destinoKey] = (conteoDestinos[destinoKey] ?? 0) + 1;
    }

    final confirmar = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
            esIndividual ? 'Confirmar dirección' : 'Confirmar procesamiento'),
        // Solo confirmación. El publicador no necesita un desglose de a dónde
        // va cada dirección: ese detalle ya queda guardado por dirección en
        // `motivo` / `estado` / `reportado_por`, y es el admin quien lo revisa
        // desde su pestaña. Mostrarlo acá solo retrasaba el trabajo de campo y
        // arrastraba los caracteres que la fuente del navegador no tenía.
        content: Text(esIndividual
            ? '¿Confirmar esta dirección?'
                '${calleIndividual.isEmpty ? '' : '\n\n$calleIndividual'}'
            : '¿Procesar las ${direcciones.length} direcciones de "$tarjetaNombre"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(c, true),
            style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF1B5E20)),
            child: const Text('Confirmar'),
          ),
        ],
      ),
    );
    if (confirmar != true) return;

    try {
      final db = FirebaseFirestore.instance;
      final ahora = DateTime.now();
      final marcaLocal = Timestamp.fromDate(ahora);
      final mesActual =
          '${ahora.year}-${ahora.month.toString().padLeft(2, '0')}';

      final batch = db.batch();

      // Nombre de territorio desde caché: el id sirve de fallback offline.
      String territorioNombreGlobal = territorioId;
      try {
        final terDoc = await db
            .collection('territorios')
            .doc(territorioId)
            .get(const GetOptions(source: Source.cache));
        final nombreCache = terDoc.data()?['nombre'] as String?;
        if (nombreCache != null && nombreCache.isNotEmpty) {
          territorioNombreGlobal = nombreCache;
        }
      } catch (_) {}

      for (final dir in direcciones) {
        final data = _safeData(dir);
        // Dirección ya predicada dentro de la tarjeta recibida: no se reescribe
        // su resultado ni su fecha (ya quedaron registrados al predicarla). Se
        // permite guardar la entrega de campañas que falten; el procesamiento
        // salta el resto para esas direcciones más abajo.
        final esPredicadaDir = _esDirPredicada(data);
        final estado = estados[dir.id] ?? 'pendiente';
        final motivo = textos[dir.id]?.trim() ?? '';
        final comentarioTexto =
            estados['comentario_${dir.id}'] == 'true' ? motivo : '';
        final calle = (data['calle'] as String?) ?? '';
        final complemento = (data['complemento'] as String?) ?? '';
        final territorioNombre = territorioNombreGlobal;
        final tarjetaIdOriginal = (data['tarjeta_id'] as String?) ?? tarjetaId;

        // ── Verificar campañas activas (no aplican a comercios) ──
        List<QueryDocumentSnapshot<Map<String, dynamic>>> campanasActivas = [];
        if (!esComercial) {
          final queryCampanas =
              db.collection('configuracion').where('activa', isEqualTo: true);
          try {
            final campSnap = OfflineSyncService.instance.isOffline
                ? await queryCampanas.get(
                    const GetOptions(source: Source.cache),
                  )
                : await queryCampanas.get();
            campanasActivas = campSnap.docs;
          } catch (_) {
            try {
              campanasActivas = (await queryCampanas.get(
                const GetOptions(source: Source.cache),
              ))
                  .docs;
            } catch (_) {
              // Si no hay una copia local de la configuración, no hay una
              // lectura de servidor disponible. El resto del procesamiento
              // sigue usando los resultados y decisiones capturados en UI.
            }
          }
        }

        for (final campDoc in campanasActivas) {
          final campData = campDoc.data();
          final campNombre = (campData['nombre'] as String?) ?? '';
          if (campNombre.isEmpty) continue;
          // El nombre de la campaña se usa como ID de colección. Si trae
          // caracteres que Firestore no admite en un path (por ejemplo "/"),
          // armar el batch revienta con "A collection path must point to a
          // valid collection" y NO se guarda nada de toda la tarjeta. Por eso
          // se convierte a un ID válido; los tabs de admin usan el mismo
          // helper, así que leen exactamente la misma carpeta.
          final campId = CampanasUtils.idColeccionCampana(campNombre);
          if (campId.isEmpty) continue;
          final mensajePendiente = (campData['mensaje_pendiente'] as String?) ??
              'Falta entregar invitación';
          final campKey = 'campana_inv_${campNombre}_${dir.id}';
          final invitacionMarcada = estados[campKey] == 'true';

          if (!invitacionMarcada && estado != 'no_hispano' && !esPredicadaDir) {
            // ❌ No marcó — va a carpeta de campaña
            batch.set(
              db
                  .collection('territorios')
                  .doc('campanas')
                  .collection(campId)
                  .doc(dir.id),
              {
                'calle': calle,
                'complemento': complemento,
                'direccion_normalizada':
                    _normalizarDireccion('$calle $complemento'),
                'territorio_origen': territorioNombre,
                'territorio_origen_id': territorioId,
                'tarjeta_origen': tarjetaIdOriginal,
                'estado_campana': 'pendiente',
                'mensaje': mensajePendiente,
                'created_at': marcaLocal,
              },
            );
          } else if (invitacionMarcada) {
            // ✅ Marcó invitación — guardar en dirección
            batch.update(dir.reference, {
              'campana_invitacion_$campNombre': true,
              'campana_invitacion_fecha': marcaLocal,
              // El modelo nuevo lleva un estado de campaña por dirección, con
              // clave fija. El campo de arriba es el que renombra la
              // campaña y rompe: si el nombre cambia, el `true` anterior queda
              // en un campo que ya nadie lee y la campaña parece no
              // entregada. Este no depende del nombre.
              'campana_estado': 'entregada',
              'campana_nombre': campNombre,
              'fecha_campana': marcaLocal,
              'campana_por': widget.usuarioData['nombre'] ?? '',
            });
          }
        }

        // Dirección ya predicada: solo se registró la campaña (arriba). No se
        // reescribe el resultado de predicación ni se registran movimientos.
        //
        // Excepción: "no vive hispanohablante" SÍ debe procesarse aunque la
        // dirección ya esté predicada. Es una decisión que la saca del listado
        // (va a `direcciones_removidas`) y no un cambio de resultado. Antes
        // este `continue` la ignoraba en silencio: marcar una dirección
        // predicada como no hispana no hacía nada.
        if (esPredicadaDir && estado != 'no_hispano') continue;

        // ── Procesar estado de predicación ─────────────────
        if (estado == 'completada') {
          batch.update(dir.reference, {
            'estado': 'activa',
            'estado_predicacion': 'completada',
            'predicado': true,
            'fecha_predicacion': marcaLocal,
            'mes_predicacion': mesActual,
            ..._camposResultadoNuevo(
                'predicado', widget.usuarioData['nombre'] ?? ''),
            if (comentarioTexto.isNotEmpty) 'comentario': comentarioTexto,
          });
        } else if (estado == 'comercio_cerrado') {
          // 🚫 El comercio ya no existe. La dirección sale de la tarjeta y
          // queda registrada para revisión del administrador.
          batch.update(dir.reference, {
            'estado': 'comercio_cerrado',
            'estado_predicacion': 'comercio_cerrado',
            'tarjeta_id': '',
            ..._camposResultadoNuevo(
                'comercio_cerrado', widget.usuarioData['nombre'] ?? ''),
            if (comentarioTexto.isNotEmpty)
              'comentario_cierre': comentarioTexto,
            'fecha_cierre': marcaLocal,
            'reportado_por': widget.usuarioData['nombre'] ?? '',
            'reportado_por_email': widget.usuarioData['email'] ?? '',
          });
        } else if (estado == 'no_hispano') {
          batch.set(
            db.collection('direcciones_removidas').doc(dir.id),
            {
              'calle': calle,
              'complemento': complemento,
              'direccion_normalizada':
                  _normalizarDireccion('$calle $complemento'),
              'territorio_id': territorioId,
              'territorio_nombre': territorioNombre,
              'tarjeta_id': tarjetaIdOriginal,
              'motivo': 'no_hispano',
              'removida_por': widget.usuarioData['nombre'] ?? '',
              'removida_en': marcaLocal,
              'doc_id_original': dir.id,
              'alerta_30_enviada': false,
              'alerta_60_enviada': false,
              if (comentarioTexto.isNotEmpty) 'comentario': comentarioTexto,
            },
          );
          // La copia completa queda en `direcciones_removidas` (arriba) y el
          // documento original se BORRA de `direcciones_globales`.
          //
          // Antes se marcaba `estado: 'removida'` en lugar de borrar, para no
          // perder el historial. El problema: el documento seguía existiendo en
          // `direcciones_globales` y los conteos que no filtran por `estado`
          // (el total de "Existentes" del home, por ejemplo) lo seguían
          // contando. Una dirección removida inflaba el total real.
          //
          // La rama equivalente del admin (`devueltas_tab` → "Mover a
          // devueltas") ya borra el documento, así que esto también la deja
          // consistente. No se pierde nada: `direcciones_removidas` guarda
          // todos los campos necesarios y el botón "Restaurar" del panel
          // recrea la dirección en `direcciones_globales` con `doc_id_original`.
          batch.delete(dir.reference);
        }
      }

      // Marcar tarjeta como completada.
      //
      // Solo con la confirmación de tarjeta entera. Con la individual, una
      // dirección no puede cerrar la tarjeta: el publicador sigue trabajando el
      // resto. El cierre cuando ya no queda ninguna pendiente es la Fase 4 del
      // plan (§5.5), y sale de contar las direcciones, no de este `batch`.
      if (cerrarTarjeta) {
        batch.update(
          db
              .collection('territorios')
              .doc(territorioId)
              .collection('tarjetas')
              .doc(tarjetaId),
          {
            'completada': true,
            'fecha_completada': marcaLocal,
          },
        );
      }

      unawaited(batch.commit().catchError((Object error) {
        debugPrint('Confirmación pendiente/no confirmada: $error');
      }));

      // Cancelar timer de devolución automática
      AutoReturnService().cancelarTimer(tarjetaId);

      // Notificar al admin de territorios si hay "no_hispano" o
      // "comercio_cerrado"
      final dirNoPredicadas = direcciones.where((dir) {
        final estado = _estadosPorTarjeta[tarjetaId]?[dir.id] ?? 'pendiente';
        return estado == 'no_hispano' || estado == 'comercio_cerrado';
      }).toList();

      if (dirNoPredicadas.isNotEmpty) {
        final nombre = widget.usuarioData['nombre'] ?? 'Publicador';
        final resumen = dirNoPredicadas.map((dir) {
          final data = dir.data() as Map<String, dynamic>;
          final estado = _estadosPorTarjeta[tarjetaId]?[dir.id] ?? '';
          final calle = data['calle']?.toString() ?? '';
          final motivo = estado == 'no_hispano'
              ? 'No vive hispanohablante'
              : 'Comercio ya no existe';
          return '$calle — $motivo';
        }).join('\n');

        // Notificar a admins de territorios
        unawaited(NotificacionService.enviarAAdminTerritorios(
          titulo: '⚠️ Atención requerida',
          cuerpo:
              '$nombre reportó ${dirNoPredicadas.length} dirección(es) en "$tarjetaId":\n$resumen',
          tipo: TipoNotificacion.alertaPredicacion,
          extra: {'tarjeta_id': tarjetaId, 'territorio_id': territorioId},
        ).catchError((Object error) {
          debugPrint('Notificación de resultado pendiente: $error');
        }));
      }

      if (mounted) {
        // `_tarjetasCompletadas` saca la tarjeta del listado. Con la
        // confirmación individual la tarjeta sigue abierta: se workea de a una.
        if (cerrarTarjeta) {
          setState(() {
            _tarjetasCompletadas.add(tarjetaId);
          });
        }

        // Programar mensaje motivacional en Firestore (persiste aunque se cierre la app)
        unawaited(_programarMensajeMotivacional());

        // Resumen final del destino de las direcciones procesadas
        final cerrados = conteoDestinos['cerrado'] ?? 0;
        final removidas = conteoDestinos['removidas'] ?? 0;
        final partesResumen = <String>[
          if (cerrados > 0) '🏬 $cerrados quedaron en comercios cerrados',
          if (removidas > 0) '🗑️ $removidas se removieron',
        ];
        final textoResumen = partesResumen.join(' · ');

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.check_circle, color: Colors.white, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    esIndividual
                        ? (OfflineSyncService.instance.isOffline
                            ? '¡Dirección guardada en este dispositivo! Se sincronizará al recuperar conexión.'
                            : '¡Dirección guardada!')
                        : (OfflineSyncService.instance.isOffline
                            ? '¡Tarjeta "$tarjetaNombre" guardada! Se sincronizará al recuperar conexión.'
                            : '¡Tarjeta "$tarjetaNombre" completada!'),
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
            backgroundColor: const Color(0xFF1B5E20),
            duration: const Duration(seconds: 3),
            behavior: SnackBarBehavior.floating,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        );

        // ✔ Resumen con el destino de cada dirección
        if (textoResumen.isNotEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                textoResumen,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              backgroundColor: const Color(0xFF004D40),
              duration: const Duration(seconds: 5),
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al procesar: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  } // ✅ cierra _confirmarProcesamientoTarjeta

  // ─────────────────────────────────────────────────
  // BUILD
  // ─────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final nombrePublicador = widget.usuarioData['nombre'] ?? 'Publicador';
    debugPrint('=== NOMBRE: ${widget.usuarioData['nombre']}');
    debugPrint('=== EMAIL: ${widget.usuarioEmail}');
    final iniciales =
        nombrePublicador.isNotEmpty ? nombrePublicador[0].toUpperCase() : 'U';

    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      body: CustomScrollView(
        slivers: [
          // ── HEADER ─────────────────────────────────────
          SliverToBoxAdapter(
            child: Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [Color(0xFF1B5E20), Color(0xFF2E7D32)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
              padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      CircleAvatar(
                        radius: 28,
                        backgroundColor: Colors.white.withOpacity(0.2),
                        child: Text(
                          iniciales,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              context.t('hello_user', args: [nombrePublicador]),
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              context.t('your_assigned_cards'),
                              style: TextStyle(
                                color: Colors.white.withOpacity(0.8),
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  // ✅ Botón solicitar integrado al header
                  GestureDetector(
                    onTap: widget.onSolicitarTerritorio,
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                          vertical: 12, horizontal: 16),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                            color: Colors.white.withOpacity(0.5), width: 1.5),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.map_outlined,
                              color: Colors.white, size: 18),
                          const SizedBox(width: 8),
                          Text(
                            context.t('request_territory'),
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w600,
                              fontSize: 14,
                              letterSpacing: 0.3,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // ── ALERTAS ────────────────────────────────────
          if (widget.campanaEspecialActiva ||
              (widget.campanaGeneralActiva &&
                  widget.anuncioGeneral.trim().isNotEmpty))
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
              sliver: SliverList(
                delegate: SliverChildListDelegate([
                  if (widget.campanaEspecialActiva)
                    _alertaBanner(
                      icon: Icons.campaign,
                      color: const Color(0xFFE65100),
                      bgColor: const Color(0xFFFFF3E0),
                      title: 'Campaña especial activa',
                      body: widget.nombreCampanaEspecial,
                    ),
                  if (widget.campanaGeneralActiva &&
                      widget.anuncioGeneral.trim().isNotEmpty) ...[
                    const SizedBox(height: 10),
                    _alertaBanner(
                      icon: Icons.info_outline,
                      color: const Color(0xFF1565C0),
                      bgColor: const Color(0xFFE3F2FD),
                      title: 'Anuncio',
                      body: widget.anuncioGeneral,
                    ),
                  ],
                ]),
              ),
            ),

          // ── ANUNCIO GENERAL ──────────────────────────────
          SliverToBoxAdapter(
            child: StreamBuilder<DocumentSnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('configuracion')
                  .doc('anuncio_general')
                  .snapshots(),
              builder: (context, snap) {
                final data = (snap.data?.data() as Map<String, dynamic>?) ?? {};
                final idioma = context.currentLanguage;
                final texto = idioma == 'PT'
                    ? ((data['texto_pt'] as String?)?.isNotEmpty == true
                        ? data['texto_pt'] as String
                        : data['texto'] as String? ?? '')
                    : (data['texto'] as String? ??
                        data['mensaje'] as String? ??
                        '');
                if (texto.isEmpty) return const SizedBox.shrink();
                return Container(
                  margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1565C0).withOpacity(0.08),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                        color: const Color(0xFF1565C0).withOpacity(0.3)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.campaign,
                          color: Color(0xFF1565C0), size: 20),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          texto,
                          style: const TextStyle(
                              fontSize: 13, color: Color(0xFF1565C0)),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),

          // ── STATS ──────────────────────────────────────
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
            sliver: SliverToBoxAdapter(
              child: StreamBuilder<QuerySnapshot>(
                stream: FirebaseFirestore.instance
                    .collectionGroup('tarjetas')
                    .where('asignado_a',
                        isEqualTo: widget.usuarioData['nombre'] ?? '')
                    .snapshots(),
                builder: (context, tarjetasSnap) {
                  int totalDirAsignadas = 0;
                  final List<String> tarjetaIds = [];

                  if (tarjetasSnap.hasData) {
                    for (final t in tarjetasSnap.data!.docs) {
                      final d = _safeData(t);
                      if (d['completada'] == true) continue;
                      if (d['enviado_tipo'] == 'conductor') continue;
                      totalDirAsignadas +=
                          (d['cantidad_direcciones'] as num?)?.toInt() ?? 0;
                      tarjetaIds.add(t.id);
                    }
                  }

                  final idsOrdenados = [...tarjetaIds]..sort();
                  final keyFuturo = idsOrdenados.join(',');
                  if (keyFuturo != _completadasFutureKey) {
                    _completadasFutureKey = keyFuturo;
                    _completadasFuture = _contarCompletadas(idsOrdenados);
                  }

                  return FutureBuilder<int?>(
                    future: _completadasFuture,
                    builder: (context, dirsSnap) {
                      final completadas = dirsSnap.data ?? 0;
                      final pendientes = totalDirAsignadas - completadas;

                      return Row(
                        children: [
                          Expanded(
                            child: _statCard('Asignadas', totalDirAsignadas,
                                Icons.home_work_outlined),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _statCard('Completadas', completadas,
                                Icons.check_circle_outline),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _statCard(
                                'Pendientes',
                                pendientes < 0 ? 0 : pendientes,
                                Icons.schedule_outlined),
                          ),
                        ],
                      );
                    },
                  );
                },
              ),
            ),
          ),

          // ── PROGRESO ───────────────────────────────────
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
            sliver: SliverToBoxAdapter(
              child: StreamBuilder<QuerySnapshot>(
                stream: FirebaseFirestore.instance
                    .collection('direcciones_globales')
                    .snapshots(),
                builder: (context, snapTotal) {
                  // Las direcciones ya removidas (estado == 'removida') NO
                  // cuentan como existentes. Antes inflaban el total: una
                  // dirección marcada como "no vive hispanohablante" seguía
                  // sumando en "Existentes" aunque ya estuviera en removidas.
                  // Se filtra en memoria y no en la query para no excluir por
                  // error documentos sin el campo `estado`.
                  final todos = snapTotal.data?.docs ?? [];
                  bool esRemovida(QueryDocumentSnapshot doc) =>
                      (_safeData(doc)['estado'] as String?) == 'removida';
                  final totalExistentes =
                      todos.where((doc) => !esRemovida(doc)).length;
                  // Criterio único de "completada": `predicado == true` o
                  // `estado_predicacion == 'completada'`. Antes solo se miraba
                  // `predicado`, por lo que las direcciones completadas por
                  // otras vías quedaban contadas como pendientes.
                  final completadasGlobal = todos.where((doc) {
                    if (esRemovida(doc)) return false;
                    final d = _safeData(doc);
                    return d['predicado'] == true ||
                        d['estado_predicacion'] == 'completada';
                  }).length;
                  final pendientesGlobal = totalExistentes - completadasGlobal;
                  final avance = totalExistentes > 0
                      ? completadasGlobal / totalExistentes
                      : 0.0;

                  final pctPendientes = totalExistentes > 0
                      ? (pendientesGlobal / totalExistentes * 100)
                          .toStringAsFixed(0)
                      : '0';

                  final inicioProg = _inicioProgreso;
                  final ahora = DateTime.now();
                  final mesActualClave =
                      '${ahora.year}-${ahora.month.toString().padLeft(2, '0')}';

                  // "Este mes": predicadas cuyo `mes_predicacion` es el mes
                  // actual. Ese campo SIEMPRE se escribe al predicar; en cambio
                  // `fecha_predicacion` solo existe en registros antiguos, por
                  // eso se usa únicamente como respaldo.
                  final predActualGlobal = snapTotal.data?.docs.where((doc) {
                        if (esRemovida(doc)) return false;
                        final d = _safeData(doc);
                        if (d['predicado'] != true &&
                            d['estado_predicacion'] != 'completada') {
                          return false;
                        }
                        final m = d['mes_predicacion']?.toString();
                        if (m != null && m.isNotEmpty) {
                          return m == mesActualClave;
                        }
                        final fp = d['fecha_predicacion'];
                        if (inicioProg == null || fp is! Timestamp) {
                          return false;
                        }
                        return !fp.toDate().isBefore(inicioProg);
                      }).length ??
                      0;
                  final pctCompletadasMes = totalExistentes > 0
                      ? (predActualGlobal / totalExistentes * 100)
                          .toStringAsFixed(0)
                      : '0';
                  // "mes pasado": completadas antes del inicio del período actual.
                  final completadasMesPasado =
                      (completadasGlobal - predActualGlobal)
                          .clamp(0, completadasGlobal);
                  final pctCompletadasMesPasado = totalExistentes > 0
                      ? (completadasMesPasado / totalExistentes * 100)
                          .toStringAsFixed(0)
                      : '0';

                  return Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.05),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Builder(
                                builder: (ctx) => Text(
                                      ctx.t('monthly_progress'),
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 15,
                                        color: Color(0xFF263238),
                                      ),
                                    )),
                            Text(
                              '${(avance * 100).toStringAsFixed(0)}%',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 15,
                                color: Color(0xFF1B5E20),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: LinearProgressIndicator(
                            value: avance,
                            minHeight: 10,
                            backgroundColor: const Color(0xFFE8F5E9),
                            valueColor: const AlwaysStoppedAnimation<Color>(
                                Color(0xFF1B5E20)),
                          ),
                        ),
                        const SizedBox(height: 16),
                        if (totalExistentes > 0) ...[
                          Text(
                            'Mes pasado: $completadasMesPasado ($pctCompletadasMesPasado%) · Este mes: $predActualGlobal ($pctCompletadasMes%) · Pendientes: $pendientesGlobal ($pctPendientes%)',
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.grey[600],
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const SizedBox(height: 12),
                        ],
                        Row(
                          children: [
                            Expanded(
                              child: _miniStat('Existentes', totalExistentes,
                                  Icons.home_work_outlined, Colors.blue),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: _miniStat(
                                  'Completadas',
                                  completadasGlobal,
                                  Icons.check_circle_outline,
                                  const Color(0xFF1B5E20)),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: _miniStat('Pendientes', pendientesGlobal,
                                  Icons.schedule_outlined, Colors.orange),
                            ),
                          ],
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ),

          // ── ENVIAR DIRECCIÓN NUEVA ──
          SliverToBoxAdapter(
            child: EnviarDireccionCard(
              usuarioEmail: widget.usuarioEmail,
              usuarioNombre:
                  widget.usuarioData['nombre'] ?? widget.usuarioEmail,
            ),
          ),

          // ── MIS TARJETAS ───────────────────────────────
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
            sliver: SliverToBoxAdapter(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    context.t('my_cards'),
                    style: const TextStyle(
                      fontSize: 11,
                      letterSpacing: 1.5,
                      fontWeight: FontWeight.w700,
                      color: Colors.grey,
                    ),
                  ),
                  const SizedBox(height: 12),
                  StreamBuilder<QuerySnapshot>(
                    stream: _buildTarjetasStream(),
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return const Center(child: CircularProgressIndicator());
                      }
                      if (!snapshot.hasData) {
                        return const SizedBox();
                      }

                      final tarjetasVisibles = snapshot.data!.docs.where((doc) {
                        if (_tarjetasCompletadas.contains(doc.id)) return false;
                        final d = (doc.data() as Map<String, dynamic>?) ?? {};
                        if (d['completada'] == true) return false;
                        // Una tarjeta en manos de un conductor NO se muestra en
                        // el modo publicador, aunque quien la tenga sea también
                        // publicador.
                        if (d['enviado_tipo'] == 'conductor') return false;
                        return true;
                      }).toList();

                      // ── Ciclo del mensaje motivacional ──
                      // Tiene tarjetas → reinicia el ciclo.
                      // Sin tarjetas → programa 10 min y luego envía.
                      final ahoraTieneTarjetas = tarjetasVisibles.isNotEmpty;
                      if (ahoraTieneTarjetas != _tieneTarjetasActivas) {
                        _tieneTarjetasActivas = ahoraTieneTarjetas;
                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          if (!mounted) return;
                          if (ahoraTieneTarjetas) {
                            _reiniciarCicloMotivacional();
                          } else {
                            _programarMensajeMotivacional();
                          }
                        });
                      }

                      if (tarjetasVisibles.isEmpty) {
                        // Verificar si hay tarjetas completadas o simplemente no hay tarjetas
                        final hayCompletadas = snapshot.data!.docs.any((doc) {
                          final d = (doc.data() as Map<String, dynamic>?) ?? {};
                          return d['completada'] == true;
                        });
                        return Container(
                          padding: const EdgeInsets.all(24),
                          decoration: BoxDecoration(
                            color: hayCompletadas
                                ? const Color(0xFFE8F5E9)
                                : Colors.grey.shade50,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                                color: hayCompletadas
                                    ? const Color(0xFF1B5E20).withOpacity(0.3)
                                    : Colors.grey.shade200),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                hayCompletadas
                                    ? Icons.check_circle
                                    : Icons.inbox_outlined,
                                color: hayCompletadas
                                    ? const Color(0xFF1B5E20)
                                    : Colors.grey,
                                size: 20,
                              ),
                              const SizedBox(width: 8),
                              Flexible(
                                child: Text(
                                  hayCompletadas
                                      ? context.t('all_cards_completed')
                                      : context.t('no_cards_this_month'),
                                  style: TextStyle(
                                    color: hayCompletadas
                                        ? const Color(0xFF1B5E20)
                                        : Colors.grey,
                                    fontWeight: FontWeight.w600,
                                    fontSize: 13,
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                              ),
                            ],
                          ),
                        );
                      }

                      return Column(
                        children:
                            List.generate(tarjetasVisibles.length, (index) {
                          final tarjetaDoc = tarjetasVisibles[index];
                          final data =
                              (tarjetaDoc.data() as Map<String, dynamic>?) ??
                                  {};
                          final nombre =
                              (data['nombre'] as String?) ?? tarjetaDoc.id;
                          final territorioId =
                              tarjetaDoc.reference.parent.parent?.id ?? '';
                          final tarjetaId = tarjetaDoc.id;
                          final esComercial =
                              (data['tipo'] as String?) == 'zona';
                          final tarjetaColor = esComercial
                              ? const Color(0xFF4A148C)
                              : _tarjetaColores[index % _tarjetaColores.length];
                          final color = tarjetaColor;

                          return Container(
                            margin: const EdgeInsets.only(bottom: 14),
                            decoration: BoxDecoration(
                              color: Theme.of(context).cardColor,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                  color: color.withOpacity(0.2), width: 1),
                              boxShadow: [
                                BoxShadow(
                                  color: color.withOpacity(0.12),
                                  blurRadius: 12,
                                  spreadRadius: 1,
                                  offset: const Offset(0, 4),
                                ),
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.05),
                                  blurRadius: 6,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                            ),
                            child: Stack(
                              children: [
                                Padding(
                                  padding: const EdgeInsets.only(left: 5),
                                  child: ExpansionTile(
                                    leading: Container(
                                      width: 36,
                                      height: 36,
                                      decoration: BoxDecoration(
                                        color: color.withOpacity(0.12),
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                      child: Icon(
                                          esComercial
                                              ? Icons.storefront
                                              : Icons.credit_card,
                                          color: color,
                                          size: 20),
                                    ),
                                    title: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Flexible(
                                          child: Text(nombre,
                                              style: const TextStyle(
                                                  fontWeight: FontWeight.bold)),
                                        ),
                                        if (esComercial) ...[
                                          const SizedBox(width: 6),
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                                horizontal: 6, vertical: 2),
                                            decoration: BoxDecoration(
                                              color: const Color(0xFF4A148C)
                                                  .withOpacity(0.12),
                                              borderRadius:
                                                  BorderRadius.circular(6),
                                            ),
                                            child: const Text('COMERCIAL',
                                                style: TextStyle(
                                                    fontSize: 9,
                                                    fontWeight: FontWeight.bold,
                                                    letterSpacing: 0.5,
                                                    color: Color(0xFF4A148C))),
                                          ),
                                        ],
                                      ],
                                    ),
                                    subtitle: FutureBuilder<QuerySnapshot>(
                                      future: FirebaseFirestore.instance
                                          .collection('direcciones_globales')
                                          .where('tarjeta_id',
                                              isEqualTo: tarjetaId)
                                          .get(),
                                      builder: (context, dirSnap) {
                                        // Filtrado en memoria: `isNotEqualTo`
                                        // excluye docs sin el campo `estado`.
                                        final cantReal = dirSnap.data?.docs
                                                .where((d) =>
                                                    (_safeData(d)['estado']
                                                        as String?) !=
                                                    'removida')
                                                .length ??
                                            0;
                                        final enviadoNombre =
                                            (data['enviado_nombre']
                                                    as String?) ??
                                                '';
                                        final enviadoEn =
                                            data['enviado_en'] as Timestamp?;
                                        String fechaHora = '';
                                        if (enviadoEn != null) {
                                          final dt = enviadoEn.toDate();
                                          final h = dt.hour
                                              .toString()
                                              .padLeft(2, '0');
                                          final m = dt.minute
                                              .toString()
                                              .padLeft(2, '0');
                                          fechaHora =
                                              '${dt.day}/${dt.month}/${dt.year} $h:$m';
                                        }
                                        return Text(
                                          '$cantReal dir${enviadoNombre.isNotEmpty ? ' · $enviadoNombre' : ''}${fechaHora.isNotEmpty ? ' · $fechaHora' : ''}',
                                          style: const TextStyle(fontSize: 11),
                                        );
                                      },
                                    ),
                                    trailing: TextButton(
                                      onPressed: () async {
                                        final confirmar =
                                            await showDialog<bool>(
                                          context: context,
                                          builder: (c) => AlertDialog(
                                            title:
                                                const Text('Devolver tarjeta'),
                                            content: Text(
                                              '¿Devolver "$nombre"? Quedará disponible para otros.',
                                            ),
                                            actions: [
                                              TextButton(
                                                onPressed: () =>
                                                    Navigator.pop(c, false),
                                                child: const Text('Cancelar'),
                                              ),
                                              ElevatedButton(
                                                onPressed: () =>
                                                    Navigator.pop(c, true),
                                                style: ElevatedButton.styleFrom(
                                                    backgroundColor:
                                                        Colors.orange),
                                                child: const Text('Devolver'),
                                              ),
                                            ],
                                          ),
                                        );
                                        if (confirmar == true) {
                                          await _devolverTarjeta(
                                              territorioId, tarjetaId);
                                        }
                                      },
                                      child: const Text('Devolver',
                                          style:
                                              TextStyle(color: Colors.orange)),
                                    ),
                                    children: [
                                      _buildDireccionesTarjeta(
                                          tarjetaId,
                                          territorioId,
                                          nombre,
                                          (data['tipo'] as String?) ??
                                              'normal'),
                                    ],
                                  ),
                                ),
                                Positioned(
                                  left: 0,
                                  top: 0,
                                  bottom: 0,
                                  child: Container(
                                    width: 5,
                                    decoration: BoxDecoration(
                                      color: color,
                                      borderRadius: const BorderRadius.only(
                                        topLeft: Radius.circular(16),
                                        bottomLeft: Radius.circular(16),
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          );
                        }),
                      );
                    },
                  ),
                ],
              ),
            ),
          ),

          // Padding para que el FAB no tape el contenido inferior
          const SliverPadding(
            padding: EdgeInsets.only(bottom: 140),
          ),
        ],
      ),
    );
  }
}
