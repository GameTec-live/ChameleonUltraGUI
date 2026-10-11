import 'dart:async';
import 'dart:typed_data';

import 'package:chameleonultragui/gui/page/read_card.dart';
import 'package:chameleonultragui/helpers/definitions.dart';
import 'package:chameleonultragui/helpers/general.dart';
import 'package:chameleonultragui/helpers/mifare_classic/general.dart';
import 'package:chameleonultragui/helpers/mifare_ultralight/general.dart';
import 'package:chameleonultragui/main.dart';
import 'package:chameleonultragui/sharedprefsprovider.dart';
import 'package:flutter/widgets.dart';

// Localizations
import 'package:chameleonultragui/generated/i18n/app_localizations.dart';

enum ReaderFrequency { hf, lf }

/// Drives the mobile "Read" tab. It only orchestrates the existing scan
/// helpers from the desktop reader and keeps their results for the UI.
class MobileReaderController extends ChangeNotifier {
  MobileReaderController(this.appState);

  static const _scanInterval = Duration(seconds: 2);
  static const _maxContinuousDuration = Duration(minutes: 1);

  final ChameleonGUIState appState;

  ReaderFrequency frequency = ReaderFrequency.hf;
  HFCardInfo hfInfo = HFCardInfo();
  LFCardInfo lfInfo = LFCardInfo();
  MifareClassicInfo mfcInfo = MifareClassicInfo();
  MifareUltralightInfo mfuInfo = MifareUltralightInfo();

  bool scanInProgress = false;
  bool continuousScan = false;
  Object? error;

  Timer? _timer;
  bool _disposed = false;

  Future<void> scanOnce(BuildContext context) async {
    if (scanInProgress) return;
    await _runScan(context);
  }

  Future<void> startContinuousScan(BuildContext context) async {
    if (continuousScan || scanInProgress) return;

    continuousScan = true;
    _notify();

    final startedAt = DateTime.now();
    _timer = Timer.periodic(
      _scanInterval,
      (_) => _continuousTick(context, startedAt),
    );
    await _continuousTick(context, startedAt);
  }

  void stopScans() {
    _timer?.cancel();
    _timer = null;
    if (continuousScan) {
      continuousScan = false;
      _notify();
    }
  }

  void setFrequency(ReaderFrequency f) {
    if (frequency == f) return;
    stopScans();
    frequency = f;
    error = null;
    _notify();
  }

  Future<void> overrideHfType(BuildContext context, TagType type) async {
    final localizations = AppLocalizations.of(context)!;

    hfInfo.type = type;
    hfInfo.tech = chameleonTagToString(type, localizations);
    _notify();

    try {
      final communicator = appState.communicator!;
      if (isMifareClassic(type)) {
        final info = await performMifareClassicScan(
          communicator,
          mfcInfo,
          context,
          _notify,
          override: type,
        );
        mfcInfo = info.$2;
      } else if (isMifareUltralight(type)) {
        final info = await performMifareUltralightScan(
          communicator,
          mfuInfo,
          override: type,
        );
        mfuInfo = info.$2;
      }
    } catch (e) {
      appState.log?.e(e);
      error = e;
    }
    _notify();
  }

  Future<void> saveHfUid(String name, AppLocalizations l) async {
    final tags = appState.sharedPreferencesProvider.getCards();
    tags.add(
      CardSave(
        uid: hfInfo.uid,
        sak: hexToBytes(hfInfo.sak)[0],
        atqa: hexToBytes(hfInfo.atqa),
        name: name,
        tag: hfInfo.type != TagType.unknown ? hfInfo.type : TagType.mifare1K,
        data: [],
        ats: (hfInfo.ats != l.no) ? hexToBytes(hfInfo.ats) : Uint8List(0),
        extraData: CardSaveExtra(
          ultralightSignature: mfuInfo.signature,
          ultralightVersion: mfuInfo.version,
          ultralightCounters: [],
        ),
      ),
    );
    appState.sharedPreferencesProvider.setCards(tags);
    appState.changesMade();
  }

  Future<void> saveLf(String name) async {
    final card = lfInfo.card;
    if (card == null) return;

    final tags = appState.sharedPreferencesProvider.getCards();
    tags.add(CardSave(uid: card.toString(), name: name, tag: card.type));
    appState.sharedPreferencesProvider.setCards(tags);
    appState.changesMade();
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    super.dispose();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  /// Runs one scan of the selected frequency and returns true when a card
  /// was found. Errors are logged and stored in [error].
  Future<bool> _runScan(BuildContext context) async {
    scanInProgress = true;
    error = null;
    _notify();

    try {
      if (frequency == ReaderFrequency.hf) {
        await _scanHf(context);
        return hfInfo.cardExist && hfInfo.uid.isNotEmpty;
      }
      await _scanLf();
      return lfInfo.cardExist && lfInfo.card != null;
    } catch (e) {
      appState.log?.e(e);
      error = e;
      return false;
    } finally {
      scanInProgress = false;
      _notify();
    }
  }

  Future<void> _scanHf(BuildContext context) async {
    final info = await readHFInfo(context, _notify);
    hfInfo = info.$1;
    mfcInfo = info.$2;
    mfuInfo = info.$3;
  }

  Future<void> _scanLf() async {
    final card = await readLFCard(appState.communicator!);
    lfInfo = LFCardInfo(cardExist: card != null);
    lfInfo.card = card;
  }

  Future<void> _continuousTick(BuildContext context, DateTime startedAt) async {
    if (!continuousScan || scanInProgress) return;

    if (DateTime.now().difference(startedAt) > _maxContinuousDuration) {
      stopScans();
      return;
    }

    final found = await _runScan(context);
    if (found || error != null) {
      stopScans();
    }
  }
}
