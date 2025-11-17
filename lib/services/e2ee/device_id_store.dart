import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:uuid/uuid.dart';

class DeviceIdStore {
  DeviceIdStore({FlutterSecureStorage? secureStorage})
      : _secureStorage = secureStorage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _secureStorage;
  static const _kDeviceId = 'e2ee.device_id';
  static const _kServerDeviceId = 'e2ee.server_device_id';

  Future<String> getOrCreateDeviceId() async {
    final existing = await _secureStorage.read(key: _kDeviceId);
    if (existing != null && existing.isNotEmpty) {
      return existing;
    }
    final id = const Uuid().v4();
    await _secureStorage.write(key: _kDeviceId, value: id);
    return id;
  }

  Future<void> saveServerDeviceId(String deviceId) async {
    await _secureStorage.write(key: _kServerDeviceId, value: deviceId);
  }

  Future<String?> getServerDeviceId() => _secureStorage.read(key: _kServerDeviceId);
}



