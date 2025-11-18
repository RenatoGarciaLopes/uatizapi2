import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Serviço responsável pelo registro de usuários
class RegisterService {
  /// Envia os dados de registro do usuário para o Supabase
  Future<void> sendRegister(
    String fullName,
    String email,
    String password,
  ) async {
    final supabase = Supabase.instance.client;
    // Define o redirect do link de confirmação:
    // - Mobile: deep link capturado pelo app (intent-filter)
    // - Web: volta para a origem do site (hash routing para login)
    final redirect = kIsWeb
        ? '${Uri.base.origin}#/login'
        : 'zapizapi://auth-callback';
    await supabase.auth.signUp(
      data: {'full_name': fullName},
      password: password,
      email: email,
      emailRedirectTo: redirect,
    );
  }
}
