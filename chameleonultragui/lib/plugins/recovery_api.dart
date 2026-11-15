part of 'api.dart';

extension _RecoveryApi on PluginApi {
  void _registerRecovery() {
    methods.addAll({
      'recovery.darkside': (a) {
        final input = (a.single as Map).cast<String, Object?>();
        return _runNative(
          (operation) => native_recovery.darkside(
            native_recovery.DarksideDart(
              uid: _word(input, 'uid'),
              items: PluginApi.list(input['items']).map((item) {
                final data = (item as Map).cast<String, Object?>();
                return native_recovery.DarksideItemDart(
                  nt1: _word(data, 'nt1'),
                  ks1: _wideWord(data, 'ks1'),
                  par: _wideWord(data, 'par'),
                  nr: _word(data, 'nr'),
                  ar: _word(data, 'ar'),
                );
              }).toList(),
            ),
            operation: operation,
          ),
        );
      },
      'recovery.nested': (a) {
        final input = (a.single as Map).cast<String, Object?>();
        return _runNative(
          (operation) => native_recovery.nested(
            native_recovery.NestedDart(
              uid: _word(input, 'uid'),
              distance: _word(input, 'distance'),
              nt0: _word(input, 'nt0'),
              nt0Enc: _word(input, 'nt0Enc'),
              par0: _parity(input, 'par0'),
              nt1: _word(input, 'nt1'),
              nt1Enc: _word(input, 'nt1Enc'),
              par1: _parity(input, 'par1'),
            ),
            operation: operation,
          ),
        );
      },
      'recovery.staticNested': (a) {
        final input = (a.single as Map).cast<String, Object?>();
        final keyType = _word(input, 'keyType');
        if (keyType != 0x60 && keyType != 0x61) {
          throw ArgumentError(pluginLocalizations.plugin_error_key_type);
        }
        return _runNative(
          (operation) => native_recovery.staticNested(
            native_recovery.StaticNestedDart(
              uid: _word(input, 'uid'),
              keyType: keyType,
              nt0: _word(input, 'nt0'),
              nt0Enc: _word(input, 'nt0Enc'),
              nt1: _word(input, 'nt1'),
              nt1Enc: _word(input, 'nt1Enc'),
            ),
            operation: operation,
          ),
        );
      },
      'recovery.staticEncryptedNested': (a) {
        final input = (a.single as Map).cast<String, Object?>();
        return _runNative(
          (operation) => native_recovery.staticEncryptedNested(
            native_recovery.StaticEncryptedNestedDart(
              uid: _word(input, 'uid'),
              nt: _word(input, 'nt'),
              ntEnc: _word(input, 'ntEnc'),
              ntParEnc: _word(input, 'ntParEnc'),
            ),
            operation: operation,
          ),
        );
      },
      'recovery.hardNested': (a) {
        final nonces = PluginApi.bytes(a.single);
        if (nonces.length < 15 || (nonces.length - 6) % 9 != 0) {
          throw ArgumentError(pluginLocalizations.plugin_error_nonce_records);
        }
        return _runNative(
          (operation) => native_recovery.hardNested(
            native_recovery.HardNestedDart(nonces: nonces),
            operation: operation,
          ),
        );
      },
      'recovery.mfkey32': (a) {
        final input = (a.single as Map).cast<String, Object?>();
        return _runNative(
          (operation) => native_recovery.mfkey32(
            native_recovery.Mfkey32Dart(
              uid: _word(input, 'uid'),
              nt0: _word(input, 'nt0'),
              nt1: _word(input, 'nt1'),
              nr0Enc: _word(input, 'nr0Enc'),
              ar0Enc: _word(input, 'ar0Enc'),
              nr1Enc: _word(input, 'nr1Enc'),
              ar1Enc: _word(input, 'ar1Enc'),
            ),
            operation: operation,
          ),
        );
      },
      'recovery.mfkey64': (a) {
        final input = (a.single as Map).cast<String, Object?>();
        return _runNative(
          (operation) => native_recovery.mfkey64(
            native_recovery.Mfkey64Dart(
              uid: _word(input, 'uid'),
              nt: _word(input, 'nt'),
              nrEnc: _word(input, 'nrEnc'),
              arEnc: _word(input, 'arEnc'),
              atEnc: _word(input, 'atEnc'),
            ),
            operation: operation,
          ),
        );
      },
    });
  }

  Future<List<int>> _runNative(
    Future<List<int>> Function(RecoveryOperation) search,
  ) async {
    final operation = RecoveryOperation();
    _nativeOperation = operation;
    List<int> result = [];
    try {
      await operation.run(() async {
        result = await search(operation);
      });
      if (operation.wasCancelled || _cancelled) throw const RecoveryCancelled();
      // mfkey solvers report failure as UINT64_MAX, which FFI may expose as -1.
      // Keep actual 48-bit keys, including a valid zero key.
      return result.where((key) => key >= 0 && key <= 0xffffffffffff).toList();
    } finally {
      _nativeOperation = null;
    }
  }
}

// 64-bit fields accept hexadecimal strings to avoid loss through Lua numbers.
int _wideWord(Map<String, Object?> data, String key) {
  final value = data[key];
  if (value is String) {
    final text = value.startsWith('0x') ? value.substring(2) : value;
    if (!RegExp(r'^[0-9a-fA-F]{1,16}$').hasMatch(text)) {
      throw ArgumentError(pluginLocalizations.plugin_error_hex_field(key));
    }
    return int.parse(text, radix: 16);
  }
  if (value is! int || value < 0 || value > 0x1fffffffffffff) {
    throw ArgumentError(pluginLocalizations.plugin_error_integer_field(key));
  }
  return value;
}

int _word(Map<String, Object?> data, String key) {
  final value = _wideWord(data, key);
  return RangeError.checkValueInInterval(value, 0, 0xffffffff, key);
}

int _parity(Map<String, Object?> data, String key) =>
    RangeError.checkValueInInterval(_word(data, key), 0, 7, key);
