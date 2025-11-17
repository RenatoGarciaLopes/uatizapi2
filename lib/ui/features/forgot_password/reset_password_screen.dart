import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:zapizapi/services/password_recovery_service.dart';
import 'package:zapizapi/ui/widgets/custom_button.dart';
import 'package:zapizapi/ui/widgets/custom_input.dart';
import 'package:zapizapi/utils/routes_enum.dart';

/// Tela exibida após abrir o link de recuperação (deep link)
/// Permite definir uma nova senha
class ResetPasswordScreen extends StatefulWidget {
  /// Construtor
  const ResetPasswordScreen({super.key});

  @override
  State<ResetPasswordScreen> createState() => _ResetPasswordScreenState();
}

class _ResetPasswordScreenState extends State<ResetPasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _confirmController = TextEditingController();
  bool _obscure1 = true;
  bool _obscure2 = true;
  bool _isLoading = false;
  final PasswordRecoveryService _service = PasswordRecoveryService();

  Future<void> _ensureRecoverySession() async {
    final auth = Supabase.instance.client.auth;
    if (auth.currentSession != null) return;
    if (!kIsWeb) return;

    // Para Web, use a API própria que processa a URL de callback PKCE
    try {
      await auth.getSessionFromUrl(Uri.base);
    } catch (_) {
      // Silencioso: vamos avisar no submit se continuar sem sessão
    }
  }

  @override
  void dispose() {
    _passwordController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  String? _validatePassword(String? value) {
    final text = value ?? '';
    if (text.isEmpty) return 'Informe a nova senha';
    if (text.length < 6) return 'A senha deve ter pelo menos 6 caracteres';
    return null;
  }

  String? _validateConfirm(String? value) {
    if (value != _passwordController.text) return 'As senhas não coincidem';
    return null;
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isLoading = true);
    try {
      await _ensureRecoverySession();
      if (Supabase.instance.client.auth.currentSession == null) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Link de recuperação inválido ou expirado. Solicite um novo email.',
            ),
          ),
        );
        return;
      }

      await _service.updatePassword(newPassword: _passwordController.text);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Senha atualizada com sucesso!')),
      );
      await Navigator.of(context).pushNamedAndRemoveUntil(
        RoutesEnum.login.route,
        (_) => false,
      );
    } on AuthException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            e.message.isNotEmpty
                ? e.message
                : 'Não foi possível atualizar a senha. Tente novamente.',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erro: $e')),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Redefinir senha')),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text('Defina sua nova senha para concluir a recuperação.'),
                const SizedBox(height: 18),
                CustomInput(
                  label: 'Nova senha',
                  hint: 'Digite a nova senha',
                  controller: _passwordController,
                  obsecureText: _obscure1,
                  validator: _validatePassword,
                  suffixIcon: IconButton(
                    icon: Icon(_obscure1 ? Icons.visibility : Icons.visibility_off),
                    onPressed: () => setState(() => _obscure1 = !_obscure1),
                  ),
                ),
                const SizedBox(height: 18),
                CustomInput(
                  label: 'Confirmar nova senha',
                  hint: 'Repita a nova senha',
                  controller: _confirmController,
                  obsecureText: _obscure2,
                  validator: _validateConfirm,
                  suffixIcon: IconButton(
                    icon: Icon(_obscure2 ? Icons.visibility : Icons.visibility_off),
                    onPressed: () => setState(() => _obscure2 = !_obscure2),
                  ),
                ),
                const SizedBox(height: 18),
                CustomButton(
                  backgroundColor: Theme.of(context).colorScheme.primary,
                  buttonText: _isLoading ? 'Atualizando...' : 'Atualizar senha',
                  buttonAction: _isLoading ? () {} : _submit,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}


