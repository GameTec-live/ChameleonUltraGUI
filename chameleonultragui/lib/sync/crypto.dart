import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as hashing;
import 'package:cryptography/cryptography.dart';

/// Cryptographic building blocks of the sync protocol (`sync/PROTOCOL.md`).
/// Servers never see anything but the outputs of [Keychain.seal],
/// [wrapKeychain] and [hashToken].

final _random = Random.secure();
final _x25519 = X25519();
final _aead = Xchacha20.poly1305Aead();
const _nonceLength = 24;
const _tagLength = 16;

Uint8List randomBytes(int length) =>
    Uint8List.fromList(List.generate(length, (_) => _random.nextInt(256)));

/// base64url without padding, the protocol's binary encoding.
String b64(List<int> bytes) => base64Url.encode(bytes).replaceAll('=', '');

Uint8List unb64(String text) => base64Url.decode(base64Url.normalize(text));

/// `hash(x)`: what servers store instead of bearer tokens.
String hashToken(String token) =>
    b64(hashing.sha256.convert(utf8.encode(token)).bytes);

Future<Uint8List> hkdf(
  List<int> ikm,
  String info,
  int length, {
  List<int> salt = const [],
}) async {
  final key = await Hkdf(
    hmac: Hmac.sha256(),
    outputLength: length,
  ).deriveKey(secretKey: SecretKey(ikm), nonce: salt, info: utf8.encode(info));
  return Uint8List.fromList(await key.extractBytes());
}

Future<Uint8List> hmacSha256(List<int> key, List<int> data) async =>
    Uint8List.fromList(
      (await Hmac.sha256().calculateMac(data, secretKey: SecretKey(key))).bytes,
    );

Uint8List _u32(int value) =>
    Uint8List(4)..buffer.asByteData().setUint32(0, value);

Uint8List _aad(String vaultId, String id, int epoch) =>
    Uint8List.fromList([...utf8.encode('$vaultId/$id'), ..._u32(epoch)]);

/// An X25519 identity (a device or the recovery member), from a 32 byte seed.
class Identity {
  final Uint8List seed;
  Identity(this.seed);
  Identity.random() : seed = randomBytes(32);

  Future<SimpleKeyPair> keyPair() => _x25519.newKeyPairFromSeed(seed);

  Future<Uint8List> publicKey() async =>
      Uint8List.fromList((await (await keyPair()).extractPublicKey()).bytes);
}

/// Everything derived from the recovery phrase entropy.
class RecoveryKeys {
  final String vaultId;
  final String token;
  final Identity identity;

  RecoveryKeys._(this.vaultId, this.token, this.identity);

  static Future<RecoveryKeys> derive(Uint8List entropy) async => RecoveryKeys._(
    b64(await hkdf(entropy, 'cu-sync/vault-id/v1', 16)),
    b64(await hkdf(entropy, 'cu-sync/recovery-auth/v1', 32)),
    Identity(await hkdf(entropy, 'cu-sync/recovery-kx/v1', 32)),
  );
}

/// The vault secrets shared by all members: a stable [keyId] for record key
/// obfuscation and one data key per epoch (old ones keep old blobs readable).
class Keychain {
  final Uint8List keyId;
  final int current;
  final Map<int, Uint8List> epochs;

  Keychain(this.keyId, this.current, this.epochs);

  Keychain.create()
    : keyId = randomBytes(32),
      current = 1,
      epochs = {1: randomBytes(32)};

  /// A copy with a fresh data key for the next epoch.
  Keychain rotated() =>
      Keychain(keyId, current + 1, {...epochs, current + 1: randomBytes(32)});

  factory Keychain.fromJson(Map<String, dynamic> json) => Keychain(
    unb64(json['keyId'] as String),
    json['current'] as int,
    (json['epochs'] as Map<String, dynamic>).map(
      (epoch, key) => MapEntry(int.parse(epoch), unb64(key as String)),
    ),
  );

  Map<String, Object> toJson() => {
    'keyId': b64(keyId),
    'current': current,
    'epochs': epochs.map((epoch, key) => MapEntry('$epoch', b64(key))),
  };

  /// The opaque server-side key of a record.
  Future<String> recordKey(String collection, String id) async =>
      b64(await hmacSha256(keyId, utf8.encode('$collection/$id')));

  /// `[0x01][u32 epoch][nonce][ciphertext+tag]` under the current epoch.
  Future<Uint8List> seal(
    String vaultId,
    String recordKey,
    List<int> plaintext,
  ) async {
    final nonce = randomBytes(_nonceLength);
    final box = await _aead.encrypt(
      plaintext,
      secretKey: SecretKey(epochs[current]!),
      nonce: nonce,
      aad: _aad(vaultId, recordKey, current),
    );
    return Uint8List.fromList([
      1,
      ..._u32(current),
      ...nonce,
      ...box.cipherText,
      ...box.mac.bytes,
    ]);
  }

  /// Opens a blob from [seal]. Throws on tampering or unknown epochs.
  Future<Uint8List> open(
    String vaultId,
    String recordKey,
    Uint8List blob,
  ) async {
    final epoch = blobEpoch(blob);
    final key = epochs[epoch];
    if (key == null) throw const FormatException('Unknown key epoch');
    final body = blob.sublist(5);
    final plaintext = await _aead.decrypt(
      SecretBox(
        body.sublist(_nonceLength, body.length - _tagLength),
        nonce: body.sublist(0, _nonceLength),
        mac: Mac(body.sublist(body.length - _tagLength)),
      ),
      secretKey: SecretKey(key),
      aad: _aad(vaultId, recordKey, epoch),
    );
    return Uint8List.fromList(plaintext);
  }

  /// The epoch in a blob header (the only part servers read).
  static int blobEpoch(Uint8List blob) {
    if (blob.length < 5 + _nonceLength + _tagLength || blob[0] != 1) {
      throw const FormatException('Malformed blob');
    }
    return blob.buffer.asByteData(blob.offsetInBytes).getUint32(1);
  }
}

/// Encrypts [keychain] to a member's X25519 public key (sealed-box style).
Future<String> wrapKeychain(
  Keychain keychain, {
  required String vaultId,
  required String memberId,
  required List<int> memberPublicKey,
}) async {
  final ephemeral = await _x25519.newKeyPair();
  final ephemeralPublic = (await ephemeral.extractPublicKey()).bytes;
  final key = await _wrapKey(
    ephemeral,
    ephemeralPublic,
    memberPublicKey,
    memberPublicKey,
  );
  final nonce = randomBytes(_nonceLength);
  final box = await _aead.encrypt(
    utf8.encode(jsonEncode(keychain.toJson())),
    secretKey: SecretKey(key),
    nonce: nonce,
    aad: _aad(vaultId, memberId, keychain.current),
  );
  return b64([
    1,
    ...ephemeralPublic,
    ...nonce,
    ...box.cipherText,
    ...box.mac.bytes,
  ]);
}

/// Opens a keychain from [wrapKeychain]. [epoch] is what the server claims;
/// it is authenticated, so a server cannot replay a keychain as another epoch.
Future<Keychain> unwrapKeychain(
  String wrapped, {
  required String vaultId,
  required String memberId,
  required int epoch,
  required Identity identity,
}) async {
  final bytes = unb64(wrapped);
  if (bytes.length < 1 + 32 + _nonceLength + _tagLength || bytes[0] != 1) {
    throw const FormatException('Malformed keychain');
  }
  final ephemeralPublic = bytes.sublist(1, 33);
  final nonce = bytes.sublist(33, 33 + _nonceLength);
  final keyPair = await identity.keyPair();
  final ownPublic = (await keyPair.extractPublicKey()).bytes;
  final key = await _wrapKey(
    keyPair,
    ephemeralPublic,
    ownPublic,
    ephemeralPublic,
  );
  final plaintext = await _aead.decrypt(
    SecretBox(
      bytes.sublist(33 + _nonceLength, bytes.length - _tagLength),
      nonce: nonce,
      mac: Mac(bytes.sublist(bytes.length - _tagLength)),
    ),
    secretKey: SecretKey(key),
    aad: _aad(vaultId, memberId, epoch),
  );
  final keychain = Keychain.fromJson(jsonDecode(utf8.decode(plaintext)));
  if (keychain.current != epoch) {
    throw const FormatException('Keychain epoch mismatch');
  }
  return keychain;
}

/// HKDF(X25519(own, remote), salt = ephemeralPub ‖ memberPub).
Future<Uint8List> _wrapKey(
  SimpleKeyPair own,
  List<int> ephemeralPublic,
  List<int> memberPublic,
  List<int> remote,
) async {
  final shared = await _x25519.sharedSecretKey(
    keyPair: own,
    remotePublicKey: SimplePublicKey(remote, type: KeyPairType.x25519),
  );
  return hkdf(
    await shared.extractBytes(),
    'cu-sync/wrap/v1',
    32,
    salt: [...ephemeralPublic, ...memberPublic],
  );
}

/// The one-time secret behind a pairing code. The server only ever sees
/// `hash(authToken)`; the MAC key stays between the two devices.
class PairingSecret {
  final Uint8List secret;
  PairingSecret(this.secret);
  PairingSecret.random() : secret = randomBytes(32);

  Future<String> authToken() async =>
      b64(await hkdf(secret, 'cu-sync/pair-auth/v1', 32));

  /// Binds a join request to this secret so the server cannot swap keys.
  Future<String> mac(List<String> fields) async => b64(
    await hmacSha256(
      await hkdf(secret, 'cu-sync/pair-mac/v1', 32),
      utf8.encode(fields.join('\n')),
    ),
  );
}

/// Short human-comparable fingerprint of a public key.
String fingerprint(List<int> publicKey) => hashing.sha256
    .convert(publicKey)
    .toString()
    .substring(0, 12)
    .toUpperCase()
    .replaceAllMapped(RegExp(r'.{4}(?!$)'), (m) => '${m[0]}-');
