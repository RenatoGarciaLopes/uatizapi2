import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import 'signal_types.dart';

class SupabaseE2EERepository {
  SupabaseE2EERepository(this._client);

  final SupabaseClient _client;

  Future<E2EEDevice> createOrGetDevice({
    required String deviceName,
    required int registrationId,
  }) async {
    final userId = _client.auth.currentUser!.id;
    final existing = await _client.from('e2ee_devices').select().eq('user_id', userId).eq('device_name', deviceName).maybeSingle();
    if (existing != null) {
      return E2EEDevice(
        deviceId: (existing as Map<String, dynamic>)['device_id'] as String,
        userId: userId,
        deviceName: deviceName,
        registrationId: existing['registration_id'] as int,
      );
    }
    final inserted = await _client.from('e2ee_devices').insert({
      'user_id': userId,
      'device_name': deviceName,
      'registration_id': registrationId,
    }).select().single() as Map<String, dynamic>;
    return E2EEDevice(
      deviceId: inserted['device_id'] as String,
      userId: userId,
      deviceName: deviceName,
      registrationId: inserted['registration_id'] as int,
    );
  }

  Future<void> upsertDeviceBundle({
    required String deviceId,
    required Uint8List identityKeyPublic,
    required int signedPreKeyId,
    required Uint8List signedPreKeyPublic,
    required Uint8List signedPreKeySignature,
    required int oneTimePreKeysRemaining,
  }) async {
    await _client.from('e2ee_device_bundles').upsert({
      'device_id': deviceId,
      'identity_key_public': identityKeyPublic,
      'signed_prekey_id': signedPreKeyId,
      'signed_prekey_public': signedPreKeyPublic,
      'signed_prekey_signature': signedPreKeySignature,
      'one_time_prekeys_remaining': oneTimePreKeysRemaining,
    });
  }

  Future<void> uploadOneTimePreKeys({
    required String deviceId,
    required List<(int id, Uint8List publicKey)> prekeys,
  }) async {
    if (prekeys.isEmpty) return;
    final rows = prekeys
        .map((e) => {
              'device_id': deviceId,
              'prekey_id': e.$1,
              'prekey_public': e.$2,
            })
        .toList(growable: false);
    // Evita violar unique constraint ao rodar bootstrap mais de uma vez
    try {
      await _client.from('e2ee_onetime_prekeys').insert(rows);
    } on PostgrestException catch (e) {
      // 23505 = unique_violation: ignora se já existem
      if (e.code != '23505') rethrow;
    }
  }

  Future<DeviceBundlePublic?> getBundleForDevice(String deviceId) async {
    // Busca registration_id do device
    final deviceRow = await _client.from('e2ee_devices').select().eq('device_id', deviceId).maybeSingle();
    if (deviceRow == null) return null;
    final row = await _client.from('e2ee_device_bundles').select().eq('device_id', deviceId).maybeSingle();
    if (row == null) return null;
    return DeviceBundlePublic(
      deviceId: deviceId,
      registrationId: (deviceRow as Map<String, dynamic>)['registration_id'] as int,
      identityKeyPublic: Uint8List.fromList(((row as Map<String, dynamic>)['identity_key_public'] as List).cast<int>()),
      signedPreKeyId: row['signed_prekey_id'] as int,
      signedPreKeyPublic: Uint8List.fromList((row['signed_prekey_public'] as List).cast<int>()),
      signedPreKeySignature: Uint8List.fromList((row['signed_prekey_signature'] as List).cast<int>()),
      oneTimePreKeysRemaining: row['one_time_prekeys_remaining'] as int,
    );
  }

  Future<bool> hasAnyAvailablePreKeys(String deviceId) async {
    final resp = await _client
        .from('e2ee_onetime_prekeys')
        .select('id')
        .eq('device_id', deviceId)
        .eq('consumed', false)
        .limit(1);
    final list = (resp as List?)?.whereType<Map<String, dynamic>>().toList() ?? const [];
    return list.isNotEmpty;
  }

  Future<OneTimePreKeyPublic?> reserveOneTimePreKey(String deviceId) async {
    final resp = await _client.rpc('reserve_onetime_prekey', params: {'target_device': deviceId});
    if (resp == null) return null;
    final list = (resp as List).cast<dynamic>();
    if (list.isEmpty) return null;
    final row = list.first as Map<String, dynamic>;
    return OneTimePreKeyPublic(
      preKeyId: row['prekey_id'] as int,
      preKeyPublic: Uint8List.fromList((row['prekey_public'] as List).cast<int>()),
    );
  }

  Future<void> sendCiphertextMessage({
    required String roomId,
    required String senderDeviceId,
    required String recipientUserId,
    required String recipientDeviceId,
    required bool isPreKey,
    required int msgType,
    required Uint8List ciphertext,
  }) {
    final userId = _client.auth.currentUser!.id;
    return _client.from('e2ee_messages').insert({
      'room_id': roomId,
      'sender_user_id': userId,
      'sender_device_id': senderDeviceId,
      'recipient_user_id': recipientUserId,
      'recipient_device_id': recipientDeviceId,
      'is_prekey': isPreKey,
      'msg_type': msgType,
      'ciphertext': ciphertext,
    });
  }
}


