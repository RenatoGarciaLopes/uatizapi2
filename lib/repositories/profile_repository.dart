/// Contrato para operações de leitura de perfis de usuário.
abstract class ProfileRepository {
  /// Retorna o identificador único de um usuário a partir do e-mail informado.
  Future<String> getUserIdByEmail(String email);
}






