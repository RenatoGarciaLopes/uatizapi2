import 'dart:typed_data';

class E2EEDevice {
  E2EEDevice({
    required this.deviceId,
    required this.userId,
    required this.deviceName,
    required this.registrationId,
  });

  final String deviceId;
  final String userId;
  final String deviceName;
  final int registrationId;
}

class DeviceBundlePublic {
  DeviceBundlePublic({
    required this.deviceId,
    required this.registrationId,
    required this.identityKeyPublic,
    required this.signedPreKeyId,
    required this.signedPreKeyPublic,
    required this.signedPreKeySignature,
    required this.oneTimePreKeysRemaining,
  });

  final String deviceId;
  final int registrationId;
  final Uint8List identityKeyPublic;
  final int signedPreKeyId;
  final Uint8List signedPreKeyPublic;
  final Uint8List signedPreKeySignature;
  final int oneTimePreKeysRemaining;
}

class OneTimePreKeyPublic {
  OneTimePreKeyPublic({
    required this.preKeyId,
    required this.preKeyPublic,
  });

  final int preKeyId;
  final Uint8List preKeyPublic;
}

class SessionAddress {
  SessionAddress({
    required this.remoteUserId,
    required this.remoteDeviceId,
  });

  final String remoteUserId;
  final String remoteDeviceId;
}

class CiphertextEnvelope {
  CiphertextEnvelope({
    required this.isPreKeyMessage,
    required this.messageType,
    required this.ciphertext,
  });

  final bool isPreKeyMessage;
  final int messageType; // 1=text, 2=attachment, etc.
  final Uint8List ciphertext;
}


