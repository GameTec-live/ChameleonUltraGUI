import 'dart:async';
import 'dart:convert';

import 'localization.dart';

import 'dart:io';
import 'dart:isolate';

import 'package:lualike/lualike.dart';

import 'plugin.dart';

import 'package:chameleonultragui/generated/i18n/app_localizations.dart';

typedef PluginCall = Future<Object?> Function(
  String method,
  List<Object?> arguments,
);

/// Lua runs off the UI isolate. Stop kills Lua immediately, then drains any
/// in-flight host call before releasing the device to the rest of the GUI.
class PluginRuntime {
  Isolate? _isolate;
  final _stopped = Completer<void>();
  bool get stopped => _stopped.isCompleted;
  void stop() {
    if (!stopped) _stopped.complete();
    _isolate?.kill(priority: Isolate.immediate);
  }

  Future<void> run(
    Plugin plugin,
    Iterable<String> methods,
    PluginCall call, {
    AppLocalizations? localizations,
  }) => withPluginLocalizations(
    localizations ?? pluginLocalizations,
    () => _run(plugin, methods, call),
  );

  Future<void> _run(
    Plugin plugin,
    Iterable<String> methods,
    PluginCall call,
  ) async {
    final events = ReceivePort();
    final done = Completer<void>();
    Future<void>? pending;
    final subscription = events.listen((dynamic event) {
      final message = event as List;
      switch (message[0]) {
        case 'call':
          final reply = message[3] as SendPort;
          pending = (pending ?? Future<void>.value()).then((_) async {
            try {
              if (stopped) throw StateError(pluginLocalizations.plugin_stopped);
              final result = await call(
                message[1] as String,
                (message[2] as List).cast<Object?>(),
              );
              if (!stopped) reply.send([true, result]);
            } catch (error) {
              if (!stopped) reply.send([false, error.toString()]);
            }
          });
        case 'done':
          if (!done.isCompleted) done.complete();
        case 'error':
          if (!done.isCompleted) {
            done.completeError(StateError(message[1].toString()));
          }
        default:
          if (!done.isCompleted) {
            done.completeError(
              StateError(
                pluginLocalizations.plugin_error_isolate(
                  message.first.toString(),
                ),
              ),
            );
          }
      }
    });
    try {
      _isolate = await Isolate.spawn(_execute, [
        events.sendPort,
        plugin.code,
        plugin.resources,
        methods.toList(),
        pluginLocalizations,
      ], onError: events.sendPort);
      if (stopped) _isolate!.kill(priority: Isolate.immediate);
      await Future.any([done.future, _stopped.future]);
    } finally {
      stop();
      await pending;
      await subscription.cancel();
      events.close();
    }
  }
}

Future<void> _execute(List<Object?> configuration) => withPluginLocalizations(
  configuration[4] as AppLocalizations,
  () => _executeLocalized(configuration),
);

Future<void> _executeLocalized(List<Object?> configuration) async {
  final host = configuration[0] as SendPort;
  try {
    final lua = LuaLike();
    final resources = (configuration[2] as Map).cast<String, String>();
    lua.expose('_host', (List<Object?> args) async {
      final values = args.map(_dartValue).toList();
      final reply = ReceivePort();
      try {
        host.send([
          'call',
          values.first,
          values.skip(1).toList(),
          reply.sendPort,
        ]);
        final response = await reply.first as List;
        return _luaValue({'ok': response[0], 'value': response[1]});
      } finally {
        reply.close();
      }
    });
    lua.expose('_resource', (List<Object?> args) {
      final key = _dartValue(args.single) as String;

      return _luaValue({
        'text': resources[key],
        'error': pluginLocalizations.plugin_error_resource(key),
      });
    });
    lua.expose('_codec', (List<Object?> args) {
      try {
        final operation = _dartValue(args[0]) as String;
        final value = _dartValue(args[1]);
        final text = value is String ? value : '';
        List<int> bytes() {
          final bytes = value is Map && value.isEmpty
              ? <int>[]
              : (value as List).cast<int>();
          if (bytes.any((b) => b < 0 || b > 255)) {
            throw ArgumentError(pluginLocalizations.plugin_error_bytes);
          }
          return bytes;
        }

        final result = switch (operation) {
          'encodeBytes' => base64Encode(bytes()),
          'decodeBytes' => base64Decode(text).toList(),
          'compressBytes' => base64Encode(gzip.encode(bytes())),
          'decompressBytes' => gzip.decode(base64Decode(text)).toList(),
          'encode' => base64Encode(utf8.encode(text)),
          'decode' => utf8.decode(base64Decode(text)),
          'compress' => base64Encode(gzip.encode(utf8.encode(text))),
          'decompress' => utf8.decode(gzip.decode(base64Decode(text))),
          _ => throw ArgumentError(pluginLocalizations.plugin_error_codec),
        };
        return _luaValue({'ok': true, 'value': result});
      } catch (error) {
        return _luaValue({'ok': false, 'value': error.toString()});
      }
    });
    final bootstrap = StringBuffer('''
-- Hide ambient filesystem/process capabilities. Modules come only from this plugin.
io = nil; os = nil; package = nil; debug = nil; dofile = nil; loadfile = nil
local host, resource, codec, compile = _host, _resource, _codec, load
_host = nil; _resource = nil; _codec = nil
chameleon = { resources = {}, codec = {} }
function chameleon.resources.get(key)
  if type(key) ~= 'string' then error(${jsonEncode(pluginLocalizations.plugin_error_resource_key)}) end
  local response = resource(key)
  if response.text == nil then error(response.error) end
  return response.text
end
local modules = {}
function require(key)
  if modules[key] ~= nil then return modules[key] end
  local chunk, err = compile(chameleon.resources.get(key), key, 't')
  if not chunk then error(err) end
  modules[key] = true
  local ok, result = pcall(chunk)
  if not ok then modules[key] = nil; error(result, 2) end
  if result == nil then result = true end
  modules[key] = result
  return result
end
chameleon.resources.require = require
local function convertText(operation, text)
  local response = codec(operation, text)
  if not response.ok then error(response.value, 2) end
  return response.value
end
function chameleon.codec.base64Encode(text) return convertText('encode', text) end
function chameleon.codec.base64Decode(text) return convertText('decode', text) end
function chameleon.codec.compress(text) return convertText('compress', text) end
function chameleon.codec.decompress(text) return convertText('decompress', text) end
function chameleon.codec.base64EncodeBytes(bytes) return convertText('encodeBytes', bytes) end
function chameleon.codec.base64DecodeBytes(text) return convertText('decodeBytes', text) end
function chameleon.codec.compressBytes(bytes) return convertText('compressBytes', bytes) end
function chameleon.codec.decompressBytes(text) return convertText('decompressBytes', text) end
''');
    final namespaces = <String>{};
    for (final method in configuration[3] as List<String>) {
      final parts = method.split('.');
      if (namespaces.add(parts.first)) {
        bootstrap.writeln('chameleon.${parts.first} = {}');
      }
      bootstrap.writeln('''chameleon.$method = function(...)
  local response = host("$method", ...)
  if not response.ok then error(response.value, 2) end
  return response.value
end''');
    }
    await lua.execute(bootstrap.toString());
    await lua.execute(configuration[1] as String);
    host.send(['done']);
  } catch (error) {
    host.send(['error', error.toString()]);
  }
}

// LuaLike's Value(List) is not recursively indexable as a Lua table.
Value _luaValue(Object? value) => switch (value) {
  List values => Value({
    for (var i = 0; i < values.length; i++) i + 1: _luaValue(values[i]),
  }),
  Map values => Value(
    values.map((key, value) => MapEntry(key, _luaValue(value))),
  ),
  _ => Value(value),
};

// Value.unwrap preserves UTF-8; LuaLike's fromLuaValue decodes strings as Latin-1.
Object? _dartValue(Object? value) {
  if (value is Value) return _dartValue(value.unwrap());
  if (value is LuaString) return value.toString();
  if (value is List) return value.map(_dartValue).toList();
  if (value is Map) {
    final entries = value.map((k, v) => MapEntry(_dartValue(k), _dartValue(v)));
    if (entries.isNotEmpty &&
        List.generate(
          entries.length,
          (i) => i + 1,
        ).every(entries.containsKey)) {
      return List.generate(entries.length, (i) => entries[i + 1]);
    }
    return entries;
  }
  return value;
}
