import 'package:flutter/material.dart';
import 'app_translations.dart';

class TranslationService extends InheritedWidget {
  final String currentLanguage;
  final Function(String) changeLanguage;

  const TranslationService({
    super.key,
    required this.currentLanguage,
    required this.changeLanguage,
    required super.child,
  });

  static TranslationService? of(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<TranslationService>();
  }

  String translate(String key, {List<String>? args}) {
    return AppTranslations.translate(key,
        language: currentLanguage, args: args);
  }

  // Método de conveniencia para traducción corta
  String t(String key, {List<String>? args}) {
    return translate(key, args: args);
  }

  @override
  bool updateShouldNotify(TranslationService oldWidget) {
    return oldWidget.currentLanguage != currentLanguage;
  }
}

class TranslationProvider extends StatefulWidget {
  final Widget child;
  final String initialLanguage;

  const TranslationProvider({
    super.key,
    required this.child,
    this.initialLanguage = 'ES',
  });

  @override
  State<TranslationProvider> createState() => _TranslationProviderState();
}

class _TranslationProviderState extends State<TranslationProvider> {
  late String _currentLanguage;

  @override
  void initState() {
    super.initState();
    _currentLanguage = widget.initialLanguage;
  }

  void changeLanguage(String language) {
    setState(() {
      _currentLanguage = language;
    });
  }

  @override
  Widget build(BuildContext context) {
    return TranslationService(
      currentLanguage: _currentLanguage,
      changeLanguage: changeLanguage,
      child: widget.child,
    );
  }
}

// Extension methods para facilitar el uso
extension BuildContextX on BuildContext {
  String t(String key, {List<String>? args}) {
    final service = TranslationService.of(this);
    return service?.translate(key, args: args) ?? key;
  }

  String get currentLanguage {
    return TranslationService.of(this)?.currentLanguage ?? 'ES';
  }

  void changeLanguage(String language) {
    TranslationService.of(this)?.changeLanguage(language);
  }
}

// Widget helper para traducciones
class TranslatedText extends StatelessWidget {
  final String translationKey;
  final List<String>? args;
  final TextStyle? style;
  final TextAlign? textAlign;
  final StrutStyle? strutStyle;
  final TextDirection? textDirection;
  final Locale? locale;
  final bool? softWrap;
  final TextOverflow? overflow;
  final double? textScaleFactor;
  final int? maxLines;
  final String? semanticsLabel;

  const TranslatedText(
    this.translationKey, {
    super.key,
    this.args,
    this.style,
    this.textAlign,
    this.strutStyle,
    this.textDirection,
    this.locale,
    this.softWrap,
    this.overflow,
    this.textScaleFactor,
    this.maxLines,
    this.semanticsLabel,
  });

  @override
  Widget build(BuildContext context) {
    return Text(
      context.t(translationKey, args: args),
      style: style,
      textAlign: textAlign,
      strutStyle: strutStyle,
      textDirection: textDirection,
      locale: locale,
      softWrap: softWrap,
      overflow: overflow,
      textScaleFactor: textScaleFactor,
      maxLines: maxLines,
      semanticsLabel: semanticsLabel,
    );
  }
}
