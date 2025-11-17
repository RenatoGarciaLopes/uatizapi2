import 'package:flutter/material.dart';

/// Campo de entrada customizado reutilizável
class CustomInput extends StatelessWidget {
  /// Construtor da classe [CustomInput]
  const CustomInput({
    required this.label,
    required this.hint,
    required this.controller,
    super.key,
    this.validator,
    this.obsecureText = false,
    this.enabled = true,
    this.focusNode,
    this.textInputAction,
    this.keyboardType,
    this.onFieldSubmitted,
    this.minLines = 1,
    this.maxLines = 1,
    this.suffixIcon,
  });

  /// Construtor da classe [CustomInput]
  final String label;

  /// Texto de dica exibido no campo
  final String hint;

  /// Controlador do campo de entrada
  final TextEditingController controller;

  /// Função de validação do campo
  final String? Function(String?)? validator;

  /// Indica se o texto deve ser ocultado (para senhas)
  final bool obsecureText;

  /// Indica se o campo está habilitado
  final bool enabled;

  /// Foco externo para permitir gerenciamento customizado
  final FocusNode? focusNode;

  /// Define a ação do teclado virtual
  final TextInputAction? textInputAction;

  /// Define o tipo de teclado desejado
  final TextInputType? keyboardType;

  /// Callback disparado ao submeter o campo
  final ValueChanged<String>? onFieldSubmitted;

  /// Número mínimo de linhas exibidas
  final int minLines;

  /// Número máximo de linhas exibidas
  final int maxLines;

  /// Ícone exibido ao final do campo (ex.: olhinho de senha)
  final Widget? suffixIcon;

  @override
  Widget build(BuildContext context) {
    final effectiveMinLines = minLines < 1 ? 1 : minLines;
    final effectiveMaxLines =
        maxLines < effectiveMinLines ? effectiveMinLines : maxLines;
    final isMultiLine = effectiveMaxLines > 1;
    final resolvedTextInputAction = textInputAction ??
        (isMultiLine ? TextInputAction.newline : TextInputAction.done);
    final resolvedKeyboardType = keyboardType ??
        (isMultiLine ? TextInputType.multiline : TextInputType.text);
    final fieldHeight =
        isMultiLine ? 60 + (effectiveMaxLines - 1) * 28.0 : 68.0;

    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: controller,
      builder: (context, value, child) {
        final theme = Theme.of(context);
        final scheme = theme.colorScheme;
        final isDarkTheme = theme.brightness == Brightness.dark;
        final baseLabelColor = isDarkTheme
            ? scheme.onSurface.withOpacity(0.85)
            : scheme.onSurfaceVariant;
        final hintColor = scheme.onSurfaceVariant.withOpacity(
          isDarkTheme ? 0.7 : 0.6,
        );
        // debug: print controller empty state
        // print('[DEBUG] controller: ${value.text.isEmpty}');
        return SizedBox(
          height: fieldHeight,
          child: TextFormField(
            enabled: enabled,
            obscureText: obsecureText,
            validator: validator,
            controller: controller,
            focusNode: focusNode,
            textInputAction: resolvedTextInputAction,
            keyboardType: resolvedKeyboardType,
            minLines: effectiveMinLines,
            maxLines: effectiveMaxLines,
            onFieldSubmitted: onFieldSubmitted,

            decoration: InputDecoration(
              // border: OutlineInputBorder(
              //   borderRadius: BorderRadius.circular(8.0),
              //   borderSide: BorderSide(color: Colors.red, width: 2.0),
              // ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(
                  color:
                      value.text.isEmpty ? scheme.outlineVariant : scheme.primary,
                  width: 2,
                ),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: scheme.primary, width: 2.5),
              ),
              errorBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: Colors.red, width: 2.5),
              ),
              focusedErrorBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: Colors.red, width: 2.5),
              ),
              labelText: label.isEmpty ? null : label,
              labelStyle: TextStyle(color: baseLabelColor),
              floatingLabelStyle: TextStyle(
                color: scheme.primary,
                fontWeight: FontWeight.w600,
              ),
              hintText: hint,
              hintStyle: TextStyle(color: hintColor),
              fillColor: isDarkTheme
                  ? scheme.surfaceContainerLowest
                  : Colors.white,
              filled: true,
              suffixIcon: suffixIcon,
            ),
          ),
        );
      },
    );
  }
}
