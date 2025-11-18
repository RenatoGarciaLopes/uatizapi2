import 'package:supabase_flutter/supabase_flutter.dart';

/// Serviço responsável pela recuperação e redefinição de senha
class PasswordRecoveryService {
  /// Envia email de recuperação de senha via Supabase
  Future<void> sendPasswordResetEmail({
    required String email,
    required String redirectTo,
  }) async {
    final supabase = Supabase.instance.client;
    await supabase.auth.resetPasswordForEmail(
      email,
      redirectTo: redirectTo,
    );
  }

  /// Atualiza a senha do usuário após o redirecionamento de recuperação
  Future<void> updatePassword({
    required String newPassword,
  }) async {
    final supabase = Supabase.instance.client;
    await supabase.auth.updateUser(
      UserAttributes(password: newPassword),
    );
  }
}






