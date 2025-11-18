import 'dart:io';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:zapizapi/services/notification_service.dart';
import 'package:zapizapi/ui/widgets/custom_button.dart';
import 'package:zapizapi/ui/widgets/custom_input.dart';
import 'package:zapizapi/ui/widgets/custom_text_button.dart';
import 'package:zapizapi/utils/routes_enum.dart';

/// Tela de login
class LoginScreen extends StatefulWidget {
  /// Construtor da classe [LoginScreen]
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  /// Controlador do campo de email
  final TextEditingController emailController = TextEditingController();

  /// Controlador do campo de senha
  final TextEditingController passwordController = TextEditingController();

  /// Estado de visibilidade da senha
  bool _obscurePassword = true;

  @override
  void dispose() {
    emailController.dispose();
    passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: LayoutBuilder(
          builder: (context, constraints) {
            return SingleChildScrollView(
              child: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: SizedBox(
                    width: constraints.maxWidth > 768
                        ? 768
                        : constraints.maxWidth,
                    child: Column(
                      children: [
                        SizedBox(
                          height: 280,
                          child: Image.asset(
                            'assets/lottie/arty_chat_20251118122943.gif',
                            fit: BoxFit.contain,
                          ),
                        ),
                        const SizedBox(height: 18),
                        const SizedBox(
                          width: double.infinity,
                          child: Text('Login', style: TextStyle(fontSize: 20)),
                        ),
                        const SizedBox(height: 18),
                        CustomInput(
                          hint: 'Digite seu email',
                          label: 'Email',
                          controller: emailController,
                        ),
                        const SizedBox(height: 18),
                        CustomInput(
                          hint: 'Digite sua senha',
                          label: 'Senha',
                          controller: passwordController,
                          obsecureText: _obscurePassword,
                          suffixIcon: IconButton(
                            onPressed: () {
                              setState(() {
                                _obscurePassword = !_obscurePassword;
                              });
                            },
                            icon: Icon(
                              _obscurePassword
                                  ? Icons.visibility
                                  : Icons.visibility_off,
                            ),
                          ),
                        ),
                        Align(
                          alignment: AlignmentGeometry.centerRight,
                          child: CustomTextButton(
                            buttonText: 'Esqueci minha senha',
                            buttonAction: () async {
                              await Navigator.pushNamed(
                                context,
                                RoutesEnum.forgotPassword.route,
                              );
                            },
                          ),
                        ),
                        const SizedBox(height: 18),
                        CustomButton(
                          buttonText: 'Entrar',
                          backgroundColor: Theme.of(context).colorScheme.primary,
                          buttonAction: () async {
                            final navigator = Navigator.of(context);
                            final supabase = Supabase.instance.client;

                            try {
                              final response = await supabase.auth
                                  .signInWithPassword(
                                password: passwordController.text.trim(),
                                email: emailController.text.trim(),
                              );

                              if (response.user != null) {
                                // Sincroniza o token FCM com o Supabase
                                await NotificationService.instance
                                    .syncTokenWithSupabase(
                                  userId: response.user!.id,
                                );

                                await navigator.pushReplacementNamed(
                                  RoutesEnum.home.route,
                                );
                              } else {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text(
                                      'Não foi possível efetuar o login. Verifique suas credenciais.',
                                    ),
                                  ),
                                );
                              }
                            } on AuthException catch (e) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(e.message.isNotEmpty
                                      ? e.message
                                      : 'Login inválido. Verifique email e senha.'),
                                ),
                              );
                            } on SocketException {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text(
                                    'Falha de rede. Verifique sua conexão e tente novamente.',
                                  ),
                                ),
                              );
                            } catch (e) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text(
                                    'Ocorreu um erro inesperado ao fazer login.',
                                  ),
                                ),
                              );
                            }
                          },
                        ),
                        const SizedBox(height: 18),
                        CustomTextButton(
                          buttonText: 'Não tem uma conta? Cadastre-se',
                          buttonAction: () async {
                            await Navigator.pushNamed(
                              context,
                              RoutesEnum.register.route,
                            ); // Named route
                          },
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
