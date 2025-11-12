import 'package:zapizapi/repositories/profile_repository.dart';
import 'package:zapizapi/services/profile_service.dart';

/// Implementação padrão de [ProfileRepository].
class ProfileRepositoryImplementation implements ProfileRepository {
  /// Construtor com injeção do [ProfileService].
  ProfileRepositoryImplementation({required this.profileService});

  /// Serviço responsável por falar com o Supabase.
  final ProfileService profileService;

  @override
  Future<String> getUserIdByEmail(String email) {
    return profileService.getUserIdByEmail(email);
  }
}






