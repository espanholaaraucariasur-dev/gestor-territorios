import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ThemeProvider extends ChangeNotifier {
  static const _key = 'dark_mode';
  bool _isDark = false;

  bool get isDark => _isDark;
  ThemeMode get themeMode => _isDark ? ThemeMode.dark : ThemeMode.light;

  ThemeProvider() {
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    _isDark = prefs.getBool(_key) ?? false;
    notifyListeners();
  }

  Future<void> toggle() async {
    _isDark = !_isDark;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_key, _isDark);
    notifyListeners();
  }
}

// InheritedWidget para acceder al provider sin provider package
class ThemeProviderScope extends StatefulWidget {
  final Widget child;
  const ThemeProviderScope({super.key, required this.child});

  @override
  State<ThemeProviderScope> createState() => _ThemeProviderScopeState();

  static ThemeProvider of(BuildContext context) {
    return context
        .dependOnInheritedWidgetOfExactType<_ThemeInherited>()!
        .provider;
  }
}

class _ThemeProviderScopeState extends State<ThemeProviderScope> {
  final ThemeProvider _provider = ThemeProvider();

  @override
  void initState() {
    super.initState();
    _provider.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _provider.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _ThemeInherited(provider: _provider, child: widget.child);
  }
}

class _ThemeInherited extends InheritedWidget {
  final ThemeProvider provider;
  const _ThemeInherited({required this.provider, required super.child});

  @override
  bool updateShouldNotify(_ThemeInherited old) => true;
}
