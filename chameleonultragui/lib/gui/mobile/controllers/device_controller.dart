import 'package:chameleonultragui/bridge/chameleon.dart';
import 'package:chameleonultragui/connector/serial_abstract.dart';
import 'package:chameleonultragui/helpers/definitions.dart';
import 'package:chameleonultragui/helpers/general.dart';
import 'package:chameleonultragui/helpers/slot_loader.dart';
import 'package:chameleonultragui/main.dart';
import 'package:chameleonultragui/sharedprefsprovider.dart';
import 'package:flutter/foundation.dart';

enum DeviceLoadState { idle, loading, ready, error }

/// Caches what the mobile UI shows about the connected device (battery,
/// slots, firmware) so it is requested once per connection, or when the user
/// refreshes, instead of on every rebuild.
///
/// It only orchestrates existing [ChameleonCommunicator] commands.
class MobileDeviceController extends ChangeNotifier {
  MobileDeviceController(this.appState) {
    appState.addListener(_onAppStateChanged);
    _onAppStateChanged();
  }

  final ChameleonGUIState appState;

  ChameleonCommunicator? _communicator;
  bool _disposed = false;

  DeviceLoadState state = DeviceLoadState.idle;
  Object? error;

  BatteryCharge? battery;
  List<SlotTypes> slotTypes = _defaultSlotTypes();
  List<EnabledSlotInfo> enabledSlots = _defaultEnabledSlots();
  List<SlotNames> slotNames = _defaultSlotNames();
  int activeSlot = 0;
  bool slotsLoaded = false;
  bool readerMode = false;

  String firmwareVersion = '';
  String commitHash = '';
  bool legacyProtocol = false;
  bool capabilitiesSupported = true;

  /// 0..100 while a card is being uploaded to a slot, -1 otherwise.
  int uploadProgress = -1;

  bool get isUploading => uploadProgress != -1;

  bool get isConnected {
    final connector = appState.connector;
    return connector != null &&
        connector.connected &&
        !connector.isDFU &&
        appState.communicator != null;
  }

  /// Number of slots holding at least one card.
  int get usedSlots =>
      slotsLoaded ? slotTypes.where((s) => s.notMatch()).length : 0;

  static List<SlotTypes> _defaultSlotTypes() =>
      List.generate(8, (_) => SlotTypes());
  static List<EnabledSlotInfo> _defaultEnabledSlots() =>
      List.generate(8, (_) => EnabledSlotInfo());
  static List<SlotNames> _defaultSlotNames() =>
      List.generate(8, (_) => SlotNames());

  void _onAppStateChanged() {
    final communicator = appState.communicator;
    if (identical(communicator, _communicator)) {
      return;
    }

    _communicator = communicator;
    _reset();

    if (isConnected) {
      load();
    } else {
      _notify();
    }
  }

  void _reset() {
    state = DeviceLoadState.idle;
    error = null;
    battery = null;
    slotTypes = _defaultSlotTypes();
    enabledSlots = _defaultEnabledSlots();
    slotNames = _defaultSlotNames();
    activeSlot = 0;
    slotsLoaded = false;
    readerMode = false;
    firmwareVersion = '';
    commitHash = '';
    legacyProtocol = false;
    capabilitiesSupported = true;
    uploadProgress = -1;
  }

  void _notify() {
    if (!_disposed) {
      notifyListeners();
    }
  }

  Future<T> _safe<T>(Future<T> Function() request, T fallback) async {
    try {
      return await request();
    } catch (e) {
      appState.log?.e(e);
      return fallback;
    }
  }

  /// Loads everything shown on the dashboard.
  Future<void> load() async {
    final communicator = _communicator;
    if (communicator == null) {
      return;
    }

    state = DeviceLoadState.loading;
    error = null;
    _notify();

    try {
      final firmware = await communicator.getFirmwareVersion();
      if (!identical(communicator, _communicator)) return;

      legacyProtocol = firmware.legacyProtocol;
      firmwareVersion = numToVerCode(firmware.version);

      commitHash = await _safe(communicator.getGitCommitHash, '');
      battery = await _safe<BatteryCharge?>(
        communicator.getBatteryCharge,
        null,
      );
      capabilitiesSupported = await _areCapabilitiesSupported(communicator);
      readerMode = await _safe(communicator.isReaderDeviceMode, false);
      await _loadSlots(communicator);
      if (!identical(communicator, _communicator)) return;

      state = DeviceLoadState.ready;
    } catch (e) {
      if (!identical(communicator, _communicator)) return;

      appState.log?.e(e);
      error = e;
      state = DeviceLoadState.error;
    }

    _notify();
  }

  Future<void> refresh() async {
    if (isUploading) {
      return;
    }

    await load();
  }

  /// Reloads slot types, names, enabled state and the active slot.
  Future<void> refreshSlots() async {
    final communicator = _communicator;
    if (communicator == null) {
      return;
    }

    await _loadSlots(communicator);
    _notify();
  }

  Future<void> _loadSlots(ChameleonCommunicator communicator) async {
    final types = await _safe<List<SlotTypes>?>(
      communicator.getSlotTagTypes,
      null,
    );
    if (!identical(communicator, _communicator)) return;

    if (types == null || types.length < 8) {
      slotsLoaded = false;
      return;
    }

    slotTypes = types;
    enabledSlots = await _safe(
      communicator.getEnabledSlots,
      _defaultEnabledSlots(),
    );
    slotNames = await _safe(communicator.getSlotTagNames, _defaultSlotNames());
    activeSlot = await _safe(communicator.getActiveSlot, 0);
    slotsLoaded = true;
  }

  /// Checks that the firmware supports every command the app relies on, as
  /// the desktop home page does.
  Future<bool> _areCapabilitiesSupported(
    ChameleonCommunicator communicator,
  ) async {
    List<int> capabilities;
    try {
      capabilities = await communicator.getDeviceCapabilities();
    } catch (_) {
      return false;
    }

    return switch (appState.connector?.device) {
      ChameleonDevice.ultra => capabilities.contains(
        ChameleonCommand.mf0UlcAuth.value,
      ),
      ChameleonDevice.lite => capabilities.contains(
        ChameleonCommand.setIdteckEmulatorID.value,
      ),
      _ => true,
    };
  }

  Future<void> activateSlot(int slot) async {
    final communicator = _communicator;
    if (communicator == null || slot == activeSlot) {
      return;
    }

    await communicator.activateSlot(slot);
    activeSlot = slot;
    _notify();
  }

  Future<void> setSlotEnabled(
    int slot,
    TagFrequency frequency,
    bool enabled,
  ) async {
    final communicator = _communicator;
    if (communicator == null) {
      return;
    }

    await communicator.enableSlot(slot, frequency, enabled);
    if (frequency == TagFrequency.hf) {
      enabledSlots[slot].hf = enabled;
    } else {
      enabledSlots[slot].lf = enabled;
    }
    _notify();
  }

  Future<void> refreshReaderMode() async {
    final communicator = _communicator;
    if (communicator == null) {
      return;
    }

    final enabled = await _safe(communicator.isReaderDeviceMode, readerMode);
    if (identical(communicator, _communicator)) {
      readerMode = enabled;
      _notify();
    }
  }

  Future<void> setReaderMode(bool enabled) async {
    final communicator = _communicator;
    if (communicator == null) {
      return;
    }

    await communicator.setReaderDeviceMode(enabled);
    readerMode = enabled;
    _notify();
  }

  /// Uploads a saved card to [slot]. Returns false if the card type can't be
  /// emulated yet; the device is untouched in that case.
  Future<bool> loadCardIntoSlotIndex(
    int slot,
    CardSave card,
    String noName,
  ) async {
    final communicator = _communicator;
    if (communicator == null || isUploading || !canLoadCardIntoSlot(card)) {
      return false;
    }

    uploadProgress = 0;
    _notify();

    try {
      await loadCardIntoSlot(
        communicator,
        slot,
        card,
        noName: noName,
        onProgress: (progress) {
          if (progress != uploadProgress) {
            uploadProgress = progress;
            _notify();
          }
        },
      );
      readerMode = false;
    } finally {
      uploadProgress = -1;
      _notify();
    }

    await refreshSlots();
    return true;
  }

  /// Called by the UI after it changed slot data through a dialog that talks
  /// to the device on its own.
  Future<void> slotsChangedExternally() => refreshSlots();

  @override
  void dispose() {
    _disposed = true;
    appState.removeListener(_onAppStateChanged);
    super.dispose();
  }
}
