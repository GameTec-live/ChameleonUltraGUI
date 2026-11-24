import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Per-device BLE PIN backed by the platform secure store (DPAPI / Keystore).
class BlePinStore {
  BlePinStore._();

  static const _storage = FlutterSecureStorage();

  static String _key(String port) =>
      'ble_pin_${port.replaceAll(RegExp('[^0-9A-Fa-f]'), '').toUpperCase()}';

  static Future<String?> read(String port) async {
    try {
      final value = await _storage.read(key: _key(port));
      if (value == null || !RegExp(r'^\d{6}$').hasMatch(value)) {
        return null;
      }
      return value;
    } catch (_) {
      return null;
    }
  }

  static Future<void> save(String port, String pin) async {
    try {
      await _storage.write(key: _key(port), value: pin);
    } catch (_) {}
  }

  static Future<void> clear(String port) async {
    try {
      await _storage.delete(key: _key(port));
    } catch (_) {}
  }
}
