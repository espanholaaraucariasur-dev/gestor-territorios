import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Ventana animada para los mensajes motivacionales de la predicación.
///
/// Escena: un amanecer sobre colinas verdes (sol que sale, haces de luz en
/// abanico y motas de luz que suben). Encima, una tarjeta con el título, el
/// mensaje y, si el texto trae una cita bíblica ("Mateo 24:14",
/// "1 Corintios 3:9"...), la resalta en un bloque aparte con brillo suave.
///
/// REGLA DE CONTENIDO: solo imágenes de naturaleza y luz (amanecer, colinas,
/// plantas, mundo). Nada de cruces, templos o iglesias, ni símbolos
/// católicos o evangélicos (palomas, aureolas, custodias, velas, etc.).
/// Si se agregan emojis o dibujos nuevos, hay que respetar esto.
///
/// No usa imágenes ni fuentes propias (todo se dibuja con código) y respeta
/// la opción "quitar animaciones" del sistema. Mismo uso que el diálogo
/// anterior:
///
///   MensajeAnimadoDialog.mostrar(context,
///       titulo: '...', cuerpo: '...', iconoEmoji: '🌅', onVerTarjetas: () {});
class MensajeAnimadoDialog {
  const MensajeAnimadoDialog._();

  static Future<void> mostrar(
    BuildContext context, {
    required String titulo,
    required String cuerpo,
    String iconoEmoji = '🌅',
    VoidCallback? onVerTarjetas,
  }) {
    HapticFeedback.lightImpact();
    return showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Cerrar mensaje',
      barrierColor: const Color.fromRGBO(0, 0, 0, 0.55),
      transitionDuration: const Duration(milliseconds: 380),
      pageBuilder: (ctx, animation, secondaryAnimation) => _MensajeAnimadoPagina(
        titulo: titulo,
        cuerpo: cuerpo,
        iconoEmoji: iconoEmoji,
        onVerTarjetas: onVerTarjetas,
      ),
      transitionBuilder: (ctx, animation, secondaryAnimation, child) {
        return FadeTransition(
          opacity: CurvedAnimation(parent: animation, curve: Curves.easeOut),
          child: child,
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Detección de la cita bíblica dentro del texto
// ---------------------------------------------------------------------------

/// Solo se reconocen citas con nombre de libro (lista de abajo) seguido de
/// capítulo:versículo. Una lista cerrada evita falsos positivos como
/// "Reunión 10:30", que un patrón genérico tomaría por cita.
const List<String> _librosBiblia = [
  'Génesis', 'Éxodo', 'Levítico', 'Números', 'Deuteronomio', 'Josué',
  'Jueces', 'Rut', 'Samuel', 'Reyes', 'Crónicas', 'Esdras', 'Nehemías',
  'Ester', 'Job', 'Salmos', 'Salmo', 'Proverbios', 'Eclesiastés',
  'Cantar de los Cantares', 'Cantares', 'Isaías', 'Jeremías',
  'Lamentaciones', 'Ezequiel', 'Daniel', 'Oseas', 'Joel', 'Amós', 'Abdías',
  'Jonás', 'Miqueas', 'Nahúm', 'Habacuc', 'Sofonías', 'Hageo', 'Zacarías',
  'Malaquías', 'Mateo', 'Marcos', 'Lucas', 'Juan', 'Hechos', 'Romanos',
  'Corintios', 'Gálatas', 'Efesios', 'Filipenses', 'Colosenses',
  'Tesalonicenses', 'Timoteo', 'Tito', 'Filemón', 'Hebreos', 'Santiago',
  'Pedro', 'Judas', 'Apocalipsis',
];

// Grupo 1: carácter previo (o inicio de texto), para no cortar a mitad de
// palabra sin usar lookbehind (que falla en Safari antiguo, como el de iOS).
// Grupo 2: la cita completa.
final RegExp _regexCita = RegExp(
  r'(^|[^A-Za-zÁ-úÑñ])((?:[123]\s?)?(?:' +
      _librosBiblia.join('|') +
      r')\s+\d{1,3}:\d{1,3}(?:\s?[-–]\s?\d{1,3})?(?:\s?,\s?\d{1,3})*)',
  caseSensitive: false,
);

/// Texto entre comillas («...», “...” o "..."), de al menos 12 caracteres.
final RegExp _regexVersiculo = RegExp(r'[«“"]([^»”"]{12,}?)[»”"]');

class _MensajeParseado {
  const _MensajeParseado(this.texto, this.versiculo, this.cita);

  final String texto;
  final String? versiculo;
  final String? cita;
}

_MensajeParseado _parsearMensaje(String cuerpo) {
  final m = _regexCita.firstMatch(cuerpo);
  if (m == null) return _MensajeParseado(cuerpo.trim(), null, null);

  final inicio = m.start + m.group(1)!.length;
  final cita = m.group(2)!.trim();
  var texto = cuerpo.replaceRange(inicio, m.end, '');

  // El texto entre comillas solo se separa si hay cita: así una frase
  // motivacional entre comillas, sin referencia bíblica, queda como texto.
  String? versiculo;
  final v = _regexVersiculo.firstMatch(texto);
  if (v != null) {
    versiculo = v.group(1)!.trim();
    texto = texto.replaceRange(v.start, v.end, '');
  }

  texto = texto
      .replaceAll(RegExp(r'\(\s*[,;.]?\s*\)'), '')
      .replaceAll(RegExp(r'[ \t]{2,}'), ' ');
  texto = texto.replaceAllMapped(RegExp(r'\s+([,.;:!?])'), (x) => x.group(1)!);
  texto = texto.replaceAll(RegExp(r'[\s,;\-–—]+$'), '').trim();

  return _MensajeParseado(texto, versiculo, cita);
}

double _c01(double v) => v < 0 ? 0 : (v > 1 ? 1 : v);

// ---------------------------------------------------------------------------
// Pantalla
// ---------------------------------------------------------------------------

class _MensajeAnimadoPagina extends StatefulWidget {
  const _MensajeAnimadoPagina({
    required this.titulo,
    required this.cuerpo,
    required this.iconoEmoji,
    required this.onVerTarjetas,
  });

  final String titulo;
  final String cuerpo;
  final String iconoEmoji;
  final VoidCallback? onVerTarjetas;

  @override
  State<_MensajeAnimadoPagina> createState() => _MensajeAnimadoPaginaState();
}

class _MensajeAnimadoPaginaState extends State<_MensajeAnimadoPagina>
    with TickerProviderStateMixin {
  late final AnimationController _entrada;
  late final AnimationController _ambiente;
  late final List<_Particula> _particulas;
  late final _MensajeParseado _mensaje;

  late final Animation<double> _aEmoji;
  late final Animation<double> _aTarjeta;
  late final Animation<double> _aTitulo;
  late final Animation<double> _aCuerpo;
  late final Animation<double> _aCita;
  late final Animation<double> _aBotones;

  bool _iniciado = false;

  Animation<double> _tramo(double inicio, double fin,
      [Curve curva = Curves.easeOutCubic]) {
    return _entrada.drive(CurveTween(curve: Interval(inicio, fin, curve: curva)));
  }

  @override
  void initState() {
    super.initState();
    _entrada = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2600),
    );
    _ambiente = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 14),
    );

    _aEmoji = _tramo(0.12, 0.50, Curves.elasticOut);
    _aTarjeta = _tramo(0.20, 0.50);
    _aTitulo = _tramo(0.32, 0.58);
    _aCuerpo = _tramo(0.44, 0.72);
    _aCita = _tramo(0.58, 0.88);
    _aBotones = _tramo(0.78, 1.0);

    final azar = math.Random(11);
    _particulas = List.generate(
      18,
      (_) => _Particula(
        x: azar.nextDouble(),
        velocidad: 1 + azar.nextInt(3),
        fase: azar.nextDouble(),
        deriva: 1 + azar.nextInt(3),
        tam: 1.4 + azar.nextDouble() * 2.2,
      ),
    );
    _mensaje = _parsearMensaje(widget.cuerpo);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_iniciado) return;
    _iniciado = true;
    if (MediaQuery.of(context).disableAnimations) {
      // El usuario pidió quitar animaciones: se muestra directo el estado final.
      _entrada.value = 1;
    } else {
      _entrada.forward();
      _ambiente.repeat();
    }
  }

  @override
  void dispose() {
    _entrada.dispose();
    _ambiente.dispose();
    super.dispose();
  }

  void _cerrar() => Navigator.of(context).pop();

  Widget _aparecer(Animation<double> a, Widget child, {double deslizar = 14}) {
    return AnimatedBuilder(
      animation: a,
      child: child,
      builder: (context, hijo) {
        return Opacity(
          opacity: _c01(a.value),
          child: Transform.translate(
            offset: Offset(0, (1 - _c01(a.value)) * deslizar),
            child: hijo,
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      type: MaterialType.transparency,
      child: Stack(
        children: [
          Positioned.fill(
            child: RepaintBoundary(
              child: CustomPaint(
                painter: _CieloPainter(
                  entrada: _entrada,
                  ambiente: _ambiente,
                  particulas: _particulas,
                ),
              ),
            ),
          ),
          SafeArea(
            child: LayoutBuilder(
              builder: (context, c) {
                return SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
                  child: GestureDetector(
                    // Tocar fuera de la tarjeta cierra la ventana.
                    behavior: HitTestBehavior.opaque,
                    onTap: _cerrar,
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        minHeight: math.max(0.0, c.maxHeight - 48),
                      ),
                      child: Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 460),
                          child: GestureDetector(
                            // Absorbe el toque para que tocar la tarjeta no cierre.
                            onTap: () {},
                            child: _contenido(),
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          Positioned(
            top: 0,
            right: 0,
            child: SafeArea(
              child: IconButton(
                tooltip: 'Cerrar',
                icon: const Icon(Icons.close_rounded, color: Colors.white),
                onPressed: _cerrar,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _contenido() {
    return Stack(
      clipBehavior: Clip.none,
      alignment: Alignment.topCenter,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 42),
          child: _aparecer(_aTarjeta, _tarjeta(), deslizar: 28),
        ),
        _emoji(),
      ],
    );
  }

  Widget _emoji() {
    return AnimatedBuilder(
      animation: Listenable.merge([_aEmoji, _ambiente]),
      builder: (context, _) {
        final pulso = 1 + 0.035 * math.sin(_ambiente.value * 2 * math.pi * 2);
        final escala = math.max(0.001, _aEmoji.value * pulso);
        return Opacity(
          opacity: _c01(_aEmoji.value),
          child: Transform.scale(
            scale: escala,
            child: Container(
              width: 84,
              height: 84,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: const RadialGradient(
                  colors: [Color(0xFFFFF8E1), Color(0xFFFFE082)],
                ),
                border: Border.all(color: const Color(0xFFFFFFFF), width: 3),
                boxShadow: const [
                  BoxShadow(
                    color: Color.fromRGBO(255, 214, 79, 0.55),
                    blurRadius: 24,
                    spreadRadius: 2,
                  ),
                ],
              ),
              child: Text(widget.iconoEmoji, style: const TextStyle(fontSize: 40)),
            ),
          ),
        );
      },
    );
  }

  Widget _tarjeta() {
    final m = _mensaje;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(22, 54, 22, 18),
      decoration: BoxDecoration(
        color: const Color.fromRGBO(255, 255, 255, 0.95),
        borderRadius: BorderRadius.circular(26),
        boxShadow: const [
          BoxShadow(
            color: Color.fromRGBO(0, 0, 0, 0.28),
            blurRadius: 32,
            offset: Offset(0, 16),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _aparecer(
            _aTitulo,
            Text(
              widget.titulo,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                height: 1.2,
                color: Color(0xFF1B5E20),
              ),
            ),
          ),
          if (m.texto.isNotEmpty) ...[
            const SizedBox(height: 12),
            _aparecer(
              _aCuerpo,
              Text(
                m.texto,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 15.5,
                  height: 1.5,
                  color: Color(0xFF37474F),
                ),
              ),
            ),
          ],
          if (m.cita != null) ...[
            const SizedBox(height: 16),
            _aparecer(_aCita, _bloqueCita(m)),
          ],
          const SizedBox(height: 18),
          _aparecer(_aBotones, _botones()),
        ],
      ),
    );
  }

  Widget _bloqueCita(_MensajeParseado m) {
    return AnimatedBuilder(
      animation: _ambiente,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.format_quote_rounded, color: Color(0xFFBF8F00), size: 22),
          if (m.versiculo != null) ...[
            const SizedBox(height: 2),
            Text(
              '«${m.versiculo}»',
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 15,
                height: 1.45,
                fontStyle: FontStyle.italic,
                color: Color(0xFF4E3B00),
              ),
            ),
            const SizedBox(height: 8),
          ],
          Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.menu_book_rounded, size: 16, color: Color(0xFF8D6E00)),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  m.cita!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF6D4C00),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
      builder: (context, hijo) {
        final brillo = 0.5 + 0.5 * math.sin(_ambiente.value * 2 * math.pi);
        return Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          decoration: BoxDecoration(
            color: const Color(0xFFFFF8E1),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: Color.fromRGBO(255, 193, 7, 0.35 + 0.35 * brillo),
              width: 1.4,
            ),
            boxShadow: [
              BoxShadow(
                color: Color.fromRGBO(255, 193, 7, 0.10 + 0.18 * brillo),
                blurRadius: 16,
              ),
            ],
          ),
          child: hijo,
        );
      },
    );
  }

  Widget _botones() {
    return Wrap(
      alignment: WrapAlignment.center,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 8,
      runSpacing: 4,
      children: [
        TextButton(onPressed: _cerrar, child: const Text('Cerrar')),
        if (widget.onVerTarjetas != null)
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF1B5E20),
              foregroundColor: Colors.white,
              shape: const StadiumBorder(),
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
            ),
            onPressed: () {
              final alVer = widget.onVerTarjetas;
              _cerrar();
              alVer?.call();
            },
            icon: const Icon(Icons.credit_card_outlined, size: 18),
            label: const Text('Ver mis tarjetas'),
          ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Fondo animado
// ---------------------------------------------------------------------------

class _Particula {
  const _Particula({
    required this.x,
    required this.velocidad,
    required this.fase,
    required this.deriva,
    required this.tam,
  });

  final double x; // posición horizontal (0..1)
  final int velocidad; // vueltas por ciclo; entero para que el bucle no salte
  final double fase;
  final int deriva; // oscilaciones laterales por ciclo (entero, mismo motivo)
  final double tam;
}

class _CieloPainter extends CustomPainter {
  _CieloPainter({
    required this.entrada,
    required this.ambiente,
    required this.particulas,
  }) : super(repaint: Listenable.merge([entrada, ambiente]));

  final Animation<double> entrada;
  final Animation<double> ambiente;
  final List<_Particula> particulas;

  @override
  void paint(Canvas canvas, Size size) {
    final t = Curves.easeOutCubic.transform(_c01(entrada.value));
    final amb = ambiente.value;
    final rect = Offset.zero & size;

    // 1) Cielo: de la noche al amanecer.
    canvas.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color.lerp(const Color(0xFF071F17), const Color(0xFF0F4D3A), t)!,
            Color.lerp(const Color(0xFF0E3326), const Color(0xFF4DB27A), t)!,
            Color.lerp(const Color(0xFF14402F), const Color(0xFFFFD98A), t)!,
          ],
          stops: const [0.0, 0.62, 1.0],
        ).createShader(rect),
    );

    // 2) Sol que sube desde detrás de las colinas.
    final radio = size.shortestSide * 0.17;
    final centro = Offset(size.width / 2, size.height * (1.10 - 0.30 * t));

    // Haces de luz en abanico hacia arriba desde el horizonte, con un vaivén
    // suave, como un amanecer real. A propósito NO es un disco con rayos que
    // giran en círculo completo: esa figura puede recordar simbología
    // religiosa (custodias, aureolas) y esta app no debe tenerla.
    final largo = size.longestSide * 1.2;
    canvas.save();
    canvas.translate(centro.dx, centro.dy);
    canvas.rotate(0.10 * math.sin(amb * 2 * math.pi));
    const rayos = 9;
    const arco = math.pi * 0.84; // abanico de unos 150 grados, hacia arriba
    for (var i = 0; i < rayos; i++) {
      // -pi/2 es "arriba" (el eje y del canvas crece hacia abajo).
      final centroRayo = -math.pi / 2 - arco / 2 + (i + 0.5) * (arco / rayos);
      const mitadAncho = (arco / rayos) * 0.21;
      final a1 = centroRayo - mitadAncho;
      final a2 = centroRayo + mitadAncho;
      // Cada haz respira a su propio ritmo (frecuencia entera: el bucle no salta).
      final pulso = 0.65 + 0.35 * math.sin(amb * 2 * math.pi + i * 1.7);
      final pintaRayo = Paint()
        ..shader = RadialGradient(
          colors: [
            Color.fromRGBO(255, 244, 200, 0.26 * t * pulso),
            const Color.fromRGBO(255, 244, 200, 0),
          ],
        ).createShader(Rect.fromCircle(center: Offset.zero, radius: largo));
      final rayo = Path()
        ..moveTo(0, 0)
        ..lineTo(math.cos(a1) * largo, math.sin(a1) * largo)
        ..lineTo(math.cos(a2) * largo, math.sin(a2) * largo)
        ..close();
      canvas.drawPath(rayo, pintaRayo);
    }
    canvas.restore();

    // Halo y disco del sol.
    canvas.drawCircle(
      centro,
      radio * 3.2,
      Paint()
        ..shader = RadialGradient(
          colors: [
            Color.fromRGBO(255, 224, 130, 0.55 * t),
            const Color.fromRGBO(255, 224, 130, 0),
          ],
        ).createShader(Rect.fromCircle(center: centro, radius: radio * 3.2)),
    );
    canvas.drawCircle(
      centro,
      radio,
      Paint()
        ..shader = const RadialGradient(
          colors: [Color(0xFFFFFDE7), Color(0xFFFFE082)],
        ).createShader(Rect.fromCircle(center: centro, radius: radio)),
    );

    // 3) Colinas (suben un poco al entrar).
    final subida = (1 - t) * 60;
    _colina(canvas, size, size.height * 0.84 + subida, 14, 0.6,
        const Color(0xFF43A047));
    _colina(canvas, size, size.height * 0.90 + subida, 12, 2.3,
        const Color(0xFF1B5E20));

    // 4) Motas de luz que suben. Velocidad y deriva son enteras para que al
    // reiniciar el ciclo no se note el salto.
    final pincel = Paint();
    for (final p in particulas) {
      final avance = (amb * p.velocidad + p.fase) % 1.0;
      final y = size.height * (1 - avance);
      final x = p.x * size.width +
          math.sin(amb * 2 * math.pi * p.deriva + p.fase * 6.28) * 18;
      final opacidad = math.sin(avance * math.pi) * 0.85 * t;
      if (opacidad <= 0.01) continue;
      pincel.color = Color.fromRGBO(255, 236, 160, _c01(opacidad * 0.25));
      canvas.drawCircle(Offset(x, y), p.tam * 3, pincel);
      pincel.color = Color.fromRGBO(255, 248, 210, _c01(opacidad));
      canvas.drawCircle(Offset(x, y), p.tam, pincel);
    }
  }

  void _colina(Canvas canvas, Size size, double baseY, double amplitud,
      double fase, Color color) {
    final path = Path()
      ..moveTo(0, size.height)
      ..lineTo(0, baseY);
    for (double x = 0; x <= size.width; x += 8) {
      final y = baseY + math.sin((x / size.width) * math.pi * 2 + fase) * amplitud;
      path.lineTo(x, y);
    }
    path
      ..lineTo(size.width, size.height)
      ..close();
    canvas.drawPath(path, Paint()..color = color);
  }

  @override
  bool shouldRepaint(covariant _CieloPainter old) {
    return old.entrada != entrada ||
        old.ambiente != ambiente ||
        old.particulas != particulas;
  }
}
