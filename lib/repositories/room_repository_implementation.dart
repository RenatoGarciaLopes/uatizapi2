import 'package:zapizapi/repositories/profile_repository.dart';
import 'package:zapizapi/repositories/room_repository.dart';
import 'package:zapizapi/services/room_service.dart';

/// Implementação padrão do [RoomRepository], delegando chamadas para o serviço.
class RoomRepositoryImplementation implements RoomRepository {
  /// Cria uma nova instância com dependências injetadas.
  RoomRepositoryImplementation({
    required this.roomService,
    required this.profileRepository,
  });

  /// Serviço responsável por falar com o Supabase.
  final RoomService roomService;

  /// Repositório de perfis responsável por buscar usuários.
  final ProfileRepository profileRepository;

  @override
  Future<String> createDirectRoom(String targetUserId) {
    return roomService.createDirectRoom(targetUserId);
  }

  @override
  Future<String> createDirectRoomByEmail(String email) async {
    final targetUserId = await profileRepository.getUserIdByEmail(email);
    return roomService.createDirectRoom(targetUserId);
  }

  @override
  Future<String> createGroupRoom({
    required String name,
    required List<String> memberIds,
    required bool isSearchable,
  }) {
    return roomService.createGroupRoom(
      name: name,
      memberIds: memberIds,
      isSearchable: isSearchable,
    );
  }
}

