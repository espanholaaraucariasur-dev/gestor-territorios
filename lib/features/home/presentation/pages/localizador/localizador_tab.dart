import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class LocalizadorTab extends StatefulWidget {
  final String usuarioEmail;

  const LocalizadorTab({
    super.key,
    required this.usuarioEmail,
  });

  @override
  State<LocalizadorTab> createState() => _LocalizadorTabState();
}

class _LocalizadorTabState extends State<LocalizadorTab> {
  final TextEditingController _localizadorController = TextEditingController();
  final TextEditingController _complementoLocalizadorController =
      TextEditingController();
  final TextEditingController _detallesLocalizadorController =
      TextEditingController();
  bool _localizadorBuscado = false;
  bool _localizadorEncontrada = false;
  String _localizadorMensaje = '';
  bool _mostrarSolicitudLocalizador = false;

  String _normalizarDireccion(String direccion) {
    var texto = direccion.toLowerCase();
    texto = texto.replaceAll(RegExp(r'cep[:\s]*\d{4,10}'), ' ');
    texto = texto.replaceAll(RegExp(r'\b\d{5}-?\d{3}\b'), ' ');
    texto = texto.replaceAll(RegExp(r'\b(n\.?|no\.?|nº|n°)\b'), ' ');
    texto = texto.replaceAll(RegExp(r'[^a-z0-9 ]'), ' ');
    texto = texto.replaceAll('apto', 'apartamento');
    texto = texto.replaceAll('apt', 'apartamento');
    texto = texto.replaceAll('ap.', 'apartamento');
    texto = texto.replaceAll('dpto', 'departamento');
    texto = texto.replaceAll(RegExp(r'\s+'), ' ').trim();
    return texto;
  }

  String _formatoTiempoRelativo(DateTime dateTime) {
    final now = DateTime.now();
    final difference = now.difference(dateTime);

    if (difference.inSeconds < 60) {
      return 'unos segundos';
    } else if (difference.inMinutes < 60) {
      final minutes = difference.inMinutes;
      return minutes == 1 ? '1 minuto' : '$minutes minutos';
    } else if (difference.inHours < 24) {
      final hours = difference.inHours;
      return hours == 1 ? '1 hora' : '$hours horas';
    } else if (difference.inDays < 7) {
      final days = difference.inDays;
      return days == 1 ? '1 día' : '$days días';
    } else if (difference.inDays < 30) {
      final weeks = (difference.inDays / 7).floor();
      return weeks == 1 ? '1 semana' : '$weeks semanas';
    } else if (difference.inDays < 365) {
      final months = (difference.inDays / 30).floor();
      return months == 1 ? '1 mes' : '$months meses';
    } else {
      final years = (difference.inDays / 365).floor();
      return years == 1 ? '1 año' : '$years años';
    }
  }

  Future<void> _buscarDireccionGlobal() async {
    final consulta = _localizadorController.text.trim();
    if (consulta.isEmpty) {
      setState(() {
        _localizadorBuscado = true;
        _localizadorEncontrada = false;
        _localizadorMensaje = 'Ingresa una dirección para buscar.';
        _mostrarSolicitudLocalizador = false;
      });
      return;
    }

    final normalizada = _normalizarDireccion(consulta);
    setState(() {
      _localizadorBuscado = true;
      _localizadorEncontrada = false;
      _localizadorMensaje = 'Buscando en el directorio global…';
      _mostrarSolicitudLocalizador = false;
    });

    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('direcciones_globales')
          .where('es_hispano', isEqualTo: true)
          .get();

      for (final doc in snapshot.docs) {
        final data = doc.data();
        final calle = data['calle']?.toString() ?? '';
        final complemento = data['complemento']?.toString() ?? '';
        final docNormalizada = _normalizarDireccion('$calle $complemento');
        if (docNormalizada == normalizada) {
          setState(() {
            _localizadorEncontrada = true;
            _localizadorMensaje =
                'Dirección encontrada: $calle${complemento.isNotEmpty ? ' • $complemento' : ''}';
            _mostrarSolicitudLocalizador = false;
          });
          return;
        }
      }

      // Verificar si ya fue solicitada
      final pendientes = await FirebaseFirestore.instance
          .collection('solicitudes_direcciones')
          .where('direccion_normalizada', isEqualTo: normalizada)
          .where('estado', isEqualTo: 'pendiente')
          .get();
      if (pendientes.docs.isNotEmpty) {
        setState(() {
          _localizadorEncontrada = false;
          _localizadorMensaje =
              'Esta dirección ya fue solicitada y está pendiente de revisión.';
          _mostrarSolicitudLocalizador = false;
        });
        return;
      }

      setState(() {
        _localizadorEncontrada = false;
        _localizadorMensaje =
            'No se encontró en el directorio global. Completa el formulario para enviarla al administrador.';
        _mostrarSolicitudLocalizador = true;
      });
    } catch (e) {
      setState(() {
        _localizadorBuscado = true;
        _localizadorEncontrada = false;
        _localizadorMensaje = 'Error buscando la dirección: $e';
        _mostrarSolicitudLocalizador = false;
      });
    }
  }

  Future<void> _enviarDireccionParaRegistro() async {
    final direccion = _localizadorController.text.trim();
    if (direccion.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Por favor ingresa una dirección'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    final normalizada = _normalizarDireccion(direccion);

    try {
      // Verificar si ya existe en el directorio global
      final existenteGlobal = await FirebaseFirestore.instance
          .collection('direcciones_globales')
          .where('direccion_normalizada', isEqualTo: normalizada)
          .get();
      if (existenteGlobal.docs.isNotEmpty) {
        setState(() {
          _localizadorEncontrada = true;
          _localizadorMensaje =
              'La dirección ya existe en el directorio global.';
          _mostrarSolicitudLocalizador = false;
        });
        return;
      }

      // Verificar si ya fue solicitada
      final existenteSolicitud = await FirebaseFirestore.instance
          .collection('solicitudes_direcciones')
          .where('direccion_normalizada', isEqualTo: normalizada)
          .where('estado', isEqualTo: 'pendiente')
          .get();
      if (existenteSolicitud.docs.isNotEmpty) {
        setState(() {
          _localizadorEncontrada = false;
          _localizadorMensaje =
              'Esta dirección ya fue solicitada y está pendiente de revisión.';
          _mostrarSolicitudLocalizador = false;
        });
        return;
      }

      await FirebaseFirestore.instance
          .collection('solicitudes_direcciones')
          .add({
        'direccion_original': direccion,
        'direccion_normalizada': normalizada,
        'direccion_consultada': direccion,
        'complemento': _complementoLocalizadorController.text.trim(),
        'detalles': _detallesLocalizadorController.text.trim(),
        'solicitante_email': widget.usuarioEmail,
        'estado': 'pendiente',
        'created_at': FieldValue.serverTimestamp(),
      });
      setState(() {
        _localizadorMensaje =
            'Solicitud enviada correctamente. El admin revisará la dirección pronto.';
        _mostrarSolicitudLocalizador = false;
        _localizadorController.clear();
        _complementoLocalizadorController.clear();
        _detallesLocalizadorController.clear();
        _localizadorBuscado = false;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error enviando solicitud: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  void dispose() {
    _localizadorController.dispose();
    _complementoLocalizadorController.dispose();
    _detallesLocalizadorController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return CustomScrollView(
      slivers: [
        // Header
        SliverToBoxAdapter(
          child: Container(
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF1B5E20), Color(0xFF2E7D32)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: const BorderRadius.only(
                bottomLeft: Radius.circular(28),
                bottomRight: Radius.circular(28),
              ),
            ),
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(
                        Icons.location_searching,
                        color: Colors.white,
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 16),
                    const Expanded(
                      child: Text(
                        'Localizador de direcciones',
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                const Text(
                  'Busca direcciones en el directorio global o solicita agregar nuevas',
                  style: TextStyle(fontSize: 14, color: Colors.white70),
                ),
              ],
            ),
          ),
        ),

        // Buscador
        SliverPadding(
          padding: const EdgeInsets.all(20),
          sliver: SliverToBoxAdapter(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: _localizadorController,
                  decoration: InputDecoration(
                    hintText: 'Ingresa calle, número o punto de referencia',
                    filled: true,
                    fillColor: const Color(0xFFF5F5F5),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(
                        color: Color(0xFF1B5E20),
                        width: 2,
                      ),
                    ),
                    prefixIcon: const Icon(
                      Icons.search,
                      color: Color(0xFF1B5E20),
                    ),
                  ),
                  onChanged: (_) {
                    if (_localizadorBuscado) {
                      setState(() {
                        _localizadorBuscado = false;
                        _localizadorMensaje = '';
                        _mostrarSolicitudLocalizador = false;
                      });
                    }
                  },
                  onSubmitted: (_) => _buscarDireccionGlobal(),
                ),
                const SizedBox(height: 12),
                ElevatedButton.icon(
                  onPressed: _buscarDireccionGlobal,
                  icon: const Icon(Icons.search),
                  label: const Text('Buscar dirección'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF1B5E20),
                    foregroundColor: Colors.white,
                    minimumSize: const Size(double.infinity, 48),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ],
            ),
          ),
        ),

        // Resultados y formulario
        if (_localizadorBuscado)
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
            sliver: SliverToBoxAdapter(
              child: Card(
                elevation: 4,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                color: _localizadorEncontrada
                    ? Colors.green.shade50
                    : Colors.orange.shade50,
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            _localizadorEncontrada
                                ? Icons.check_circle
                                : Icons.info_outline,
                            color: _localizadorEncontrada
                                ? const Color(0xFF1B5E20)
                                : const Color(0xFFE65100),
                            size: 24,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              _localizadorMensaje,
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color: _localizadorEncontrada
                                    ? const Color(0xFF1B5E20)
                                    : const Color(0xFF4E342E),
                              ),
                            ),
                          ),
                        ],
                      ),
                      if (!_localizadorEncontrada &&
                          _mostrarSolicitudLocalizador) ...[
                        const SizedBox(height: 24),
                        const Text(
                          'Solicitar registro de dirección',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF263238),
                          ),
                        ),
                        const SizedBox(height: 16),
                        TextField(
                          controller: _complementoLocalizadorController,
                          decoration: InputDecoration(
                            hintText: 'Complemento / referencia adicional',
                            filled: true,
                            fillColor: const Color(0xFFF5F5F5),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide: BorderSide.none,
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide: const BorderSide(
                                color: Color(0xFF1B5E20),
                                width: 2,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _detallesLocalizadorController,
                          decoration: InputDecoration(
                            hintText: 'Detalles adicionales (opcional)',
                            filled: true,
                            fillColor: const Color(0xFFF5F5F5),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide: BorderSide.none,
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide: const BorderSide(
                                color: Color(0xFF1B5E20),
                                width: 2,
                              ),
                            ),
                          ),
                          maxLines: 3,
                        ),
                        const SizedBox(height: 20),
                        ElevatedButton.icon(
                          onPressed: _enviarDireccionParaRegistro,
                          icon: const Icon(Icons.send),
                          label: const Text('Enviar para registro'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF1B5E20),
                            foregroundColor: Colors.white,
                            minimumSize: const Size(double.infinity, 48),
                            padding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),

        // Historial de búsquedas recientes
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 100),
          sliver: SliverToBoxAdapter(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Búsquedas recientes',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF263238),
                  ),
                ),
                const SizedBox(height: 12),
                FutureBuilder<QuerySnapshot>(
                  future: FirebaseFirestore.instance
                      .collection('solicitudes_direcciones')
                      .where('solicitante_email',
                          isEqualTo: widget.usuarioEmail)
                      .orderBy('created_at', descending: true)
                      .limit(5)
                      .get(),
                  builder: (context, snapshot) {
                    if (!snapshot.hasData) {
                      return const Center(child: CircularProgressIndicator());
                    }

                    final solicitudes = snapshot.data!.docs;

                    if (solicitudes.isEmpty) {
                      return Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade100,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Center(
                          child: Text(
                            'No hay búsquedas recientes',
                            style: TextStyle(color: Colors.grey, fontSize: 14),
                          ),
                        ),
                      );
                    }

                    // Lógica de deduplicación
                    final Map<String, DocumentSnapshot> busquedasUnicas = {};
                    for (final doc in solicitudes) {
                      final data = doc.data() as Map<String, dynamic>;
                      final direccionNormalizada =
                          data['direccion_normalizada']?.toString() ?? '';
                      if (direccionNormalizada.isNotEmpty &&
                          !busquedasUnicas.containsKey(direccionNormalizada)) {
                        busquedasUnicas[direccionNormalizada] = doc;
                      }
                    }

                    return Column(
                      children: busquedasUnicas.values.map((doc) {
                        final data = doc.data() as Map<String, dynamic>;
                        final direccion =
                            data['direccion_original'] ?? 'Sin dirección';
                        final estado = data['estado'] ?? 'pendiente';
                        final createdAt =
                            (data['created_at'] as Timestamp?)?.toDate();

                        return Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.grey.shade300),
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 8,
                                height: 8,
                                decoration: BoxDecoration(
                                  color: estado == 'aprobada'
                                      ? Colors.green
                                      : estado == 'rechazada'
                                          ? Colors.red
                                          : Colors.orange,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      direccion,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w600,
                                        fontSize: 14,
                                      ),
                                    ),
                                    if (createdAt != null)
                                      Text(
                                        'Hace ${_formatoTiempoRelativo(createdAt)}',
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: Colors.grey[600],
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: estado == 'aprobada'
                                      ? Colors.green.shade100
                                      : estado == 'rechazada'
                                          ? Colors.red.shade100
                                          : Colors.orange.shade100,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Text(
                                  estado.toUpperCase(),
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w600,
                                    color: estado == 'aprobada'
                                        ? Colors.green
                                        : estado == 'rechazada'
                                            ? Colors.red
                                            : Colors.orange,
                                  ),
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
            ),
          ),
        ),
      ],
    );
  }
}
