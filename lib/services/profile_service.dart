import 'package:supabase_flutter/supabase_flutter.dart';

/// Exceção genérica para falhas no [ProfileService].
class ProfileServiceException implements Exception {

  /// Construtor padrão.
  ProfileServiceException(this.message, {this.cause});
  /// Mensagem amigável descrevendo o problema.
  final String message;

  /// Objeto original que ocasionou o erro.
  final Object? cause;

  @override
  String toString() => 'ProfileServiceException: $message';
}

/// Serviço responsável por operações relacionadas a perfis de usuários.
class ProfileService {
  /// Cria o serviço com o [SupabaseClient] opcional (facilita testes).
  ProfileService({SupabaseClient? client})
      : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  /// Obtém o `user_id` associado ao [email] informado.
  Future<String> getUserIdByEmail(String email) async {
    final sanitizedEmail = email.trim().toLowerCase();

    if (sanitizedEmail.isEmpty) {
      throw ProfileServiceException(
        'Informe um e-mail válido para localizar o usuário.',
      );
    }

    try {
      final rawResponse = await _client
          .from('profiles')
          .select('id')
          .eq('email', sanitizedEmail)
          .maybeSingle();

      final response = rawResponse == null
          ? null
          : Map<String, dynamic>.from(rawResponse);

      if (response == null) {
        throw ProfileServiceException(
          'Nenhum usuário encontrado para o e-mail $sanitizedEmail.',
        );
      }

      final userId = response['id'];

      if (userId is! String || userId.isEmpty) {
        throw ProfileServiceException(
          'Resposta inválida ao buscar o usuário pelo e-mail informado.',
          cause: response,
        );
      }

      return userId;
    } on PostgrestException catch (error) {
      throw ProfileServiceException(
        'Não foi possível buscar o usuário pelo e-mail.',
        cause: error,
      );
    } catch (error) {
      throw ProfileServiceException(
        'Ocorreu um erro inesperado ao buscar o usuário pelo e-mail.',
        cause: error,
      );
    }
  }
}

