import 'package:flutter/material.dart';

class ThemeController extends ChangeNotifier {
  ThemeController({ThemeMode initialMode = ThemeMode.light})
      : _mode = initialMode;

  ThemeMode _mode;
  ThemeMode get mode => _mode;

  void setMode(ThemeMode newMode) {
    if (newMode == _mode) return;
    _mode = newMode;
    notifyListeners();
  }

  void toggle() {
    setMode(_mode == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark);
  }
}

class ThemeControllerProvider extends InheritedWidget {
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




