import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:zapizapi/ui/features/home/home_screen.dart';
import 'package:zapizapi/ui/features/login/login_screen.dart';
import 'package:zapizapi/ui/features/forgot_password/forgot_password_screen.dart';
import 'package:zapizapi/ui/features/forgot_password/reset_password_screen.dart';
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
    authOptions: const FlutterAuthClientOptions(
      authFlowType: AuthFlowType.pkce,
    ),
  );
  // Decide rota inicial no WEB se houver ?code=... (recuperação)
  String initialRoute = RoutesEnum.login.route;
  if (kIsWeb) {
    final uri = Uri.base;
    String? code = uri.queryParameters['code'];
    if (code == null || code.isEmpty) {
      final fragment = uri.fragment; // ex.: /login?code=...
      if (fragment.isNotEmpty) {
        try {
          final synthetic = Uri.parse(
            'https://fragment${fragment.startsWith('/') ? '' : '/'}$fragment',
          );
          code = synthetic.queryParameters['code'];
        } catch (_) {}
      }
    }
    if (code != null && code.isNotEmpty) {
      // Usa a API web para ler a sessão do callback (PKCE)
      try {
        await Supabase.instance.client.auth.getSessionFromUrl(uri);
      } catch (_) {
        // segue para tela de reset mesmo sem sessão para feedback
      }
      initialRoute = RoutesEnum.resetPassword.route;
    }
  }
  runApp(MainApp(initialRoute: initialRoute));
}

/// Aplicação principal
class MainApp extends StatefulWidget {
  /// Construtor da classe [MainApp]
  const MainApp({super.key, this.initialRoute = '/login'});

  /// Rota inicial (definida em tempo de execução)
  final String initialRoute;

  @override
  State<MainApp> createState() => _MainAppState();
}

class _MainAppState extends State<MainApp> {
  final ThemeController _themeController = ThemeController();
  late final Stream<AuthState> _authSub;

  @override
  void initState() {
    super.initState();
    // Escuta eventos de autenticação para detectar recuperação de senha
    _authSub = Supabase.instance.client.auth.onAuthStateChange;
    _authSub.listen((state) {
      final event = state.event;
      if (event == AuthChangeEvent.passwordRecovery) {
        // Navega para a tela de redefinição ao abrir o deep link
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          Navigator.of(context).pushNamed(RoutesEnum.resetPassword.route);
        });
      }
    });

    // Removido: troca manual de code por sessão. O bootstrap já chamou
    // getSessionFromUrl(Uri.base) quando necessário.
  }

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
              RoutesEnum.forgotPassword.route: (context) =>
                  const ForgotPasswordScreen(),
              RoutesEnum.resetPassword.route: (context) =>
                  const ResetPasswordScreen(),
              RoutesEnum.register.route: (context) => const RegisterScreen(),
              RoutesEnum.home.route: (context) => const HomeScreen(),
            },
            initialRoute: widget.initialRoute,
          );
        },
      ),
    );
  }
}
