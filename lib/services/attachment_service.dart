import 'package:file_picker/file_picker.dart';
import 'package:mime/mime.dart';
import 'package:path/path.dart' as p;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

class AttachmentUpload {
  AttachmentUpload({
    required this.url,
    required this.storagePath,
    required this.fileName,
    required this.sizeBytes,
    required this.mimeType,
    required this.isImage,
  });

  final String url;
  final String storagePath;
  final String fileName;
  final int sizeBytes;
  final String mimeType;
  final bool isImage;
}

class AttachmentServiceException implements Exception {
  AttachmentServiceException(this.message, {this.cause});
  final String message;
  final Object? cause;

  @override
  String toString() => 'AttachmentServiceException: $message';
}

class AttachmentService {
  AttachmentService({SupabaseClient? client})
      : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  static const int _maxBytes = 20 * 1024 * 1024; // 20 MB
  static const String _bucket = 'attachments';

  Future<AttachmentUpload?> pickAndUpload(String roomId) async {
    final result = await FilePicker.platform.pickFiles(
      // Web não possui `path`, então precisamos dos bytes. Para 20MB é aceitável.
      withData: true,
    );
    if (result == null) return null;

    final picked = result.files.single;
    final bytes = picked.bytes;
    if (bytes == null) {
      throw AttachmentServiceException(
        'Não foi possível ler os bytes do arquivo selecionado.',
      );
    }

    final fileSize = picked.size;
    if (fileSize > _maxBytes) {
      throw AttachmentServiceException('Arquivo excede 20 MB.');
    }

    final mime =
        lookupMimeType(picked.name, headerBytes: bytes.take(12).toList()) ??
            'application/octet-stream';
    final ext = p.extension(picked.name);
    final generatedName = '${const Uuid().v4()}$ext';
    final storagePath = 'rooms/$roomId/$generatedName';

    await _client.storage.from(_bucket).uploadBinary(
          storagePath,
          bytes,
          fileOptions: FileOptions(
            contentType: mime,
            cacheControl: 'public, max-age=31536000, immutable',
          ),
        );

    // URL pública (CDN) — certifique-se de que o bucket está público.
    final publicUrl =
        _client.storage.from(_bucket).getPublicUrl(storagePath);

    return AttachmentUpload(
      url: publicUrl,
      storagePath: storagePath,
      fileName: picked.name,
      sizeBytes: fileSize,
      mimeType: mime,
      isImage: mime.startsWith('image/'),
    );
  }
}


