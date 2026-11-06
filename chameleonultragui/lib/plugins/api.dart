import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:chameleonultragui/bridge/chameleon.dart';
import 'package:chameleonultragui/generated/i18n/app_localizations.dart';
import 'package:chameleonultragui/helpers/definitions.dart';
import 'package:chameleonultragui/helpers/general.dart';
import 'package:chameleonultragui/helpers/mifare_classic/recovery.dart';
import 'package:chameleonultragui/helpers/slot_dump.dart';
import 'package:chameleonultragui/helpers/hf14a4_slot.dart';
import 'package:chameleonultragui/helpers/write.dart';
import 'package:chameleonultragui/helpers/mifare_classic/general.dart';
import 'package:chameleonultragui/helpers/mifare_classic/write/base.dart';
import 'package:chameleonultragui/helpers/mifare_ultralight/general.dart';
import 'package:chameleonultragui/helpers/mifare_ultralight/write/base.dart';
import 'package:chameleonultragui/helpers/t55xx/write/base.dart';
import 'package:chameleonultragui/main.dart';
import 'package:chameleonultragui/sharedprefsprovider.dart';

import 'package:chameleonultragui/helpers/card_save_converters.dart';
import 'package:chameleonultragui/helpers/recovery_operation.dart';
import 'package:chameleonultragui/recovery/recovery.dart' as native_recovery;
import 'package:uuid/uuid.dart';
import 'package:logger/logger.dart';

import 'plugin.dart';
import 'localization.dart';

part 'device_api.dart';
part 'saved_data_api.dart';
part 'settings_api.dart';
part 'recovery_api.dart';

typedef ApiMethod = FutureOr<Object?> Function(List<Object?> args);

/// Explicit capability registry; Lua never receives application objects.
class PluginApi {
  final BuildContext context;
  final ChameleonGUIState app;
  final Plugin plugin;
  final Map<String, ApiMethod> methods = {};
  MifareClassicRecovery? _recovery;
  bool _cancelled = false;
  RecoveryOperation? _nativeOperation;
  VoidCallback? _closeDialog;

  PluginApi(this.context, this.app, this.plugin) {
    methods.addAll({
      'ui.info': (a) => _dialog(pluginLocalizations.plugin_dialog_info, a),
      'ui.warning': (a) =>
          _dialog(pluginLocalizations.plugin_dialog_warning, a),
      'ui.error': (a) => _dialog(pluginLocalizations.plugin_dialog_error, a),
      'ui.input': (a) =>
          _dialog(pluginLocalizations.plugin_dialog_input, a, input: true),
      'ui.snackbar': (a) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              pluginLocalizations.plugin_snackbar_text(
                a[0].toString(),
                plugin.name,
              ),
            ),
          ),
        );
        return null;
      },
      'classic.checkKeys': (a) async =>
          _classicResult(await _classic(a, recover: false, dump: false)),
      'classic.recover': (a) async =>
          _classicResult(await _classic(a, recover: true, dump: false)),
      'classic.read': (a) async =>
          _classicResult(await _classic(a, recover: true, dump: true)),
      'cards.read': (a) => _readCard(a),
      'cards.write': (a) => _writeCard(a),
      'device.send14ARaw': (a) {
        final options = a.length > 1 ? a[1] as Map : const {};
        return device.send14ARaw(
          bytes(a[0]),
          respTimeoutMs: options['respTimeoutMs'] as int? ?? 100,
          bitLen: options['bitLen'] as int?,
          activateRfField: options['activateRfField'] as bool? ?? true,
          waitResponse: options['waitResponse'] as bool? ?? true,
          appendCrc: options['appendCrc'] as bool? ?? true,
          autoSelect: options['autoSelect'] as bool? ?? true,
          keepRfField: options['keepRfField'] as bool? ?? false,
          checkResponseCrc: options['checkResponseCrc'] as bool? ?? true,
        );
      },
      'slots.read': (a) async {
        final type = TagType.values.byName(a[1] as String);
        if (type == TagType.hf14a4) {
          return jsonDecode(
            (await readHf14a4SlotIdentity(device, a[0] as String)).toJson(),
          );
        }
        if (!isMifareClassic(type) && !isMifareUltralight(type)) {
          throw ArgumentError(pluginLocalizations.plugin_error_hf_slot);
        }
        return jsonDecode(
          (await readHfDumpFromSlot(device, a[0] as String, type)).toJson(),
        );
      },
      'slots.load': (a) => _loadSlot(a[0] as int, _card(a[1])),
      'device.raw': (a) async {
        final response = await device.sendRawCmd(
          a[0] as int,
          data: bytes(a[1]),
        );
        return response == null
            ? null
            : {
                'command': response.command,
                'status': response.status,
                'data': response.data.toList(),
              };
      },
      'device.enums': (_) => {
        'TagType': TagType.values.map((v) => v.name).toList(),
        'TagFrequency': TagFrequency.values.map((v) => v.name).toList(),
        'AnimationSetting': AnimationSetting.values.map((v) => v.name).toList(),
        'ButtonType': ButtonType.values.map((v) => v.name).toList(),
        'ButtonConfig': ButtonConfig.values.map((v) => v.name).toList(),
        'MifareWriteMode': MifareWriteMode.values.map((v) => v.name).toList(),
        'Mf1PrngType': Mf1PrngType.values.map((v) => v.name).toList(),
        'commands': {
          for (final command in ChameleonCommand.values)
            command.name: command.value,
        },
      },
      'device.connected': (_) =>
          app.connector?.connected == true && app.connector?.isDFU == false,
    });
    _registerDevice();
    _registerSavedData();
    _registerSettings();
    _registerRecovery();
  }

  ChameleonCommunicator get device {
    if (_cancelled) throw StateError(pluginLocalizations.plugin_stopped);
    if (app.connector?.connected != true ||
        app.connector?.isDFU == true ||
        app.communicator == null) {
      throw StateError(pluginLocalizations.plugin_error_connection);
    }
    return app.communicator!;
  }

  Future<Object?> call(String method, List<Object?> args) =>
      withPluginLocalizations(
        AppLocalizations.of(context) ?? pluginLocalizations,
        () async {
          if (_cancelled) throw StateError(pluginLocalizations.plugin_stopped);
          final handler = methods[method];
          if (handler == null) {
            throw ArgumentError(
              pluginLocalizations.plugin_error_method(method),
            );
          }
          return normalize(await handler(args));
        },
      );

  void cancel() {
    _cancelled = true;
    _recovery?.operation.cancel();
    _nativeOperation?.cancel();
    _closeDialog?.call();
  }

  Future<Object?> _loadSlot(int slot, CardSave card) async {
    final lfSetters = <TagType, Future<void> Function(Uint8List)>{
      TagType.hidProx: device.setHIDProxEmulatorID,
      TagType.viking: device.setVikingEmulatorID,
      TagType.pac: device.setPacEmulatorID,
      TagType.ioProx: device.setIoProxEmulatorID,
      TagType.jablotron: device.setJablotronEmulatorID,
      TagType.idteck: device.setIdteckEmulatorID,
    };
    final hf =
        isMifareClassic(card.tag) ||
        isMifareUltralight(card.tag) ||
        card.tag == TagType.hf14a4;
    final lfSetter = isEM410X(card.tag)
        ? device.setEM410XEmulatorID
        : lfSetters[card.tag];
    if (!hf && lfSetter == null) {
      throw ArgumentError(pluginLocalizations.plugin_error_emulator_type);
    }
    final frequency = hf ? TagFrequency.hf : TagFrequency.lf;
    final type = isEM410X(card.tag) && card.tag != TagType.em410XElectra
        ? TagType.em410X
        : card.tag;
    await device.setReaderDeviceMode(false);
    await device.enableSlot(slot, frequency, true);
    await device.activateSlot(slot);
    await device.setSlotType(slot, type);
    await device.setDefaultDataToSlot(slot, type);
    if (hf) {
      await writeHf14a4SlotIdentity(device, card);
      if (card.tag != TagType.hf14a4) {
        await writeHfDumpToSlot(device, slot, card.tag, card.data);
      }
      if (isMifareUltralight(card.tag)) {
        final extra = card.extraData;
        if (extra.ultralightVersion.isNotEmpty) {
          await device.mf0EmulatorSetVersionData(extra.ultralightVersion);
        }
        if (extra.ultralightSignature.isNotEmpty) {
          await device.mf0EmulatorSetSignatureData(extra.ultralightSignature);
        }
        for (var i = 0; i < extra.ultralightCounters.length; i++) {
          await device.mf0EmulatorSetCounterData(
            i,
            extra.ultralightCounters[i],
            true,
          );
        }
        if (mfUltralightHasCounters(card.tag)) await device.mf0ResetAuthCount();
      }
    } else {
      final uid = card.tag == TagType.hidProx
          ? HIDCard.fromUID(card.uid).toString()
          : card.uid;
      await lfSetter!(_hex(uid));
    }
    await device.setSlotTagName(slot, card.name, frequency);
    await device.saveSlotData();
    app.changesMade();
    return null;
  }

  Future<Object?> _readCard(List<Object?> args) async {
    await device.setReaderDeviceMode(true);
    final identity = await device.scan14443aTag();
    if (identity == null) {
      throw StateError(pluginLocalizations.plugin_error_no_hf_card);
    }
    final options = args.isEmpty ? const <Object?, Object?>{} : args[0] as Map;
    final List<Uint8List> data;
    final TagType type;
    if (await device.detectMf1Support()) {
      type = mfClassicGetChameleonTagType(await mfClassicGetType(device));
      final recovery = await _classic(
        [options['keys'] ?? []],
        recover: true,
        dump: true,
      );
      data = recovery.cardData;
    } else {
      type = await mfUltralightType(device);
      data = [];
      for (var page = 0; page < mfUltralightGetPagesCount(type); page++) {
        final response = await device.send14ARaw(
          Uint8List.fromList([0x30, page]),
        );
        data.add(
          response.length >= 4
              ? Uint8List.sublistView(response, 0, 4)
              : Uint8List(0),
        );
      }
    }
    return jsonDecode(
      CardSave(
        name:
            options['name'] as String? ??
            pluginLocalizations.plugin_default_card_name,
        uid: bytesToHexSpace(identity.uid),
        sak: identity.sak,
        atqa: identity.atqa,
        ats: identity.ats,
        tag: type,
        data: data,
      ).toJson(),
    );
  }

  Future<Object?> _writeCard(List<Object?> args) async {
    final card = _card(args[0]);
    final options = args.length > 1 ? args[1] as Map : const {};
    final localizations = AppLocalizations.of(context)!;
    await device.setReaderDeviceMode(true);
    final helper = AbstractWriteHelper.getClassByCardType(
      card.tag,
      app,
      () {},
      localizations,
    );
    if (helper == null) {
      throw StateError(pluginLocalizations.plugin_error_card_type);
    }
    // Password-based writers cannot autodetect a magic generation.
    if (helper is BaseMifareUltralightWriteHelper) {
      helper.key = options['key'] as String? ?? '';
      try {
        return await helper.writeData(card, (_) {});
      } finally {
        helper.keyController.dispose();
      }
    }
    if (helper is BaseT55XXCardHelper) {
      helper.currentKey = options['currentKey'] as String? ?? '00000000';
      helper.newKey = options['newKey'] as String? ?? '00000000';
      try {
        return await helper.writeData(card, (_) {});
      } finally {
        helper.currentKeyController.dispose();
        helper.newKeyController.dispose();
      }
    }
    for (final method in helper.getAvailableMethodsByPriority()) {
      final selected = options['method'] as String?;
      if (selected != null
          ? selected != method.name
          : !await method.isMagic(card)) {
        continue;
      }
      await method.getCardType();
      if (method is BaseMifareClassicWriteHelper) {
        method.vanitySak = options['vanitySak'] as bool? ?? false;
        if (!method.isReady()) {
          method.recovery = await _classic(
            [options['keys'] ?? []],
            recover: true,
            dump: false,
          );
        }
      }
      if (!await method.isCompatible(card)) {
        throw StateError(pluginLocalizations.plugin_error_incompatible_card);
      }
      return method.writeData(card, (_) {});
    }
    throw StateError(pluginLocalizations.plugin_error_write_method);
  }

  Future<MifareClassicRecovery> _classic(
    List<Object?> args, {
    required bool recover,
    required bool dump,
  }) async {
    device; // fail before constructing helpers when disconnected
    final keys = args.isEmpty
        ? <Uint8List>[]
        : list(args[0]).map(bytes).toList();
    final recovery = MifareClassicRecovery(
      appState: app,
      update: () {},
      localizations: AppLocalizations.of(context)!,
      selectedDictionary: Dictionary(
        name: pluginLocalizations.plugin_default_dictionary_name,
        keys: keys,
      ),
    );
    _recovery = recovery;
    try {
      await recovery.initialize();
      if (recovery.mifareClassicType == MifareClassicType.none) {
        throw StateError(pluginLocalizations.plugin_error_no_classic_card);
      }
      if (_cancelled) throw StateError(pluginLocalizations.plugin_stopped);
      await recovery.checkKeys();
      if (_cancelled) throw StateError(pluginLocalizations.plugin_stopped);
      if (recover) await recovery.recoverKeys();
      if (_cancelled) throw StateError(pluginLocalizations.plugin_stopped);
      if (dump) await recovery.dumpData();
      if (recovery.error.isNotEmpty) throw StateError(recovery.error);
      return recovery;
    } finally {
      _recovery = null;
    }
  }

  static Map<String, Object?> _classicResult(MifareClassicRecovery recovery) =>
      {
        'keys': recovery.validKeys.map((k) => k.toList()).toList(),
        'data': recovery.cardData.map((b) => b.toList()).toList(),
        'allKeysFound': recovery.allKeysExists,
      };

  static CardSave _card(Object? value) {
    // Lua's empty table has no array/object distinction. Restore empty arrays
    // using the existing card schema before passing to the card importer.
    Object? arrays(Object? value) => switch (value) {
      Map m when m.isEmpty => <Object?>[],
      Map m => m.map((k, v) => MapEntry(k, arrays(v))),
      List l => l.map(arrays).toList(),
      _ => value,
    };
    final card = (value as Map).cast<String, Object?>();
    final normalized = {...card};
    for (final key in ['atqa', 'ats', 'data']) {
      if (card.containsKey(key)) normalized[key] = arrays(card[key]);
    }
    if (card['extra'] is Map) {
      normalized['extra'] = (card['extra'] as Map).map(
        (k, v) => MapEntry(k, arrays(v)),
      );
    }
    return CardSave.fromJson(jsonEncode(normalized));
  }

  Future<Object?> _dialog(
    String kind,
    List<Object?> args, {
    bool input = false,
  }) async {
    final localizations = pluginLocalizations;
    final options = args.length > 1
        ? (args[1] as Map).cast<String, Object?>()
        : <String, Object?>{};
    final type = options['type'] ?? 'text';
    if (input && !['text', 'number', 'choice', 'boolean'].contains(type)) {
      throw ArgumentError(localizations.plugin_error_input_type);
    }
    final choices = options['choices'] == null
        ? <String>[]
        : list(options['choices']).cast<String>();
    if (input && type == 'choice' && choices.isEmpty) {
      throw ArgumentError(localizations.plugin_error_choices);
    }
    final controller = TextEditingController(
      text: options['default']?.toString() ?? '',
    );
    Object? selected = type == 'boolean'
        ? options['default'] == true
        : choices.contains(options['default'])
        ? options['default']
        : choices.firstOrNull;
    try {
      return await showDialog<Object?>(
        context: context,
        builder: (dialogContext) {
          _closeDialog = () => Navigator.of(dialogContext).pop();
          return StatefulBuilder(
            builder: (context, update) => AlertDialog(
              title: Text(localizations.plugin_dialog_title(kind, plugin.name)),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(args[0] as String),
                    if (options['description'] != null)
                      Text(options['description'] as String),
                    if (input && type == 'choice')
                      DropdownButton<String>(
                        value: selected as String?,
                        items: choices
                            .map(
                              (c) => DropdownMenuItem(value: c, child: Text(c)),
                            )
                            .toList(),
                        onChanged: (v) => update(() => selected = v),
                      ),
                    if (input && type == 'boolean')
                      Switch(
                        value: selected as bool,
                        onChanged: (v) => update(() => selected = v),
                      ),
                    if (input && (type == 'text' || type == 'number'))
                      TextField(
                        controller: controller,
                        autofocus: true,
                        obscureText: options['secret'] == true,
                        keyboardType: type == 'number'
                            ? const TextInputType.numberWithOptions(
                                decimal: true,
                                signed: true,
                              )
                            : TextInputType.text,
                        onChanged: (_) => update(() {}),
                      ),
                  ],
                ),
              ),
              actions: [
                if (input)
                  TextButton(
                    onPressed: () => Navigator.pop(dialogContext),
                    child: Text(localizations.cancel),
                  ),
                TextButton(
                  onPressed:
                      input &&
                          ((options['required'] == true &&
                                  controller.text.isEmpty &&
                                  type == 'text') ||
                              (type == 'number' &&
                                  num.tryParse(controller.text) == null))
                      ? null
                      : () => Navigator.pop(
                          dialogContext,
                          !input
                              ? true
                              : type == 'number'
                              ? num.parse(controller.text)
                              : type == 'text'
                              ? controller.text
                              : selected,
                        ),
                  child: Text(localizations.ok),
                ),
              ],
            ),
          );
        },
      );
    } finally {
      _closeDialog = null;
      // The closing route may still animate with its text field attached.
      Future<void>.delayed(const Duration(seconds: 1), controller.dispose);
    }
  }

  static List<Object?> list(Object? value) =>
      value is Map && value.isEmpty ? [] : (value as List).cast<Object?>();
  static Uint8List bytes(Object? value) {
    final values = list(value).cast<int>();
    if (values.any((b) => b < 0 || b > 255)) {
      throw ArgumentError(pluginLocalizations.plugin_error_bytes);
    }
    return Uint8List.fromList(values);
  }

  static Uint8List _hex(String value) => hexToBytes(value.replaceAll(' ', ''));

  static Object? normalize(Object? value) => switch (value) {
    Enum e => e.name,
    FirmwareVersion v => {
      'legacyProtocol': normalize(v.legacyProtocol),
      'version': normalize(v.version),
    },
    NTDistance v => {
      'uid': normalize(v.uid),
      'distance': normalize(v.distance),
    },
    NestedNonce v => {
      'nt': normalize(v.nt),
      'ntEnc': normalize(v.ntEnc),
      'parity': normalize(v.parity),
    },
    NestedNonces v => {'nonces': normalize(v.nonces)},
    SlotNames v => {'hf': normalize(v.hf), 'lf': normalize(v.lf)},
    SlotTypes v => {'hf': normalize(v.hf), 'lf': normalize(v.lf)},
    EnabledSlotInfo v => {'hf': normalize(v.hf), 'lf': normalize(v.lf)},
    Darkside v => {
      'uid': normalize(v.uid),
      'nt1': normalize(v.nt1),
      'par': normalize(v.par),
      'ks1': normalize(v.ks1),
      'nr': normalize(v.nr),
      'ar': normalize(v.ar),
    },
    DetectionResult v => {
      'block': normalize(v.block),
      'type': normalize(v.type),
      'isNested': normalize(v.isNested),
      'uid': normalize(v.uid),
      'nt': normalize(v.nt),
      'nr': normalize(v.nr),
      'ar': normalize(v.ar),
    },
    BatteryCharge v => {
      'voltage': normalize(v.voltage),
      'percent': normalize(v.percent),
      'condition': normalize(v.condition),
    },
    EmulatorSettings v => {
      'isDetectionEnabled': normalize(v.isDetectionEnabled),
      'isGen1a': normalize(v.isGen1a),
      'isGen2': normalize(v.isGen2),
      'isAntiColl': normalize(v.isAntiColl),
      'writeMode': normalize(v.writeMode),
    },
    DeviceSettings v => {
      'animation': normalize(v.animation),
      'aPress': normalize(v.aPress),
      'bPress': normalize(v.bPress),
      'aLongPress': normalize(v.aLongPress),
      'bLongPress': normalize(v.bLongPress),
      'pairingEnabled': normalize(v.pairingEnabled),
      'key': normalize(v.key),
      'wakeTimeSeconds': normalize(v.wakeTimeSeconds),
      'longPressThreshold': normalize(v.longPressThreshold),
    },
    ChameleonMessage v => {
      'command': normalize(v.command),
      'status': normalize(v.status),
      'data': normalize(v.data),
    },
    LFCard c => {'uid': c.uid.toList(), 'type': c.type.name},
    CardData c => {
      'uid': c.uid.toList(),
      'sak': c.sak,
      'atqa': c.atqa.toList(),
      'ats': c.ats.toList(),
    },
    List l => l.map(normalize).toList(),
    Map m => m.map((k, v) => MapEntry(k, normalize(v))),
    null || String() || num() || bool() => value,
    _ => throw StateError(
      pluginLocalizations.plugin_error_result(value.runtimeType.toString()),
    ),
  };
}
