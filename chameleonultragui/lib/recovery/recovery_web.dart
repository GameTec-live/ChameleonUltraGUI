import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:typed_data';
import 'package:chameleonultragui/recovery/definitions.dart';

@JS('Worker')
extension type _Worker._(JSObject _) implements JSObject {
  external factory _Worker(String url);
  external set onmessage(JSFunction? handler);
  external void postMessage(JSObject msg);
}

@JS('Object')
extension type _JsObj._(JSObject _) implements JSObject {
  external factory _JsObj();
}

bool _initialized = false;
int _nextId = 0;
late _Worker _worker;
late JSFunction _onMessageHandler;
final Map<int, Completer<JSObject>> _pending = {};

Future<void> _ensureInitialized() async {
  if (_initialized) return;

  final workerUrl = Uri.base.resolve('recovery_worker.js').toString();
  _worker = _Worker(workerUrl);

  final readyCompleter = Completer<void>();

  _onMessageHandler = (JSObject e) {
    final data = e['data'] as JSObject;
    final type = (data['type'] as JSString?)?.toDart;
    if (type == 'ready') {
      if (!readyCompleter.isCompleted) readyCompleter.complete();
      return;
    }
    final id = (data['id'] as JSNumber).toDartInt;
    final completer = _pending.remove(id);
    if (completer != null) {
      completer.complete(data);
    }
  }.toJS;
  _worker.onmessage = _onMessageHandler;

  await readyCompleter.future;
  _initialized = true;
}

Future<JSObject> _call(String method, JSObject args) async {
  await _ensureInitialized();
  final id = _nextId++;
  final completer = Completer<JSObject>();
  _pending[id] = completer;

  final msg = _JsObj();
  msg['id'] = id.toJS;
  msg['method'] = method.toJS;
  msg['args'] = args;
  _worker.postMessage(msg);

  final response = await completer.future;
  final error = response['error'];
  if (error != null) {
    throw Exception((error as JSString).toDart);
  }
  return response;
}

List<int> _parseKeyArray(JSObject response) {
  final result = response['result'];
  if (result == null) return [];
  final arr = result as JSArray;
  return [for (var i = 0; i < arr.length; i++) int.parse((arr[i] as JSString).toDart)];
}

int _parseKeyBigInt(JSObject response) {
  final result = response['result'];
  if (result == null) return 0;
  return int.parse((result as JSString).toDart);
}

Future<List<int>> darkside(DarksideDart darkside) async {
  final mask32 = BigInt.from(0xFFFFFFFF);
  final flat = Int32List(darkside.items.length * 7);
  for (var i = 0; i < darkside.items.length; i++) {
    final item = darkside.items[i];
    final o = i * 7;
    flat[o] = item.nt1;
    flat[o + 1] = (item.ks1 & mask32).toInt();
    flat[o + 2] = ((item.ks1 >> 32) & mask32).toInt();
    flat[o + 3] = (item.par & mask32).toInt();
    flat[o + 4] = ((item.par >> 32) & mask32).toInt();
    flat[o + 5] = item.nr;
    flat[o + 6] = item.ar;
  }
  final args = _JsObj();
  args['uid'] = darkside.uid.toJS;
  args['flat'] = flat.toJS;
  return _parseKeyArray(await _call('darkside', args));
}

Future<List<int>> nested(NestedDart nested) async {
  final args = _JsObj();
  args['uid'] = nested.uid.toJS;
  args['dist'] = nested.distance.toJS;
  args['nt0'] = nested.nt0.toJS;
  args['nt0Enc'] = nested.nt0Enc.toJS;
  args['par0'] = nested.par0.toJS;
  args['nt1'] = nested.nt1.toJS;
  args['nt1Enc'] = nested.nt1Enc.toJS;
  args['par1'] = nested.par1.toJS;
  return _parseKeyArray(await _call('nested', args));
}

Future<List<int>> hardNested(HardNestedDart nested) async {
  final args = _JsObj();
  args['nonces'] = nested.nonces.toJS;
  final key = _parseKeyBigInt(await _call('hardnested', args));
  return key != 0 ? [key] : [];
}

Future<List<int>> staticNested(StaticNestedDart nested) async {
  final args = _JsObj();
  args['uid'] = nested.uid.toJS;
  args['keyType'] = nested.keyType.toJS;
  args['nt0'] = nested.nt0.toJS;
  args['nt0Enc'] = nested.nt0Enc.toJS;
  args['nt1'] = nested.nt1.toJS;
  args['nt1Enc'] = nested.nt1Enc.toJS;
  return _parseKeyArray(await _call('static_nested', args));
}

Future<List<int>> staticEncryptedNested(StaticEncryptedNestedDart nested) async {
  final args = _JsObj();
  args['uid'] = nested.uid.toJS;
  args['nt'] = nested.nt.toJS;
  args['ntEnc'] = nested.ntEnc.toJS;
  args['ntParEnc'] = nested.ntParEnc.toJS;
  return _parseKeyArray(await _call('static_encrypted_nested', args));
}

Future<List<int>> mfkey32(Mfkey32Dart mfkey) async {
  final args = _JsObj();
  args['uid'] = mfkey.uid.toJS;
  args['nt0'] = mfkey.nt0.toJS;
  args['nr0Enc'] = mfkey.nr0Enc.toJS;
  args['ar0Enc'] = mfkey.ar0Enc.toJS;
  args['nt1'] = mfkey.nt1.toJS;
  args['nr1Enc'] = mfkey.nr1Enc.toJS;
  args['ar1Enc'] = mfkey.ar1Enc.toJS;
  return [_parseKeyBigInt(await _call('mfkey32', args))];
}

Future<List<int>> mfkey64(Mfkey64Dart mfkey) async {
  final args = _JsObj();
  args['uid'] = mfkey.uid.toJS;
  args['nt'] = mfkey.nt.toJS;
  args['nrEnc'] = mfkey.nrEnc.toJS;
  args['arEnc'] = mfkey.arEnc.toJS;
  args['atEnc'] = mfkey.atEnc.toJS;
  return [_parseKeyBigInt(await _call('mfkey64', args))];
}
