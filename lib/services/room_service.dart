import 'package:supabase_flutter/supabase_flutter.dart';

/// Representa uma falha ao criar ou gerenciar salas de conversa.
class RoomServiceException implements Exception {

  /// Construtor padrão.
  RoomServiceException(this.message, {this.cause});
  /// Mensagem de erro amigável.
  final String message;

  /// Objeto original que ocasionou o erro.
  final Object? cause;

  @override
  String toString() => 'RoomServiceException: $message';
}

/// Serviço responsável por orquestrar a criação de salas e grupos via Supabase.
class RoomService {
  /// Cria o serviço com um [SupabaseClient] opcional (útil para testes).
  RoomService({SupabaseClient? client})
      : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  /// Nome do RPC responsável por criar salas diretas.
  static const String _createDirectRoomFn = 'create_direct_room';

  /// Nome do RPC responsável por criar salas em grupo.
  static const String _createGroupRoomFn = 'create_group_room';

  /// Cria (ou reutiliza) uma sala direta entre o usuário autenticado e [targetUserId].
  ///
  /// Retorna o `room_id` gerado pelo Supabase.
  Future<String> createDirectRoom(String targetUserId) async {
    if (targetUserId.isEmpty) {
      throw RoomServiceException(
        'O identificador do usuário alvo não pode ser vazio.',
      );
    }

    try {
      final response = await _client.rpc<dynamic>(
        _createDirectRoomFn,
        params: {'target_user_id': targetUserId},
      );

      return _extractRoomId(response);
    } on PostgrestException catch (error) {
      throw RoomServiceException(
        'Não foi possível criar a conversa direta.',
        cause: error,
      );
    } catch (error) {
      throw RoomServiceException(
        'Ocorreu um erro inesperado ao criar a conversa direta.',
        cause: error,
      );
    }
  }

  /// Cria uma sala de grupo com [name] e a lista de membros [memberIds].
  ///
  /// Retorna o `room_id` gerado pelo Supabase.
  Future<String> createGroupRoom({
    required String name,
    required List<String> memberIds,
    required bool isSearchable,
  }) async {
    final sanitizedName = name.trim();
    final sanitizedMembers =
        memberIds.where((member) => member.trim().isNotEmpty).toList();

    if (sanitizedName.isEmpty) {
      throw RoomServiceException(
        'O nome do grupo deve ser informado.',
      );
    }

    if (sanitizedMembers.isEmpty) {
      throw RoomServiceException(
        'Informe ao menos um membro para o grupo.',
      );
    }

    try {
      final response = await _client.rpc<dynamic>(
        _createGroupRoomFn,
        params: {
          'group_name': sanitizedName,
          'member_ids': sanitizedMembers,
          'is_searchable': isSearchable,
        },
      );

      return _extractRoomId(response);
    } on PostgrestException catch (error) {
      throw RoomServiceException(
        'Não foi possível criar o grupo.',
        cause: error,
      );
    } catch (error) {
      throw RoomServiceException(
        'Ocorreu um erro inesperado ao criar o grupo.',
        cause: error,
      );
    }
  }

  String _extractRoomId(dynamic response) {
    if (response is String && response.isNotEmpty) {
      return response;
    }

    if (response is Map<String, dynamic>) {
      final roomId = response['room_id'] ?? response['id'];

      if (roomId is String && roomId.isNotEmpty) {
        return roomId;
      }
    }

    throw RoomServiceException(
      'Resposta inválida do Supabase ao criar a sala.',
      cause: response,
    );
  }
}

