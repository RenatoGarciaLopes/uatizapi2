import 'package:file_picker/file_picker.dart';
import 'package:mime/mime.dart';
import 'package:path/path.dart' as p;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

class AvatarUpload {
  AvatarUpload({
    required this.url,
    required this.storagePath,
    required this.fileName,
    required this.sizeBytes,
    required this.mimeType,
  });

  final String url;
  final String storagePath;
  final String fileName;
  final int sizeBytes;
  final String mimeType;
}

class AvatarServiceException implements Exception {
  AvatarServiceException(this.message, {this.cause});
  final String message;
  final Object? cause;

  @override
  String toString() => 'AvatarServiceException: $message';
}

class AvatarService {
  AvatarService({SupabaseClient? client})
      : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  static const int _maxBytes = 10 * 1024 * 1024; // 10MB para avatar
  static const String _bucket = 'avatars';

  Future<AvatarUpload?> pickAndUploadAvatar({
    required String userId,
  }) async {
    final result = await FilePicker.platform.pickFiles(
      withData: true, // Necessário na Web
      type: FileType.image,
    );
    if (result == null) return null;

    final picked = result.files.single;
    final bytes = picked.bytes;
    if (bytes == null) {
      throw AvatarServiceException(
        'Não foi possível ler os bytes do arquivo selecionado.',
      );
    }

    final fileSize = picked.size;
    if (fileSize > _maxBytes) {
      throw AvatarServiceException('Imagem excede 10 MB.');
    }

    final mime =
        lookupMimeType(picked.name, headerBytes: bytes.take(12).toList()) ??
            'application/octet-stream';
    if (!mime.startsWith('image/')) {
      throw AvatarServiceException('Selecione um arquivo de imagem válido.');
    }

    final ext = p.extension(picked.name).toLowerCase();
    final fileName = '${const Uuid().v4()}$ext';
    final storagePath = 'profiles/$userId/$fileName';

    await _client.storage.from(_bucket).uploadBinary(
          storagePath,
          bytes,
          fileOptions: FileOptions(
            contentType: mime,
            cacheControl: 'public, max-age=31536000, immutable',
          ),
        );

    final publicUrl = _client.storage.from(_bucket).getPublicUrl(storagePath);

    return AvatarUpload(
      url: publicUrl,
      storagePath: storagePath,
      fileName: picked.name,
      sizeBytes: fileSize,
      mimeType: mime,
    );
  }

  /// Faz upload de uma imagem de avatar para um grupo (sala).
  ///
  /// Armazena o arquivo no bucket de avatars em `groups/<roomId>/`.
  Future<AvatarUpload?> pickAndUploadGroupAvatar({
    required String roomId,
  }) async {
    final result = await FilePicker.platform.pickFiles(
      withData: true,
      type: FileType.image,
    );
    if (result == null) return null;

    final picked = result.files.single;
    final bytes = picked.bytes;
    if (bytes == null) {
      throw AvatarServiceException(
        'Não foi possível ler os bytes do arquivo selecionado.',
      );
    }

    final fileSize = picked.size;
    if (fileSize > _maxBytes) {
      throw AvatarServiceException('Imagem excede 10 MB.');
    }

    final mime =
        lookupMimeType(picked.name, headerBytes: bytes.take(12).toList()) ??
            'application/octet-stream';
    if (!mime.startsWith('image/')) {
      throw AvatarServiceException('Selecione um arquivo de imagem válido.');
    }

    final ext = p.extension(picked.name).toLowerCase();
    final fileName = '${const Uuid().v4()}$ext';
    final storagePath = 'groups/$roomId/$fileName';

    await _client.storage.from(_bucket).uploadBinary(
          storagePath,
          bytes,
          fileOptions: FileOptions(
            contentType: mime,
            cacheControl: 'public, max-age=31536000, immutable',
          ),
        );

    final publicUrl = _client.storage.from(_bucket).getPublicUrl(storagePath);

    return AvatarUpload(
      url: publicUrl,
      storagePath: storagePath,
      fileName: picked.name,
      sizeBytes: fileSize,
      mimeType: mime,
    );
  }
}


