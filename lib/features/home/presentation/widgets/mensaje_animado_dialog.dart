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

  /// Escena de fondo, elegida por el texto para que cada mensaje tenga la
  /// suya estable: amanecer, bosque, atardecer o lluvia suave.
  static EscenaMensaje escenaDe(String texto) {
    var h = 0;
    for (final c in texto.codeUnits) {
      h = ((h << 5) - h + c) & 0x7fffffff;
    }
    return EscenaMensaje.values[h % EscenaMensaje.values.length];
  }

  static Future<void> mostrar(
    BuildContext context, {
    required String titulo,
    required String cuerpo,
    String iconoEmoji = '🌅',
    VoidCallback? onVerTarjetas,
    EscenaMensaje? escena,
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
        escena: escena ?? escenaDe(cuerpo.isNotEmpty ? cuerpo : titulo),
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

/// Escenas de fondo del mensaje. Amanecer, bosque, atardecer y lluvia:
/// solo naturaleza y luz, nunca símbolos religiosos.
enum EscenaMensaje { amanecer, bosque, atardecer, lluvia }

class _MensajeAnimadoPagina extends StatefulWidget {
  const _MensajeAnimadoPagina({
    required this.titulo,
    required this.cuerpo,
    required this.iconoEmoji,
    required this.onVerTarjetas,
    required this.escena,
  });

  final String titulo;
  final String cuerpo;
  final String iconoEmoji;
  final VoidCallback? onVerTarjetas;
  final EscenaMensaje escena;

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
  late final double _floteAmplitud;
  late final double _floteGiro;
  late final int _floteVelocidad;
  late final double _floteFase;

  static const Cubic _curvaOrganica = Cubic(0.16, 1, 0.3, 1);

  Animation<double> _tramo(double inicio, double fin,
      [Curve curva = _curvaOrganica]) {
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

    _aEmoji = _tramo(0.10, 0.45);
    _aTarjeta = _tramo(0.20, 0.50);
    _aTitulo = _tramo(0.30, 0.55);
    _aCuerpo = _tramo(0.42, 0.72);
    _aCita = _tramo(0.58, 0.88);
    _aBotones = _tramo(0.76, 1.0);

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
    // La tarjeta respira: sube y baja unos píxeles con un giro leve. Cada
    // mensaje tiene su propia deriva, ángulo y ritmo (del texto), así que el
    // movimiento nunca es el mismo dos veces.
    var h = 0;
    for (final c in widget.cuerpo.codeUnits) {
      h = ((h << 5) - h + c) & 0x7fffffff;
    }
    _floteAmplitud = 5 + (h % 5).toDouble();
    _floteGiro = ((h >> 4) % 11 - 5) / 10 * 0.01;
    _floteVelocidad = 1 + ((h >> 8) % 3);
    _floteFase = ((h >> 11) % 100) / 100.0;
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

  /// Entrada orgánica estilo Telegram: fundido + deslizamiento hacia arriba
  /// con `cubic-bezier(0.16, 1, 0.3, 1)`. La curva ya viene en la animación
  /// (Interval); aquí solo se mapea el progreso a opacidad y desplazamiento.
  Widget _aparecer(Animation<double> a, Widget child, {double deslizar = 26}) {
    return AnimatedBuilder(
      animation: a,
      child: child,
      builder: (context, hijo) {
        final v = _c01(a.value);
        return Opacity(
          opacity: v,
          child: Transform.translate(
            offset: Offset(0, (1 - v) * deslizar),
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
                  escena: widget.escena,
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

  /// Contenido flotante sin caja ni tarjeta: icono (rama) arriba, texto
  /// protagonista en el centro, cita y botones abajo. Todo respira con un
  /// vaivén vertical sutil continuo para que la interfaz se sienta viva.
  Widget _contenido() {
    return AnimatedBuilder(
      animation: _ambiente,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _iconoRama(),
          const SizedBox(height: 22),
          _aparecer(
            _aTitulo,
            _textoConBrillo(
              widget.titulo,
              fontSize: 17,
              fontWeight: FontWeight.w600,
              color: Colors.white,
              brillo: const Color.fromRGBO(255, 255, 255, 0.55),
            ),
            deslizar: 24,
          ),
          if (_mensaje.texto.isNotEmpty) ...[
            const SizedBox(height: 14),
            _aparecer(
              _aCuerpo,
              _textoConBrillo(
                _mensaje.texto,
                fontSize: 26,
                fontWeight: FontWeight.w700,
                height: 1.35,
                color: Colors.white,
                brillo: const Color.fromRGBO(255, 255, 255, 0.65),
              ),
              deslizar: 30,
            ),
          ],
          if (_mensaje.cita != null) ...[
            const SizedBox(height: 16),
            _aparecer(_aCita, _citaFlotante(_mensaje)),
          ],
          const SizedBox(height: 26),
          _aparecer(_aBotones, _botonesFlotantes()),
        ],
      ),
      builder: (context, hijo) {
        final a = _ambiente.value * 2 * math.pi * _floteVelocidad +
            _floteFase * 6.28;
        return Transform.translate(
          offset: Offset(0, math.sin(a) * _floteAmplitud),
          child: Transform.rotate(
            angle: math.sin(a * 0.7) * _floteGiro,
            child: hijo,
          ),
        );
      },
    );
  }

  /// Texto con resplandor difuminado detrás (sin contenedor): el brillo lo
  /// separa ópticamente del fondo dinámico.
  Widget _textoConBrillo(
    String texto, {
    required double fontSize,
    required FontWeight fontWeight,
    required Color color,
    required Color brillo,
    double? height,
  }) {
    return Stack(
      alignment: Alignment.center,
      children: [
        Text(
          texto,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontFamily: 'Roboto',
            fontSize: fontSize,
            fontWeight: fontWeight,
            height: height ?? 1.25,
            color: Colors.transparent,
            shadows: [
              Shadow(color: brillo, blurRadius: 22),
              Shadow(color: brillo, blurRadius: 44),
            ],
          ),
        ),
        Text(
          texto,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontFamily: 'Roboto',
            fontSize: fontSize,
            fontWeight: fontWeight,
            height: height ?? 1.25,
            color: color,
            shadows: const [
              Shadow(
                color: Color.fromRGBO(0, 0, 0, 0.45),
                blurRadius: 10,
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// Icono superior con la rama: levita (sube y baja suave) en continuo y
  /// lleva un halo difuminado detrás, sin círculo ni borde sólido.
  Widget _iconoRama() {
    return _aparecer(
      _aEmoji,
      AnimatedBuilder(
        animation: _ambiente,
        builder: (context, _) {
          final levita =
              math.sin(_ambiente.value * 2 * math.pi * 2) * 7;
          return Transform.translate(
            offset: Offset(0, levita),
            child: Container(
              width: 96,
              height: 96,
              alignment: Alignment.center,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: Color.fromRGBO(255, 240, 200, 0.35),
                    blurRadius: 48,
                    spreadRadius: 6,
                  ),
                ],
              ),
              child: Text(
                widget.iconoEmoji,
                style: const TextStyle(fontSize: 56),
              ),
            ),
          );
        },
      ),
      deslizar: 30,
    );
  }

  /// Cita bíblica flotante: sin caja, con brillo suave dorado.
  Widget _citaFlotante(_MensajeParseado m) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (m.versiculo != null) ...[
          _textoConBrillo(
            '«${m.versiculo}»',
            fontSize: 16,
            fontWeight: FontWeight.w600,
            height: 1.45,
            color: const Color(0xFFFFF3C4),
            brillo: const Color.fromRGBO(255, 220, 130, 0.55),
          ),
          const SizedBox(height: 8),
        ],
        Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.menu_book_rounded,
                size: 15, color: Color(0xFFFFE082)),
            const SizedBox(width: 6),
            Flexible(
              child: _textoConBrillo(
                m.cita!,
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: const Color(0xFFFFE082),
                brillo: const Color.fromRGBO(255, 200, 100, 0.5),
              ),
            ),
          ],
        ),
      ],
    );
  }

  /// Botones sin tarjeta: cerrar en texto claro, ver-tarjetas en píldora.
  Widget _botonesFlotantes() {
    return Wrap(
      alignment: WrapAlignment.center,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 10,
      runSpacing: 6,
      children: [
        TextButton(
          onPressed: _cerrar,
          style: TextButton.styleFrom(
            foregroundColor: Colors.white70,
          ),
          child: const Text('Cerrar'),
        ),
        if (widget.onVerTarjetas != null)
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color.fromRGBO(255, 255, 255, 0.92),
              foregroundColor: const Color(0xFF1B5E20),
              shape: const StadiumBorder(),
              padding:
                  const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              elevation: 6,
              shadowColor: const Color.fromRGBO(0, 0, 0, 0.35),
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
    required this.escena,
  }) : super(repaint: Listenable.merge([entrada, ambiente]));

  final Animation<double> entrada;
  final Animation<double> ambiente;
  final List<_Particula> particulas;
  final EscenaMensaje escena;

  @override
  void paint(Canvas canvas, Size size) {
    final t = Curves.easeOutCubic.transform(_c01(entrada.value));
    final amb = ambiente.value;
    final rect = Offset.zero & size;
    final paleta = _paletaCielo(escena, t);

    // 1) Cielo: cada escena tiene su propia transición día/noche.
    canvas.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: paleta.cielo,
          stops: const [0.0, 0.62, 1.0],
        ).createShader(rect),
    );

    switch (escena) {
      case EscenaMensaje.bosque:
        _pintarBosque(canvas, size, t, amb, paleta);
        break;
      case EscenaMensaje.atardecer:
        _pintarAtardecer(canvas, size, t, amb);
        break;
      case EscenaMensaje.lluvia:
        _pintarLluvia(canvas, size, t, amb, paleta);
        break;
      case EscenaMensaje.amanecer:
        _pintarAmanecer(canvas, size, t, amb);
        break;
    }
  }

  /// El cuerpo de la escena original: sol que sube, haces en abanico y
  /// colinas. Se mantiene intacto (amanecer).
  void _pintarAmanecer(Canvas canvas, Size size, double t, double amb) {
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
    _motas(canvas, size, t, amb,
        halo: const Color.fromRGBO(255, 236, 160, 1),
        nucleo: const Color.fromRGBO(255, 248, 210, 1));
  }

  /// Bosque: tres filas de copas que se aclaran con la entrada, con luciérnagas.
  void _pintarBosque(Canvas canvas, Size size, double t, double amb,
      _PaletaCielo paleta) {
    final alto = size.height;
    final filas = [
      (0.66, const Color(0xFF2E7D32), 46.0),
      (0.78, const Color(0xFF1B5E20), 56.0),
      (0.90, const Color(0xFF0D3311), 62.0),
    ];
    for (var f = 0; f < filas.length; f++) {
      final fila = filas[f];
      final baseY = alto * (fila.$1 as double);
      final color = fila.$2 as Color;
      final radioCopa = fila.$3 as double;
      var i = 0;
      for (double x = -radioCopa;
          x <= size.width + radioCopa;
          x += radioCopa * 1.1) {
        final balanceo = math.sin(amb * 2 * math.pi + i * 1.3 + f) * 3;
        canvas.drawCircle(
          Offset(x + balanceo, baseY - radioCopa * 0.35),
          radioCopa * (0.55 + 0.35 * t),
          Paint()..color = color,
        );
        i++;
      }
      canvas.drawRect(
        Rect.fromLTRB(0, baseY, size.width, alto),
        Paint()..color = color.withValues(alpha: 0.55 + 0.45 * t),
      );
    }
    _motas(canvas, size, t, amb,
        halo: const Color.fromRGBO(220, 255, 190, 1),
        nucleo: const Color.fromRGBO(245, 255, 235, 1),
        tamExtra: 0.6);
  }

  /// Atardecer: sol grande bajando al horizonte con franjas cálidas.
  void _pintarAtardecer(Canvas canvas, Size size, double t, double amb) {
    final radio = size.shortestSide * 0.20;
    final centro =
        Offset(size.width / 2, size.height * (0.55 + 0.25 * (1 - t)));
    final respira = 1 + 0.02 * math.sin(amb * 2 * math.pi);
    canvas.drawCircle(centro, radio * 3.0 * respira,
        Paint()..color = const Color.fromRGBO(255, 138, 60, 0.16 * 1));
    canvas.drawCircle(
      centro,
      radio * respira,
      Paint()
        ..shader = const RadialGradient(
          colors: [Color(0xFFFFF3C4), Color(0xFFFFB74D)],
        ).createShader(Rect.fromCircle(center: centro, radius: radio)),
    );
    final subida = (1 - t) * 40;
    _colina(canvas, size, size.height * 0.88 + subida, 12, 1.1,
        const Color(0xFF4E342E));
    _colina(canvas, size, size.height * 0.94 + subida, 10, 3.0,
        const Color(0xFF2D1B16));
    _motas(canvas, size, t, amb,
        halo: const Color.fromRGBO(255, 200, 130, 1),
        nucleo: const Color.fromRGBO(255, 240, 210, 1),
        tamExtra: 0.4);
  }

  /// Lluvia suave: gotas que caen en diagonal sobre colinas azuladas.
  void _pintarLluvia(Canvas canvas, Size size, double t, double amb,
      _PaletaCielo paleta) {
    final subida = (1 - t) * 50;
    _colina(canvas, size, size.height * 0.86 + subida, 13, 0.9,
        const Color(0xFF33691E));
    _colina(canvas, size, size.height * 0.93 + subida, 11, 2.7,
        const Color(0xFF1B4312));
    final pincel = Paint()
      ..color = const Color.fromRGBO(200, 225, 255, 0.75)
      ..strokeWidth = 1.6
      ..strokeCap = StrokeCap.round;
    for (final p in particulas) {
      final avance = (amb * p.velocidad + p.fase) % 1.0;
      final y = avance * size.height;
      final x = p.x * size.width +
          math.sin(amb * 2 * math.pi * p.deriva + p.fase * 6.28) * 10 -
          avance * 30;
      if (avance <= 0.02 || avance >= 0.98) continue;
      canvas.drawLine(Offset(x, y), Offset(x + 3, y + 14), pincel);
    }
  }

  /// Motas de luz compartidas por amanecer, bosque y atardecer.
  void _motas(Canvas canvas, Size size, double t, double amb,
      {required Color halo, required Color nucleo, double tamExtra = 0}) {
    final pincel = Paint();
    for (final p in particulas) {
      final avance = (amb * p.velocidad + p.fase) % 1.0;
      final y = size.height * (1 - avance);
      final x = p.x * size.width +
          math.sin(amb * 2 * math.pi * p.deriva + p.fase * 6.28) * 18;
      final opacidad = math.sin(avance * math.pi) * 0.85 * t;
      if (opacidad <= 0.01) continue;
      pincel.color = Color.fromRGBO(
          (halo.r * 255).round(),
          (halo.g * 255).round(),
          (halo.b * 255).round(),
          _c01(opacidad * 0.25));
      canvas.drawCircle(Offset(x, y), p.tam * 3 + tamExtra * 3, pincel);
      pincel.color = Color.fromRGBO(
          (nucleo.r * 255).round(),
          (nucleo.g * 255).round(),
          (nucleo.b * 255).round(),
          _c01(opacidad));
      canvas.drawCircle(Offset(x, y), p.tam + tamExtra, pincel);
    }
  }

  /// Cielos por escena: inicio (noche) y fin (día) de la transición.
  _PaletaCielo _paletaCielo(EscenaMensaje escena, double t) {
    switch (escena) {
      case EscenaMensaje.bosque:
        return _PaletaCielo([
          Color.lerp(const Color(0xFF0A1F14), const Color(0xFF2E7D32), t)!,
          Color.lerp(const Color(0xFF12281A), const Color(0xFF66BB6A), t)!,
          Color.lerp(const Color(0xFF1A3324), const Color(0xFFC8E6C9), t)!,
        ]);
      case EscenaMensaje.atardecer:
        return _PaletaCielo([
          Color.lerp(const Color(0xFF241019), const Color(0xFF6D2B3C), t)!,
          Color.lerp(const Color(0xFF3A1B26), const Color(0xFFE2683C), t)!,
          Color.lerp(const Color(0xFF4A2430), const Color(0xFFFFD54F), t)!,
        ]);
      case EscenaMensaje.lluvia:
        return _PaletaCielo([
          Color.lerp(const Color(0xFF0D1B2A), const Color(0xFF3E5C76), t)!,
          Color.lerp(const Color(0xFF16283D), const Color(0xFF6B8CA8), t)!,
          Color.lerp(const Color(0xFF1D3557), const Color(0xFFBFD7EA), t)!,
        ]);
      case EscenaMensaje.amanecer:
        return _PaletaCielo([
          Color.lerp(const Color(0xFF071F17), const Color(0xFF0F4D3A), t)!,
          Color.lerp(const Color(0xFF0E3326), const Color(0xFF4DB27A), t)!,
          Color.lerp(const Color(0xFF14402F), const Color(0xFFFFD98A), t)!,
        ]);
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
        old.particulas != particulas ||
        old.escena != escena;
  }
}

/// Tres tonos de cielo (arriba, medio, horizonte) para una escena.
class _PaletaCielo {
  const _PaletaCielo(this.cielo);
  final List<Color> cielo;
}
