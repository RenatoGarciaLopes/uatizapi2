import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:zapizapi/ui/features/home/home_screen.dart';
import 'package:zapizapi/ui/features/login/login_screen.dart';
import 'package:zapizapi/ui/features/register/register_screen.dart';
import 'package:zapizapi/ui/theme/theme_controller.dart';
import 'package:zapizapi/utils/routes_enum.dart';

// TODO: Implementar change notifier na main e injetar gerenciamento de estado
// no register screen
// TODO: Integrar login screen com gerenciamento de sessão

Future<void> main() async {
  await dotenv.load();
  await Supabase.initialize(
    url: dotenv.env['SUPABASE_URL'] ?? '',
    anonKey: dotenv.env['SUPABASE_KEY'] ?? '',
  );
  runApp(const MainApp());
}

/// Aplicação principal
class MainApp extends StatefulWidget {
  /// Construtor da classe [MainApp]
  const MainApp({super.key});

  @override
  State<MainApp> createState() => _MainAppState();
}

class _MainAppState extends State<MainApp> {
  final ThemeController _themeController = ThemeController();

  @override
  Widget build(BuildContext context) {
    return ThemeControllerProvider(
      controller: _themeController,
      child: AnimatedBuilder(
        animation: _themeController,
        builder: (context, _) {
          return MaterialApp(
            debugShowCheckedModeBanner: false,
            builder: FToastBuilder(),
            themeMode: _themeController.mode,
            theme: ThemeData(
              useMaterial3: true,
              colorScheme: ColorScheme.fromSeed(
                seedColor: const Color(0xFF2F5D50), // musgo
              ).copyWith(
                surface: const Color(0xFFF4F7F5),
                surfaceContainerLowest: const Color(0xFFF7FAF7),
              ),
              scaffoldBackgroundColor: const Color(0xFFF4F7F5),
              appBarTheme: const AppBarTheme(
                elevation: 0,
                backgroundColor: Color(0xFF2F5D50),
                foregroundColor: Colors.white,
                centerTitle: false,
                titleTextStyle: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: 18,
                ),
              ),
              cardTheme: CardThemeData(
                elevation: 0,
                color: const Color(0xFFF0F3F1),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              listTileTheme: const ListTileThemeData(
                contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              ),
              inputDecorationTheme: InputDecorationTheme(
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
            darkTheme: ThemeData(
              useMaterial3: true,
              colorScheme: ColorScheme.fromSeed(
                seedColor: const Color(0xFF2F5D50), // musgo
                brightness: Brightness.dark,
              ).copyWith(
                surface: const Color(0xFF1F2624),
                surfaceContainerLowest: const Color(0xFF232B28),
              ),
              scaffoldBackgroundColor: const Color(0xFF1C2220),
              appBarTheme: const AppBarTheme(
                elevation: 0,
                backgroundColor: Color(0xFF2F5D50),
                foregroundColor: Colors.white,
                centerTitle: false,
                titleTextStyle: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: 18,
                ),
              ),
              cardTheme: CardThemeData(
                elevation: 0,
                color: const Color(0xFF29312E),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              listTileTheme: const ListTileThemeData(
                contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              ),
              inputDecorationTheme: InputDecorationTheme(
                filled: true,
                fillColor: const Color(0xFF2B332F),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
            routes: {
              RoutesEnum.login.route: (context) => LoginScreen(),
              RoutesEnum.register.route: (context) => const RegisterScreen(),
              RoutesEnum.home.route: (context) => const HomeScreen(),
            },
            initialRoute: RoutesEnum.login.route,
          );
        },
      ),
    );
  }
}
