import 'dart:convert';
import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import 'signal_engine.dart';
import 'signal_types.dart';
import 'supabase_e2ee_repository.dart';
import 'device_id_store.dart';

class E2EEService {
  E2EEService({
    required SupabaseClient supabase,
    required SignalEngine signalEngine,
  })  : _supabase = supabase,
        _repo = SupabaseE2EERepository(supabase),
        _engine = signalEngine;

  final SupabaseClient _supabase;
  final SupabaseE2EERepository _repo;
  final SignalEngine _engine;

  String get _myUserId => _supabase.auth.currentUser!.id;

  Future<E2EEDevice> initializeDevice({required String deviceName}) async {
    // Inicializa engine (usa o deviceId depois de criar no servidor)
    await _engine.initializeIfNeeded(myUserId: _myUserId, myDeviceId: 'pending');
    final device = await _engine.registerLocalDevice(myUserId: _myUserId, deviceName: deviceName);
    // Cria (ou obtém) o device no servidor e usa o device_id de lá
    final created = await _repo.createOrGetDevice(
      deviceName: deviceName,
      registrationId: device.registrationId,
    );
    final bundle = await _engine.getPublicBundle();
    // Atualiza bundle e publica prekeys
    // Publica bundle e prekeys (idempotente)
    final hasPreKeys = await _repo.hasAnyAvailablePreKeys(created.deviceId);
    if (!hasPreKeys) {
      final prekeys = await _engine.generateOneTimePreKeys(startId: 1, count: 100);
      await _repo.uploadOneTimePreKeys(deviceId: created.deviceId, prekeys: prekeys);
      await _repo.upsertDeviceBundle(
        deviceId: created.deviceId,
        identityKeyPublic: bundle.$1,
        signedPreKeyId: bundle.$2,
        signedPreKeyPublic: bundle.$3,
        signedPreKeySignature: bundle.$4,
        oneTimePreKeysRemaining: prekeys.length,
      );
    } else {
      await _repo.upsertDeviceBundle(
        deviceId: created.deviceId,
        identityKeyPublic: bundle.$1,
        signedPreKeyId: bundle.$2,
        signedPreKeyPublic: bundle.$3,
        signedPreKeySignature: bundle.$4,
        oneTimePreKeysRemaining: 0,
      );
    }
    // Atualiza engine com deviceId real (para endereçamento)
    await _engine.initializeIfNeeded(myUserId: _myUserId, myDeviceId: created.deviceId);
    // Persiste localmente para reuso
    await DeviceIdStore().saveServerDeviceId(created.deviceId);
    return created;
  }

  Future<void> initiateSessionX3DH({
    required String myDeviceId,
    required String remoteUserId,
    required String remoteDeviceId,
  }) async {
    final bundle = await _repo.getBundleForDevice(remoteDeviceId);
    if (bundle == null) {
      throw StateError('Bundle inexistente para device remoto: $remoteDeviceId');
    }
    final reserved = await _repo.reserveOneTimePreKey(remoteDeviceId);
    final address = SessionAddress(remoteUserId: remoteUserId, remoteDeviceId: remoteDeviceId);
    await _engine.buildSessionWithX3DH(
      address: address,
      theirRegistrationId: bundle.registrationId,
      theirIdentityKeyPublic: bundle.identityKeyPublic,
      theirSignedPreKeyId: bundle.signedPreKeyId,
      theirSignedPreKeyPublic: bundle.signedPreKeyPublic,
      theirSignedPreKeySignature: bundle.signedPreKeySignature,
      theirOneTimePreKeyId: reserved?.preKeyId,
      theirOneTimePreKeyPublic: reserved?.preKeyPublic,
    );
  }

  Future<void> sendEncryptedText({
    required String roomId,
    required String myDeviceId,
    required String recipientUserId,
    required String recipientDeviceId,
    required String messageText,
  }) async {
    final address = SessionAddress(remoteUserId: recipientUserId, remoteDeviceId: recipientDeviceId);
    final payload = Uint8List.fromList(messageText.codeUnits);
    final result = await _engine.encrypt(address: address, plaintext: payload);
    await _repo.sendCiphertextMessage(
      roomId: roomId,
      senderDeviceId: myDeviceId,
      recipientUserId: recipientUserId,
      recipientDeviceId: recipientDeviceId,
      isPreKey: result.$1,
      msgType: 1,
      ciphertext: result.$2,
    );
  }

  Future<String> decryptToText({
    required String senderUserId,
    required String senderDeviceId,
    required Uint8List ciphertext,
    required bool isPreKey,
  }) async {
    final address = SessionAddress(remoteUserId: senderUserId, remoteDeviceId: senderDeviceId);
    final plain = await _engine.decrypt(address: address, ciphertext: ciphertext, isPreKeyMessage: isPreKey);
    return utf8.decode(plain);
  }
}


