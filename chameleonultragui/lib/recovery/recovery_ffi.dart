import 'dart:async';
import 'dart:core';
import 'dart:ffi';
import 'dart:io' as io;
import 'dart:io';
import 'dart:isolate';
import 'package:chameleonultragui/helpers/general.dart';
import 'package:dylib/dylib.dart';
import 'bindings.dart';
import 'package:ffi/ffi.dart';
import 'dart:ffi' as ffi;
import 'package:logger/logger.dart';
import 'definitions.dart';

Logger log = Logger();

Future<List<int>> darkside(DarksideDart darkside) async {
  final SendPort helperIsolateSendPort = await _helperIsolateSendPort;
  final int requestId = _nextSumRequestId++;
  final DarksideRequest request = DarksideRequest(requestId, darkside);
  final Completer<List<int>> completer = Completer<List<int>>();
  requests[requestId] = completer;
  helperIsolateSendPort.send(request);
  return completer.future;
}

Future<List<int>> nested(NestedDart nested) async {
  final SendPort helperIsolateSendPort = await _helperIsolateSendPort;
  final int requestId = _nextSumRequestId++;
  final NestedRequest request = NestedRequest(requestId, nested);
  final Completer<List<int>> completer = Completer<List<int>>();
  requests[requestId] = completer;
  helperIsolateSendPort.send(request);
  return completer.future;
}

Future<List<int>> mfkey32(Mfkey32Dart mfkey) async {
  final SendPort helperIsolateSendPort = await _helperIsolateSendPort;
  final int requestId = _nextSumRequestId++;
  final Mfkey32Request request = Mfkey32Request(requestId, mfkey);
  final Completer<List<int>> completer = Completer<List<int>>();
  requests[requestId] = completer;
  helperIsolateSendPort.send(request);
  return completer.future;
}

String resolvePath() {
  String path = resolveDylibPath(
    'recovery',
    dartDefine: 'LIBRECOVERY_PATH',
    environmentVariable: 'LIBRECOVERY_PATH',
  );
  if (!io.File(path).existsSync() &&
      Platform.environment.containsKey('FLUTTER_TEST')) {
    log.d("Library test hotfix: Library not exists");
    Directory dir = Directory('build/${platformToPath()}');
    for (var f in dir.listSync(recursive: true).toList()) {
      if (f.path.endsWith(path)) {
        log.e(
            "THIS HOTFIX IS ONLY FOR TESTS. IF YOU SEE THIS LINE ON DEBUG/RELEASE BUILDS REPORT IT IMMEDIATELY.");
        log.e("THIS WILL LEAD TO HIGH SECURITY VULNERABILITY.");
        log.e("Library test hotfix: found at ${f.path}");
        path = f.path;
        break;
      }
    }
  } else if (!io.File(path).existsSync() &&
      (Platform.isMacOS || Platform.isIOS)) {
    return 'recovery.framework/recovery';
  }
  return path;
}

/// The bindings to the native functions in [_dylib].
final Recovery _bindings = Recovery(ffi.DynamicLibrary.open(resolvePath()));

/// A response with the result of `sum`.
///
/// Typically sent from one isolate to another.
class KeyResponse {
  final int id;
  final List<int> result;

  const KeyResponse(this.id, this.result);
}

/// Counter to identify requests and [Response]s.
int _nextSumRequestId = 0;

/// Mapping from request `id`s to the completers corresponding to the correct future of the pending request.
final Map<int, Completer<List<int>>> requests = <int, Completer<List<int>>>{};

/// The SendPort belonging to the helper isolate.
Future<SendPort> _helperIsolateSendPort = () async {
  // The helper isolate is going to send us back a SendPort, which we want to
  // wait for.
  final Completer<SendPort> completer = Completer<SendPort>();

  // Receive port on the main isolate to receive messages from the helper.
  // We receive two types of messages:
  // 1. A port to send messages on.
  // 2. Responses to requests we sent.
  final ReceivePort receivePort = ReceivePort()
    ..listen((dynamic data) {
      if (data is SendPort) {
        // The helper isolate sent us the port on which we can sent it requests.
        completer.complete(data);
        return;
      }
      if (data is KeyResponse) {
        // The helper isolate sent us a response to a request we sent.
        final Completer<List<int>> completer = requests[data.id]!;
        requests.remove(data.id);
        completer.complete(data.result);
        return;
      }
      throw UnsupportedError('Unsupported message type: ${data.runtimeType}');
    });

  // Start the helper isolate.
  await Isolate.spawn((SendPort sendPort) async {
    final ReceivePort helperReceivePort = ReceivePort()
      ..listen((dynamic data) {
        // On the helper isolate listen to requests and respond to them.
        if (data is DarksideRequest) {
          Pointer<Darkside> pointer = calloc();
          final itemPointer = calloc<DarksideItem>(256);
          pointer.ref.uid = data.darkside.uid;
          var i = 0;
          for (var item in data.darkside.items) {
            var value = itemPointer.elementAt(i);
            value.ref.ar = item.ar;
            value.ref.ks1 = item.ks1.toInt();
            value.ref.nr = item.nr;
            value.ref.nt1 = item.nt1;
            value.ref.par = item.par.toInt();
            i++;
          }
          pointer.ref.items = itemPointer;
          pointer.ref.count = i;

          Pointer<Uint32> count = calloc();
          count.value = 0;
          List<int> keys = [];
          final Pointer<Uint64> result = _bindings.darkside(pointer, count);
          for (var i = 0; i < count.value; i++) {
            keys.add(result.elementAt(i).value);
          }
          final KeyResponse response = KeyResponse(data.id, keys);
          sendPort.send(response);
          return;
        } else if (data is NestedRequest) {
          Pointer<Nested> pointer = calloc();
          pointer.ref.uid = data.nested.uid;
          pointer.ref.dist = data.nested.distance;
          pointer.ref.nt0 = data.nested.nt0;
          pointer.ref.nt0_enc = data.nested.nt0Enc;
          pointer.ref.par0 = data.nested.par0;
          pointer.ref.nt1 = data.nested.nt1;
          pointer.ref.nt1_enc = data.nested.nt1Enc;
          pointer.ref.par1 = data.nested.par1;

          Pointer<Uint32> count = calloc();
          count.value = 0;
          List<int> keys = [];
          final Pointer<Uint64> result = _bindings.nested(pointer, count);
          for (var i = 0; i < count.value; i++) {
            keys.add(result.elementAt(i).value);
          }
          final KeyResponse response = KeyResponse(data.id, keys);
          sendPort.send(response);
          return;
        } else if (data is Mfkey32Request) {
          Pointer<Mfkey32> pointer = calloc();
          pointer.ref.uid = data.mfkey32.uid;
          pointer.ref.nt0 = data.mfkey32.nt0;
          pointer.ref.nt1 = data.mfkey32.nt1;
          pointer.ref.nr0_enc = data.mfkey32.nr0Enc;
          pointer.ref.ar0_enc = data.mfkey32.ar0Enc;
          pointer.ref.nr1_enc = data.mfkey32.nr1Enc;
          pointer.ref.ar1_enc = data.mfkey32.ar1Enc;

          final int result = _bindings.mfkey32(pointer);
          final KeyResponse response = KeyResponse(data.id, [result]);
          sendPort.send(response);
          return;
        }
        throw UnsupportedError('Unsupported message type: ${data.runtimeType}');
      });

    // Send the port to the main isolate on which we can receive requests.
    sendPort.send(helperReceivePort.sendPort);
  }, receivePort.sendPort);

  // Wait until the helper isolate has sent us back the SendPort on which we
  // can start sending requests.
  return completer.future;
}();
