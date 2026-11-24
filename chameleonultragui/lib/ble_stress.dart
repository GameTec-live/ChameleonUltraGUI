import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:chameleonultragui/bridge/chameleon.dart';
import 'package:chameleonultragui/connector/ble_trace.dart';
import 'package:chameleonultragui/connector/serial_abstract.dart';
import 'package:chameleonultragui/connector/serial_ble_windows.dart';
import 'package:chameleonultragui/helpers/definitions.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:logger/logger.dart';

Future<void> runBleStress() async {
  final env = Platform.environment;
  final cycles = int.tryParse(env['CHAMELEON_BLE_CYCLES'] ?? '25') ?? 25;
  final hold = env['CHAMELEON_BLE_HOLD'] == '1';
  final mode = env['CHAMELEON_BLE_MODE'] ?? 'robust';
  final trace = BleTrace.instance;

  BleTrace.setMode(mode);
  BleTrace.setCycle(null);
  trace.reset();
  final log = Logger(level: Level.off);
  final serial = WindowsBLESerial(log: log);

  trace.log('harness.start', 'mode=$mode cycles=$cycles hold=$hold');

  final results = <Map<String, Object?>>[];
  var success = 0;
  final stageFailures = <String, int>{};

  final acquireWatch = Stopwatch()..start();
  final acquired = await _acquire(serial);
  final acquireMs = acquireWatch.elapsedMilliseconds;
  trace.log('harness.acquire.done',
      'port=${acquired?.port} ms=$acquireMs');

  if (acquired == null) {
    final summary = <String, Object?>{
      'mode': mode,
      'cycles': 0,
      'success': 0,
      'success_rate': 0,
      'acquire_ms': acquireMs,
      'error': 'acquire_timeout',
    };
    trace.log('harness.failed', jsonEncode(summary));
    _writeStats(mode, summary, results);
    await trace.flush();
    await trace.close();
    exit(0);
  }

  ChameleonCommunicator? holdComm;

  for (var cycle = 1; cycle <= cycles; cycle++) {
    BleTrace.setCycle(cycle);
    final rec = <String, Object?>{'cycle': cycle};
    final total = Stopwatch()..start();
    var stage = 'disconnect';
    ChameleonCommunicator? comm;

    try {
      await serial.performDisconnect();
      await Future<void>.delayed(const Duration(milliseconds: 100));

      stage = 'scan';
      final scanWatch = Stopwatch()..start();
      final devices = await serial.scanNow();
      rec['scan_ms'] = scanWatch.elapsedMilliseconds;
      if (devices.isEmpty) {
        throw 'scan_empty';
      }
      final info = devices.first;
      rec['port'] = info.port;

      stage = 'connect';
      final connectWatch = Stopwatch()..start();
      final ok = await serial.connectSpecificDevice(info.port);
      rec['connect_ms'] = connectWatch.elapsedMilliseconds;
      if (!ok) {
        throw 'connect_failed';
      }

      stage = 'ping';
      comm = ChameleonCommunicator(log, port: serial);
      final pingWatch = Stopwatch()..start();
      await comm.sendCmd(
        ChameleonCommand.getBatteryCharge,
        timeout: const Duration(seconds: 2),
      );
      rec['ping_ms'] = pingWatch.elapsedMilliseconds;

      rec['ok'] = true;
      success++;
      holdComm = comm;
      trace.log('cycle.ok',
          'scan_ms=${rec['scan_ms']} connect_ms=${rec['connect_ms']} ping_ms=${rec['ping_ms']} total_ms=${total.elapsedMilliseconds}');
    } catch (e) {
      rec['ok'] = false;
      rec['stage'] = stage;
      rec['error'] = '${e.runtimeType}: $e';
      stageFailures[stage] = (stageFailures[stage] ?? 0) + 1;
      trace.log('cycle.fail',
          'stage=$stage error=${rec['error']} total_ms=${total.elapsedMilliseconds}');
    } finally {
      final keepForHold = hold && cycle == cycles && holdComm != null;
      if (!keepForHold) {
        try {
          await serial.performDisconnect();
        } catch (_) {}
      }
      rec['total_ms'] = total.elapsedMilliseconds;
      results.add(rec);
      trace.log('cycle.done', jsonEncode(rec));
      await trace.flush();
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
  }
  BleTrace.setCycle(null);

  final summary = <String, Object?>{
    'mode': mode,
    'cycles': cycles,
    'success': success,
    'success_rate': cycles == 0 ? 0 : success / cycles,
    'acquire_ms': acquireMs,
    'avg_scan_ms': _average(results, 'scan_ms'),
    'avg_connect_ms': _average(results, 'connect_ms'),
    'avg_ping_ms': _average(results, 'ping_ms'),
    'avg_total_ms': _average(results, 'total_ms'),
    'failures': stageFailures,
  };
  trace.log('harness.done', jsonEncode(summary));
  _writeStats(mode, summary, results);
  await trace.flush();

  if (hold) {
    var comm = holdComm;
    if (comm == null) {
      final again = await _acquire(serial);
      if (again != null) {
        comm = ChameleonCommunicator(log, port: serial);
      }
    }
    if (comm != null) {
      final release = File('${Directory.systemTemp.path}'
          '${Platform.pathSeparator}chameleon_ble_release');
      if (release.existsSync()) {
        release.deleteSync();
      }
      trace.log('hold.start', '');
      while (!release.existsSync()) {
        try {
          await comm.sendCmd(
            ChameleonCommand.getBatteryCharge,
            timeout: const Duration(seconds: 2),
          );
        } catch (_) {}
        await Future<void>.delayed(const Duration(seconds: 1));
      }
      trace.log('hold.released', '');
    } else {
      trace.log('hold.failed', '');
    }
  }

  try {
    await serial.performDisconnect();
  } catch (_) {}
  await trace.flush();
  await trace.close();
  exit(0);
}

Future<Chameleon?> _acquire(WindowsBLESerial serial) async {
  final watch = Stopwatch()..start();
  var round = 0;
  while (watch.elapsed < const Duration(minutes: 60)) {
    round++;
    final completer = Completer<Chameleon?>();
    StreamSubscription<List<ScanResult>>? subscription;
    var resolved = false;

    subscription = FlutterBluePlus.onScanResults.listen((results) {
      if (resolved) {
        return;
      }
      if (results.isNotEmpty && round == 1) {
        final first = results.first;
        BleTrace.instance.log('harness.scan.results',
            'count=${results.length} id=${first.device.remoteId.str} adv=${first.advertisementData.advName} plat=${first.device.platformName}');
      }
      for (final result in results) {
        var name = result.advertisementData.advName;
        if (name.isEmpty) {
          name = result.device.platformName;
        }
        if (!name.startsWith('ChameleonUltra') &&
            !name.startsWith('ChameleonLite')) {
          continue;
        }
        resolved = true;
        final info = Chameleon(
          port: result.device.remoteId.str,
          device: name.startsWith('ChameleonUltra')
              ? ChameleonDevice.ultra
              : ChameleonDevice.lite,
          type: ConnectionType.ble,
          dfu: false,
        );
        serial.chameleonMap[info.port] = info;
        BleTrace.instance.log('harness.acquire.found',
            'round=$round port=${info.port} name=$name ms=${watch.elapsedMilliseconds}');
        unawaited(() async {
          try {
            await FlutterBluePlus.stopScan();
          } catch (_) {}
          final ok = await serial.connectSpecificDevice(info.port);
          BleTrace.instance.log('harness.acquire.connect',
              'ok=$ok port=${info.port} ms=${watch.elapsedMilliseconds}');
          if (!completer.isCompleted) {
            completer.complete(ok ? info : null);
          }
        }());
        return;
      }
    });

    try {
      final adapter = await FlutterBluePlus.adapterState
          .firstWhere((state) => state != BluetoothAdapterState.unknown)
          .timeout(const Duration(seconds: 2));
      BleTrace.instance.log('harness.adapter',
          'state=$adapter round=$round');
    } catch (e) {
      BleTrace.instance.log('harness.adapter', 'error=$e round=$round');
    }

    try {
      BleTrace.instance.log('harness.acquire.scan', 'round=$round');
      await FlutterBluePlus.startScan(timeout: const Duration(minutes: 2));
      BleTrace.instance.log('harness.scan.started',
          'round=$round isScanning=${FlutterBluePlus.isScanningNow}');
    } catch (e) {
      BleTrace.instance.log('harness.acquire.error',
          'round=$round error=${e.runtimeType}: $e');
    }

    final result = await completer.future.timeout(
      const Duration(minutes: 2),
      onTimeout: () => null,
    );
    await subscription.cancel();
    try {
      await FlutterBluePlus.stopScan();
    } catch (_) {}
    if (result != null) {
      return result;
    }
    await Future<void>.delayed(const Duration(milliseconds: 300));
  }
  return null;
}

double _average(List<Map<String, Object?>> results, String key) {
  final values = results
      .where((record) => record[key] is int)
      .map((record) => record[key] as int)
      .toList();
  if (values.isEmpty) {
    return 0;
  }
  return values.reduce((a, b) => a + b) / values.length;
}

void _writeStats(
    String mode, Map<String, Object?> summary, List<Map<String, Object?>> cycles) {
  try {
    final file = File('${Directory.systemTemp.path}'
        '${Platform.pathSeparator}chameleon_ble_stats_$mode.json');
    file.writeAsStringSync(jsonEncode({'summary': summary, 'cycles': cycles}));
  } catch (_) {}
}
