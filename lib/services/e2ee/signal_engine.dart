import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:libsignal_protocol_dart/libsignal_protocol_dart.dart' as signal;
import 'package:libsignal_protocol_dart/libsignal_protocol_dart.dart'
    show
        generateIdentityKeyPair,
        generateRegistrationId,
        generatePreKeys,
        generateSignedPreKey;

import 'signal_types.dart';

/// Abstração do motor Signal (X3DH + Double Ratchet).
/// Implementações devem persistir chaves localmente, nunca no servidor.
abstract class SignalEngine {
  Future<void> initializeIfNeeded({required String myUserId, required String myDeviceId});

  Future<E2EEDevice> registerLocalDevice({
    required String myUserId,
    required String deviceName,
  });

  Future<(
    Uint8List identityKeyPublic,
    int signedPreKeyId,
    Uint8List signedPreKeyPublic,
    Uint8List signedPreKeySignature
  )> getPublicBundle();

  Future<List<(int id, Uint8List publicKey)>> generateOneTimePreKeys({
    required int startId,
    required int count,
  });

  Future<void> buildSessionWithX3DH({
    required SessionAddress address,
    required int theirRegistrationId,
    required Uint8List theirIdentityKeyPublic,
    required int theirSignedPreKeyId,
    required Uint8List theirSignedPreKeyPublic,
    required Uint8List theirSignedPreKeySignature,
    int? theirOneTimePreKeyId,
    Uint8List? theirOneTimePreKeyPublic,
  });

  Future<(bool isPreKey, Uint8List ciphertext)> encrypt({
    required SessionAddress address,
    required Uint8List plaintext,
  });

  Future<Uint8List> decrypt({
    required SessionAddress address,
    required Uint8List ciphertext,
    required bool isPreKeyMessage,
  });
}

/// Implementação baseada em libsignal_protocol_dart.
/// Nota: esta implementação é mínima; persiste pares de chaves no SecureStorage.
/// Para produção, considere mover sessões para um storage local (ex.: sqlite/hive) com criptografia.
class LibSignalEngine implements SignalEngine {
  LibSignalEngine({FlutterSecureStorage? secureStorage})
      : _secureStorage = secureStorage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _secureStorage;

  late String _myUserId;
  late String _myDeviceId;

  static const _kIdentityKeyPair = 'e2ee.identity_keypair';
  static const _kRegistrationId = 'e2ee.registration_id';
  static const _kSignedPreKey = 'e2ee.signed_prekey';
  static const _kPreKeys = 'e2ee.prekeys'; // não usado por enquanto

  bool _initialized = false;
  // Stores em memória (podem ser trocados por stores persistentes depois)
  late final signal.SessionStore _sessionStore;
  late final signal.PreKeyStore _preKeyStore;
  late final signal.SignedPreKeyStore _signedPreKeyStore;
  late final signal.IdentityKeyStore _identityStore;
  signal.IdentityKeyPair? _identityKeyPair;
  int? _registrationId;

  @override
  Future<void> initializeIfNeeded({required String myUserId, required String myDeviceId}) async {
    if (!_initialized) {
      _myUserId = myUserId;
      _myDeviceId = myDeviceId;
      await _loadOrCreateStore();
      _initialized = true;
      return;
    }
    // Re-inicializações são permitidas para atualizar apenas o deviceId.
    _myDeviceId = myDeviceId;
  }

  Future<void> _loadOrCreateStore() async {
    // Carrega ou cria identidade, registrationId, signedPreKey e prekeys
    final regStr = await _secureStorage.read(key: _kRegistrationId);
    if (regStr == null) {
      _registrationId = generateRegistrationId(true);
      await _secureStorage.write(key: _kRegistrationId, value: _registrationId.toString());
    } else {
      _registrationId = int.tryParse(regStr) ?? generateRegistrationId(true);
    }
    final idSer = await _secureStorage.read(key: _kIdentityKeyPair);
    if (idSer == null) {
      _identityKeyPair = await generateIdentityKeyPair();
      await _secureStorage.write(key: _kIdentityKeyPair, value: base64Encode(_identityKeyPair!.serialize()));
    } else {
      _identityKeyPair = signal.IdentityKeyPair.fromSerialized(base64Decode(idSer));
    }
    // Stores in-memory
    _sessionStore = signal.InMemorySessionStore();
    _preKeyStore = signal.InMemoryPreKeyStore();
    _signedPreKeyStore = signal.InMemorySignedPreKeyStore();
    _identityStore = signal.InMemoryIdentityKeyStore(_identityKeyPair!, _registrationId!);
  }

  int _computeDeviceInt(String deviceId) {
    final bytes = utf8.encode(deviceId);
    var hash = 0;
    for (final b in bytes) {
      hash = (hash * 31 + b) & 0x7fffffff;
    }
    // Mantém no intervalo típico e evita 0
    return 1 + (hash % 16380);
  }

  @override
  Future<E2EEDevice> registerLocalDevice({
    required String myUserId,
    required String deviceName,
  }) async {
    if (!_initialized) {
      throw StateError('LibSignalEngine not initialized');
    }
    // Gera/Carrega identidade + registrationId
    // Armazena no SecureStorage (privado).
    // Implementação simplificada: se não existir, cria; caso exista, reutiliza.
    // Observação: a persistência de sessões não está contemplada neste MVP.
    return E2EEDevice(
      deviceId: _myDeviceId,
      userId: myUserId,
      deviceName: deviceName,
      registrationId: _registrationId!,
    );
  }

  @override
  Future<(
    Uint8List identityKeyPublic,
    int signedPreKeyId,
    Uint8List signedPreKeyPublic,
    Uint8List signedPreKeySignature
  )> getPublicBundle() async {
    // Gera/atualiza SignedPreKey toda vez que publicar bundle (id fixo 1)
    final spk = await generateSignedPreKey(_identityKeyPair!, 1);
    await _signedPreKeyStore.storeSignedPreKey(spk.id, spk);
    final ikPub = _identityKeyPair!.getPublicKey().serialize();
    return (ikPub, spk.id, spk.getKeyPair().publicKey.serialize(), spk.signature);
  }

  @override
  Future<List<(int id, Uint8List publicKey)>> generateOneTimePreKeys({
    required int startId,
    required int count,
  }) async {
    final records = await generatePreKeys(startId, count);
    for (final r in records) {
      await _preKeyStore.storePreKey(r.id, r);
    }
    return records.map((r) => (r.id, r.getKeyPair().publicKey.serialize())).toList();
  }

  @override
  Future<void> buildSessionWithX3DH({
    required SessionAddress address,
    required int theirRegistrationId,
    required Uint8List theirIdentityKeyPublic,
    required int theirSignedPreKeyId,
    required Uint8List theirSignedPreKeyPublic,
    required Uint8List theirSignedPreKeySignature,
    int? theirOneTimePreKeyId,
    Uint8List? theirOneTimePreKeyPublic,
  }) async {
    final addr = signal.SignalProtocolAddress(address.remoteUserId, _computeDeviceInt(address.remoteDeviceId));
    final builder = signal.SessionBuilder(_sessionStore, _preKeyStore, _signedPreKeyStore, _identityStore, addr);
    final identityKey = signal.IdentityKey.fromBytes(theirIdentityKeyPublic, 0);
    final spkPub = signal.Curve.decodePoint(theirSignedPreKeyPublic, 0);
    final preKeyPub = theirOneTimePreKeyPublic != null ? signal.Curve.decodePoint(theirOneTimePreKeyPublic, 0) : null;
    final preKeyId = theirOneTimePreKeyId ?? 0;
    final bundle = signal.PreKeyBundle(
      theirRegistrationId,
      _computeDeviceInt(address.remoteDeviceId),
      preKeyPub != null ? preKeyId : 0,
      preKeyPub,
      theirSignedPreKeyId,
      spkPub,
      theirSignedPreKeySignature,
      identityKey,
    );
    await builder.processPreKeyBundle(bundle);
  }

  @override
  Future<(bool isPreKey, Uint8List ciphertext)> encrypt({
    required SessionAddress address,
    required Uint8List plaintext,
  }) async {
    final addr = signal.SignalProtocolAddress(address.remoteUserId, _computeDeviceInt(address.remoteDeviceId));
    final cipher = signal.SessionCipher(_sessionStore, _preKeyStore, _signedPreKeyStore, _identityStore, addr);
    final msg = await cipher.encrypt(plaintext);
    final isPreKey = msg.getType() == signal.CiphertextMessage.prekeyType;
    return (isPreKey, msg.serialize());
  }

  @override
  Future<Uint8List> decrypt({
    required SessionAddress address,
    required Uint8List ciphertext,
    required bool isPreKeyMessage,
  }) async {
    final addr = signal.SignalProtocolAddress(address.remoteUserId, _computeDeviceInt(address.remoteDeviceId));
    final cipher = signal.SessionCipher(_sessionStore, _preKeyStore, _signedPreKeyStore, _identityStore, addr);
    if (isPreKeyMessage) {
      final pre = signal.PreKeySignalMessage(ciphertext);
      return await cipher.decrypt(pre);
    }
    final sig = signal.SignalMessage.fromSerialized(ciphertext);
    return await cipher.decryptFromSignal(sig);
  }
}


