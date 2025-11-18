import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Controlador de tema
class ThemeController extends ChangeNotifier {
  ThemeController._({ThemeMode initialMode = ThemeMode.light})
      : _mode = initialMode;

  ThemeMode _mode;
  ThemeMode get mode => _mode;

  static const String _themeKey = 'theme_mode';

  /// Cria e carrega um ThemeController com as preferências salvas
  static Future<ThemeController> create() async {
    final controller = ThemeController._();
    await controller._loadThemePreference();
    return controller;
  }

  /// Carrega a preferência de tema salva
  Future<void> _loadThemePreference() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedTheme = prefs.getString(_themeKey);
      if (savedTheme != null) {
        _mode = _parseThemeMode(savedTheme);
        notifyListeners();
      }
    } catch (e) {
      // Se houver erro ao carregar, mantém o modo padrão
    }
  }

  /// Converte string para ThemeMode
  ThemeMode _parseThemeMode(String value) {
    switch (value) {
      case 'light':
        return ThemeMode.light;
      case 'dark':
        return ThemeMode.dark;
      case 'system':
        return ThemeMode.system;
      default:
        return ThemeMode.light;
    }
  }

  /// Converte ThemeMode para string
  String _themeModeToString(ThemeMode mode) {
    switch (mode) {
      case ThemeMode.light:
        return 'light';
      case ThemeMode.dark:
        return 'dark';
      case ThemeMode.system:
        return 'system';
    }
  }

  /// Define o modo do tema e salva a preferência
  Future<void> setMode(ThemeMode newMode) async {
    if (newMode == _mode) return;
    _mode = newMode;
    notifyListeners();
    
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_themeKey, _themeModeToString(newMode));
    } catch (e) {
      // Se houver erro ao salvar, continua normalmente
    }
  }

  /// Alterna entre tema claro e escuro
  Future<void> toggle() async {
    final newMode = _mode == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark;
    await setMode(newMode);
  }
}

/// Provedor de ThemeController
class ThemeControllerProvider e\xtends InheritedWidget {
  /// Construtor da classe [ThemeControllerProvider]
  const ThemeControllerProvider({
    required this.controller,
    required super.child,
    super.key,
  });

  final ThemeController controller;

  static ThemeController of(BuildContext context) {
    final provider =
        context.dependOnInheritedWidgetOfExactType<ThemeControllerProvider>();
    assert(provider != null, 'ThemeControllerProvider not found in context');
    return provider!.controller;
  }

  @override
  bool updateShouldNotify(ThemeControllerProvider oldWidget) =>
      oldWidget.controller != controller;
}








