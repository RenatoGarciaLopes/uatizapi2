import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'package:zapizapi/ui/features/register/resgister_view_model.dart';
import 'package:zapizapi/ui/widgets/custom_button.dart';
import 'package:zapizapi/ui/widgets/custom_input.dart';
import 'package:zapizapi/ui/widgets/custom_text_button.dart';

/// Tela de registro de novos usuários
class RegisterScreen extends StatefulWidget {
  /// Construtor da classe [RegisterScreen]
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final RegisterViewModel viewModel = RegisterViewModel();

  @override
  void initState() {
    viewModel.initToast(context);
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SingleChildScrollView(
        child: Center(
          child: LayoutBuilder(
            builder: (context, constraints) {
              return SafeArea(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: SizedBox(
                    width: constraints.maxWidth > 768
                        ? 768
                        : constraints.maxWidth,
                    child: FormWidget(viewModel: viewModel),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

/// Widget do formulário de registro
class FormWidget extends StatefulWidget {
  /// Construtor da classe [FormWidget]
  const FormWidget({required this.viewModel, super.key});

  /// ViewModel associado ao formulário
  final RegisterViewModel viewModel;

  @override
  State<FormWidget> createState() => _FormWidgetState();
}

class _FormWidgetState extends State<FormWidget> {
  late final VideoPlayerController _videoController;
  bool _isVideoInitialized = false;

  @override
  void initState() {
    super.initState();

    _videoController = VideoPlayerController.asset(
      'assets/lottie/arty_chat_20251118123035.webm',
    )
      ..setLooping(true)
      ..setVolume(0)
      ..initialize().then((_) {
        if (!mounted) return;
        setState(() {
          _isVideoInitialized = true;
        });
        _videoController.play();
      });
  }

  @override
  void dispose() {
    _videoController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Form(
      key: widget.viewModel.formKey,
      child: Column(
        spacing: 4,
        children: [
          SizedBox(
            height: 280,
            child: _isVideoInitialized
                ? AspectRatio(
                    aspectRatio: _videoController.value.aspectRatio,
                    child: VideoPlayer(_videoController),
                  )
                : const Center(
                    child: CircularProgressIndicator(),
                  ),
          ),
          const SizedBox(
            width: double.infinity,
            child: Text('Registro', style: TextStyle(fontSize: 20)),
          ),
          CustomInput(
            hint: 'Digite seu email',
            label: 'Email',
            controller: widget.viewModel.emailController,
            validator: (value) => widget.viewModel.emailValidator(value),
          ),
          CustomInput(
            hint: 'Digite seu nome completo',
            label: 'Nome',
            controller: widget.viewModel.fullNameController,
            validator: (value) => widget.viewModel.fullNameValidator(value),
          ),
          CustomInput(
            obsecureText: true,
            hint: 'Digite sua senha',
            label: 'Senha',
            controller: widget.viewModel.passwordController,
            validator: (value) => widget.viewModel.passwordValidator(value),
          ),
          CustomInput(
            obsecureText: true,
            hint: 'Confirme sua senha',
            label: 'Confirmação da senha',
            controller: widget.viewModel.passwordConfirmationController,
            validator: (value) =>
                widget.viewModel.passwordConfirmationValidator(value),
          ),
          CustomButton(
            icon: widget.viewModel.isLoading ? Icons.hourglass_empty : null,
            buttonText: 'Registrar',
            backgroundColor: Theme.of(context).colorScheme.primary,
            buttonAction: () async =>
                widget.viewModel.registerButtonAction(context),
          ),
          CustomTextButton(
            icon: Icons.login,
            buttonText: 'Já tem uma conta? Faça login',
            buttonAction: () => widget.viewModel.navigateToLogin(
              Navigator.of(context),
            ),
          ),
        ],
      ),
    );
  }
}
