/// Contrato para operações relacionadas a salas de conversa.
abstract class RoomRepository {
  /// Cria (ou reutiliza) uma sala direta entre o usuário atual e o alvo.
  Future<String> createDirectRoom(String targetUserId);

  /// Cria (ou reutiliza) uma sala direta buscando o usuário alvo pelo e-mail.
  Future<String> createDirectRoomByEmail(String email);

  /// Cria uma sala de grupo com o nome, os membros e a visibilidade informados.
  Future<String> createGroupRoom({
    required String name,
    required List<String> memberIds,
    required bool isSearchable,
  });
}

