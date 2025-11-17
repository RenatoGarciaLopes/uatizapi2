import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:zapizapi/services/password_recovery_service.dart';
import 'package:zapizapi/utils/routes_enum.dart';
import 'package:zapizapi/ui/widgets/custom_button.dart';
import 'package:zapizapi/ui/widgets/custom_input.dart';
import 'package:zapizapi/ui/widgets/custom_text_button.dart';

/// Tela para solicitar recuperação de senha
class ForgotPasswordScreen extends StatefulWidget {
  /// Construtor
  const ForgotPasswordScreen({super.key});

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _emailController = TextEditingController();
  bool _isLoading = false;
  final PasswordRecoveryService _service = PasswordRecoveryService();

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  String? _validateEmail(String? value) {
    final text = value?.trim() ?? '';
    if (text.isEmpty) return 'Informe seu email';
    final emailRegex = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');
    if (!emailRegex.hasMatch(text)) return 'Email inválido';
    return null;
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isLoading = true);
    try {
      // Mobile usa deep link (scheme); Web usa a mesma origem com hash routing
      const mobileScheme = 'zapizapi://reset';
      final redirect = kIsWeb
          ? '${Uri.base.origin}#${RoutesEnum.resetPassword.route}'
          : mobileScheme;
      await _service.sendPasswordResetEmail(
        email: _emailController.text.trim(),
        redirectTo: redirect,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Se existir uma conta com este email, enviaremos um link de redefinição.',
          ),
        ),
      );
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Não foi possível enviar o email. Tente novamente.'),
        ),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Recuperar senha')),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Informe seu email. Enviaremos um link para redefinir sua senha.',
                ),
                const SizedBox(height: 18),
                CustomInput(
                  label: 'Email',
                  hint: 'Digite seu email',
                  controller: _emailController,
                  keyboardType: TextInputType.emailAddress,
                  validator: _validateEmail,
                ),
                const SizedBox(height: 18),
                CustomButton(
                  backgroundColor: Theme.of(context).colorScheme.primary,
                  buttonText: _isLoading ? 'Enviando...' : 'Enviar link',
                  buttonAction: _isLoading ? () {} : _submit,
                ),
                const SizedBox(height: 8),
                CustomTextButton(
                  buttonText: 'Voltar ao login',
                  buttonAction: () => Navigator.of(context).pop(),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}


