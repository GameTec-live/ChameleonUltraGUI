import 'package:chameleonultragui/connector/serial_abstract.dart';
import 'package:chameleonultragui/generated/i18n/app_localizations.dart';
import 'package:chameleonultragui/helpers/definitions.dart';
import 'package:chameleonultragui/helpers/general.dart';
import 'package:chameleonultragui/sharedprefsprovider.dart';
import 'package:flutter/material.dart';

const String _mono = 'RobotoMono';

/// Everything the home overview needs. Loaded once by [HomePage].
class HomeViewData {
  final String deviceName;
  final ChameleonDevice device;
  final ConnectionType connectionType;
  final String portName;
  final int batteryPercent;
  final String firmwareVersion;
  final String firmwareCommit;
  final bool updateAvailable;
  final bool isReaderMode;
  final bool isDemo;
  final bool capabilitiesSupported;
  final int activeSlot;
  final bool slotsReady;
  final List<SlotTypes> slotTypes;
  final List<SlotNames> slotNames;
  final List<EnabledSlotInfo> enabledSlots;
  final List<CardSave> recentCards;

  const HomeViewData({
    required this.deviceName,
    required this.device,
    required this.connectionType,
    required this.portName,
    required this.batteryPercent,
    required this.firmwareVersion,
    required this.firmwareCommit,
    required this.updateAvailable,
    required this.isReaderMode,
    required this.isDemo,
    required this.capabilitiesSupported,
    required this.activeSlot,
    required this.slotsReady,
    required this.slotTypes,
    required this.slotNames,
    required this.enabledSlots,
    required this.recentCards,
  });

  factory HomeViewData.placeholder() {
    return HomeViewData(
      deviceName: '—',
      device: ChameleonDevice.ultra,
      connectionType: ConnectionType.none,
      portName: '—',
      batteryPercent: -1,
      firmwareVersion: '—',
      firmwareCommit: '',
      updateAvailable: false,
      isReaderMode: false,
      isDemo: false,
      capabilitiesSupported: true,
      activeSlot: 0,
      slotsReady: false,
      slotTypes: List.generate(8, (_) => SlotTypes()),
      slotNames: List.generate(8, (_) => SlotNames()),
      enabledSlots: List.generate(
        8,
        (_) => EnabledSlotInfo(hf: true, lf: true),
      ),
      recentCards: const [],
    );
  }

  HomeViewData copyWith({int? activeSlot, bool? isReaderMode}) {
    return HomeViewData(
      deviceName: deviceName,
      device: device,
      connectionType: connectionType,
      portName: portName,
      batteryPercent: batteryPercent,
      firmwareVersion: firmwareVersion,
      firmwareCommit: firmwareCommit,
      updateAvailable: updateAvailable,
      isReaderMode: isReaderMode ?? this.isReaderMode,
      isDemo: isDemo,
      capabilitiesSupported: capabilitiesSupported,
      activeSlot: activeSlot ?? this.activeSlot,
      slotsReady: slotsReady,
      slotTypes: slotTypes,
      slotNames: slotNames,
      enabledSlots: enabledSlots,
      recentCards: recentCards,
    );
  }
}

class HomeOverview extends StatelessWidget {
  const HomeOverview({
    super.key,
    required this.data,
    required this.loading,
    this.onSelectSlot,
    this.onOpenSavedCards,
    this.onSettings,
    this.onDisconnect,
    this.onToggleReaderMode,
    this.onUpdate,
    this.onCopy,
  });

  final HomeViewData data;
  final bool loading;
  final ValueChanged<int>? onSelectSlot;
  final VoidCallback? onOpenSavedCards;
  final VoidCallback? onSettings;
  final VoidCallback? onDisconnect;
  final VoidCallback? onToggleReaderMode;
  final VoidCallback? onUpdate;
  final ValueChanged<String>? onCopy;

  @override
  Widget build(BuildContext context) {
    final palette = _HomePalette.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 900;
        final medium = constraints.maxWidth >= 600 && !wide;
        final phone = constraints.maxWidth < 600;
        final padding = phone ? 16.0 : 24.0;

        final content = wide
            ? _desktop(context, palette)
            : medium
            ? _medium(context, palette)
            : _phone(context, palette);

        return SingleChildScrollView(
          padding: EdgeInsets.all(padding),
          child: Align(
            alignment: Alignment.topLeft,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1100),
              child: content,
            ),
          ),
        );
      },
    );
  }

  Widget _desktop(BuildContext context, _HomePalette p) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(width: 300, child: _devicePanel(context, p, imageHeight: 220)),
        const SizedBox(width: 24),
        Expanded(child: _rightColumn(context, p, compact: false)),
      ],
    );
  }

  Widget _medium(BuildContext context, _HomePalette p) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(width: 240, child: _devicePanel(context, p, imageHeight: 200)),
        const SizedBox(width: 16),
        Expanded(child: _rightColumn(context, p, compact: true)),
      ],
    );
  }

  Widget _phone(BuildContext context, _HomePalette p) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _phoneHeader(context, p),
        const SizedBox(height: 16),
        _currentSlot(context, p, compact: true),
        const SizedBox(height: 16),
        _slotGrid(context, p, columns: 2, tileHeight: 56),
        if (data.recentCards.isNotEmpty) ...[
          const SizedBox(height: 16),
          _recentCards(context, p),
        ],
      ],
    );
  }

  Widget _rightColumn(
    BuildContext context,
    _HomePalette p, {
    required bool compact,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _sectionTitle(AppLocalizations.of(context)!.current_slot),
        const SizedBox(height: 8),
        _currentSlot(context, p, compact: compact),
        const SizedBox(height: 16),
        _slotGrid(context, p, columns: 4, tileHeight: compact ? 56 : 64),
        if (data.recentCards.isNotEmpty) ...[
          const SizedBox(height: 16),
          _recentCards(context, p),
        ],
      ],
    );
  }

  Widget _phoneHeader(BuildContext context, _HomePalette p) {
    final l = AppLocalizations.of(context)!;
    final image = data.device == ChameleonDevice.lite
        ? 'assets/black-lite-standing-front.webp'
        : 'assets/black-ultra-standing-front.webp';

    return KeyedSubtree(
      key: const ValueKey('home_phone_card'),
      child: _Panel(
        palette: p,
        padding: const EdgeInsets.all(16),
        child: LayoutBuilder(
          builder: (context, constraints) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  key: const ValueKey('home_phone_top'),
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    SizedBox(
                      key: const ValueKey('home_phone_image'),
                      height: 96,
                      child: Image.asset(
                        image,
                        height: 96,
                        fit: BoxFit.contain,
                        errorBuilder: (_, __, ___) =>
                            Image.asset(image, fit: BoxFit.contain),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _PhoneModelText(name: data.deviceName),
                          const SizedBox(height: 8),
                          _connectionAndBattery(context, p),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Divider(height: 1, color: p.border),
                const SizedBox(height: 12),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        data.firmwareVersion,
                        key: const ValueKey('home_phone_firmware'),
                        softWrap: true,
                        style: TextStyle(
                          fontFamily: _mono,
                          fontSize: 12,
                          color: p.secondary,
                        ),
                      ),
                    ),
                    _iconAction(
                      context,
                      p,
                      widgetKey: const ValueKey('home_phone_refresh'),
                      icon: Icons.refresh,
                      tooltip: l.check_updates,
                      onTap: onUpdate,
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Divider(height: 1, color: p.border),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: FittedBox(
                        alignment: Alignment.centerLeft,
                        fit: BoxFit.scaleDown,
                        child: Text(
                          data.portName.isEmpty ? '—' : data.portName,
                          key: const ValueKey('home_phone_mac'),
                          style: TextStyle(
                            fontFamily: _mono,
                            fontSize: 12,
                            color: p.secondary,
                          ),
                        ),
                      ),
                    ),
                    _iconAction(
                      context,
                      p,
                      widgetKey: const ValueKey('home_phone_copy'),
                      icon: Icons.copy,
                      tooltip: l.copy,
                      onTap: data.portName == '—' || onCopy == null
                          ? null
                          : () => onCopy!(data.portName),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Divider(height: 1, color: p.border),
                const SizedBox(height: 12),
                Wrap(
                  alignment: WrapAlignment.spaceEvenly,
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _iconAction(
                      context,
                      p,
                      widgetKey: const ValueKey('home_phone_mode'),
                      icon: data.isReaderMode
                          ? Icons.nfc
                          : Icons.barcode_reader,
                      tooltip: data.isReaderMode
                          ? l.emulator_mode
                          : l.reader_mode,
                      onTap: onToggleReaderMode,
                    ),
                    _iconAction(
                      context,
                      p,
                      widgetKey: const ValueKey('home_phone_settings'),
                      icon: Icons.settings,
                      tooltip: l.device_settings,
                      onTap: onSettings,
                    ),
                    _iconAction(
                      context,
                      p,
                      widgetKey: const ValueKey('home_phone_disconnect'),
                      icon: Icons.link_off,
                      tooltip: l.disconnect,
                      onTap: onDisconnect,
                    ),
                  ],
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _devicePanel(
    BuildContext context,
    _HomePalette p, {
    required double imageHeight,
  }) {
    final l = AppLocalizations.of(context)!;
    final image = data.device == ChameleonDevice.lite
        ? 'assets/black-lite-standing-front.webp'
        : 'assets/black-ultra-standing-front.webp';

    return _Panel(
      palette: p,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Column(
              children: [
                SizedBox(
                  height: imageHeight,
                  child: Image.asset(
                    image,
                    fit: BoxFit.contain,
                    errorBuilder: (_, __, ___) =>
                        Image.asset(image, fit: BoxFit.contain),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Text(
            data.deviceName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          _connectionAndBattery(context, p),
          const SizedBox(height: 8),
          _copyLine(context, p, data.portName, maxLines: 1, fontSize: 12),
          const SizedBox(height: 4),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l.firmware_version,
                      style: TextStyle(fontSize: 12, color: p.secondary),
                    ),
                    const SizedBox(height: 2),
                    _monoText(
                      data.firmwareVersion,
                      color: p.secondary,
                      fontSize: 12,
                      maxLines: 1,
                    ),
                  ],
                ),
              ),
              _iconAction(
                context,
                p,
                icon: Icons.refresh,
                tooltip: l.check_updates,
                onTap: onUpdate,
              ),
            ],
          ),
          if (data.updateAvailable)
            SizedBox(
              height: 48,
              child: InkWell(
                borderRadius: BorderRadius.circular(6),
                hoverColor: p.hover,
                onTap: onUpdate,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 6,
                        height: 6,
                        decoration: BoxDecoration(
                          color: p.accent,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        l.update_available,
                        style: TextStyle(fontSize: 12, color: p.accent),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          const SizedBox(height: 8),
          Container(height: 1, color: p.border),
          const SizedBox(height: 8),
          Row(
            children: [
              _iconAction(
                context,
                p,
                icon: data.isReaderMode ? Icons.nfc : Icons.barcode_reader,
                tooltip: data.isReaderMode ? l.emulator_mode : l.reader_mode,
                onTap: onToggleReaderMode,
              ),
              const SizedBox(width: 8),
              _iconAction(
                context,
                p,
                icon: Icons.settings,
                tooltip: l.device_settings,
                onTap: onSettings,
              ),
              const SizedBox(width: 8),
              _iconAction(
                context,
                p,
                icon: Icons.link_off,
                tooltip: l.disconnect,
                onTap: onDisconnect,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _connectionAndBattery(BuildContext context, _HomePalette p) {
    final l = AppLocalizations.of(context)!;
    final percent = data.batteryPercent;
    final low = percent >= 0 && percent < 20;
    final color = low ? p.error : p.secondary;
    final icon = _batteryIcon(percent);

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        _Chip(
          palette: p,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                data.connectionType == ConnectionType.ble
                    ? Icons.bluetooth
                    : Icons.usb,
                size: 14,
                color: p.secondary,
              ),
              const SizedBox(width: 4),
              Text(
                data.connectionType == ConnectionType.ble ? l.bluetooth : l.usb,
                style: TextStyle(fontSize: 12, color: p.secondary),
              ),
            ],
          ),
        ),
        _Chip(
          palette: p,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 15, color: color),
              const SizedBox(width: 4),
              Text(
                percent < 0 ? '—' : '$percent%',
                style: TextStyle(fontSize: 12, color: color),
              ),
              if (percent >= 0) ...[
                const SizedBox(width: 6),
                ClipRRect(
                  borderRadius: BorderRadius.circular(2),
                  child: SizedBox(
                    width: 48,
                    height: 3,
                    child: LinearProgressIndicator(
                      value: (percent / 100).clamp(0, 1),
                      backgroundColor: p.border,
                      valueColor: AlwaysStoppedAnimation<Color>(color),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _currentSlot(
    BuildContext context,
    _HomePalette p, {
    required bool compact,
  }) {
    final l = AppLocalizations.of(context)!;
    final index = data.activeSlot.clamp(0, 7);
    final ready = data.slotsReady;
    final types = ready ? data.slotTypes[index] : SlotTypes();
    final name = ready
        ? (data.slotNames[index].hf.isNotEmpty
              ? data.slotNames[index].hf
              : data.slotNames[index].lf.isNotEmpty
              ? data.slotNames[index].lf
              : l.no_name)
        : '';

    return _Panel(
      palette: p,
      padding: const EdgeInsets.all(16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!ready)
            _skeleton(p, width: compact ? 48 : 56, height: compact ? 48 : 56)
          else
            Container(
              width: compact ? 48 : 56,
              height: compact ? 48 : 56,
              decoration: BoxDecoration(
                border: Border.all(color: p.accent, width: 1.5),
                borderRadius: BorderRadius.circular(8),
              ),
              alignment: Alignment.center,
              child: Text(
                '${index + 1}',
                style: TextStyle(
                  fontFamily: _mono,
                  fontSize: compact ? 20 : 24,
                  color: p.accent,
                ),
              ),
            ),
          const SizedBox(width: 16),
          Expanded(
            child: !ready
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _skeleton(p, width: 160, height: 16),
                      const SizedBox(height: 8),
                      _skeleton(p, width: 120, height: 12),
                      const SizedBox(height: 8),
                      _skeleton(p, width: 180, height: 12),
                    ],
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          _typeTag(
                            context,
                            p,
                            '${l.hf} ${types.hf == TagType.unknown ? l.empty : chameleonTagToString(types.hf, l)}',
                          ),
                          _typeTag(
                            context,
                            p,
                            '${l.lf} ${types.lf == TagType.unknown ? l.empty : chameleonTagToString(types.lf, l)}',
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Text(
                            'UID',
                            style: TextStyle(fontSize: 12, color: p.secondary),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: _monoText(
                              '—',
                              color: p.secondary,
                              fontSize: 12,
                              maxLines: 1,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _slotGrid(
    BuildContext context,
    _HomePalette p, {
    required int columns,
    required double tileHeight,
  }) {
    final l = AppLocalizations.of(context)!;
    final ready = data.slotsReady;
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: 8,
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: columns,
        mainAxisSpacing: 8,
        crossAxisSpacing: 8,
        mainAxisExtent: tileHeight,
      ),
      itemBuilder: (context, index) {
        if (!ready) {
          return _Panel(
            palette: p,
            radius: 8,
            padding: const EdgeInsets.all(10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _skeleton(p, width: 20, height: 10),
                const SizedBox(height: 8),
                _skeleton(p, width: 44, height: 8),
              ],
            ),
          );
        }

        final types = data.slotTypes[index];
        final empty =
            types.hf == TagType.unknown && types.lf == TagType.unknown;
        final disabled =
            index < data.enabledSlots.length && !data.enabledSlots[index].any();
        final inactive = empty || disabled;
        final selected = index == data.activeSlot;
        final dim = inactive ? 0.4 : 1.0;
        final child = Container(
          decoration: BoxDecoration(
            color: p.panel,
            borderRadius: BorderRadius.circular(8),
            border: selected
                ? Border.all(color: p.accent, width: 1.5)
                : Border.all(color: p.border),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                '${index + 1}',
                maxLines: 1,
                style: TextStyle(
                  fontFamily: _mono,
                  fontSize: 13,
                  height: 1.1,
                  color: selected ? p.accent : p.primaryText,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                _slotAbbreviation(types),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 10,
                  height: 1.1,
                  color: selected ? p.accent : p.secondary,
                ),
              ),
            ],
          ),
        );

        return Semantics(
          button: true,
          label: '${l.slot} ${index + 1}',
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(8),
              hoverColor: p.hover,
              splashColor: p.hover,
              onTap: onSelectSlot == null ? null : () => onSelectSlot!(index),
              child: Opacity(
                opacity: dim,
                child: inactive
                    ? CustomPaint(
                        foregroundPainter: _DashedBorderPainter(
                          color: p.border,
                          radius: 8,
                        ),
                        child: child,
                      )
                    : child,
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _recentCards(BuildContext context, _HomePalette p) {
    final l = AppLocalizations.of(context)!;
    final cards = data.recentCards.take(3).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle(l.recent_cards),
        const SizedBox(height: 8),
        _Panel(
          palette: p,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: Column(
            children: [
              for (var i = 0; i < cards.length; i++) ...[
                if (i > 0) Divider(height: 1, color: p.border),
                SizedBox(
                  height: 56,
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              cards[i].name.isEmpty ? l.no_name : cards[i].name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              chameleonTagToString(cards[i].tag, l),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 12,
                                color: p.secondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 10),
                      Flexible(
                        child: _monoText(
                          cards[i].uid.isEmpty ? '—' : cards[i].uid,
                          color: p.secondary,
                          fontSize: 12,
                          maxLines: 1,
                        ),
                      ),
                      const SizedBox(width: 4),
                      _iconAction(
                        context,
                        p,
                        icon: Icons.chevron_right,
                        tooltip: l.saved_cards,
                        onTap: onOpenSavedCards,
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _sectionTitle(String text) {
    return Text(
      text,
      style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
    );
  }

  Widget _typeTag(BuildContext context, _HomePalette p, String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        border: Border.all(color: p.border),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(text, style: TextStyle(fontSize: 12, color: p.secondary)),
    );
  }

  Widget _copyLine(
    BuildContext context,
    _HomePalette p,
    String text, {
    required int maxLines,
    required double fontSize,
  }) {
    final l = AppLocalizations.of(context)!;
    return Tooltip(
      message: l.copy,
      child: InkWell(
        borderRadius: BorderRadius.circular(6),
        hoverColor: p.hover,
        onTap: text == '—' || onCopy == null ? null : () => onCopy!(text),
        child: SizedBox(
          height: 48,
          child: Row(
            children: [
              Expanded(
                child: _monoText(
                  text.isEmpty ? '—' : text,
                  color: p.secondary,
                  fontSize: fontSize,
                  maxLines: maxLines,
                ),
              ),
              Icon(Icons.copy, size: 13, color: p.secondary),
            ],
          ),
        ),
      ),
    );
  }

  Widget _monoText(
    String text, {
    required Color color,
    required double fontSize,
    required int maxLines,
  }) {
    return Text(
      text,
      maxLines: maxLines,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(fontFamily: _mono, fontSize: fontSize, color: color),
    );
  }

  Widget _skeleton(
    _HomePalette p, {
    required double width,
    required double height,
  }) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: p.border.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(4),
      ),
    );
  }

  Widget _iconAction(
    BuildContext context,
    _HomePalette p, {
    required IconData icon,
    required String tooltip,
    Key? widgetKey,
    VoidCallback? onTap,
    Color? color,
  }) {
    return Tooltip(
      message: tooltip,
      child: SizedBox(
        key: widgetKey,
        width: 48,
        height: 48,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(6),
            hoverColor: p.hover,
            splashColor: p.hover,
            onTap: onTap,
            child: Icon(icon, size: 20, color: color ?? p.accent),
          ),
        ),
      ),
    );
  }
}

class _PhoneModelText extends StatelessWidget {
  const _PhoneModelText({required this.name});

  final String name;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final scaler = MediaQuery.textScalerOf(context);
        final direction = Directionality.of(context);
        var fontSize = 20.0;
        while (fontSize > 16) {
          final painter = TextPainter(
            text: TextSpan(
              text: name,
              style: TextStyle(fontSize: fontSize, fontWeight: FontWeight.w600),
            ),
            maxLines: 2,
            textDirection: direction,
            textScaler: scaler,
          )..layout(maxWidth: constraints.maxWidth);
          final exceeded = painter.didExceedMaxLines;
          painter.dispose();
          if (!exceeded) {
            break;
          }
          fontSize -= 1;
        }
        return Text(
          name,
          key: const ValueKey('home_phone_model'),
          maxLines: 2,
          softWrap: true,
          overflow: TextOverflow.visible,
          style: TextStyle(fontSize: fontSize, fontWeight: FontWeight.w600),
        );
      },
    );
  }
}

class _Panel extends StatelessWidget {
  const _Panel({
    required this.palette,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.radius = 12,
  });

  final _HomePalette palette;
  final Widget child;
  final EdgeInsets padding;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: palette.panel,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: palette.border),
      ),
      child: child,
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.palette, required this.child});

  final _HomePalette palette;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        border: Border.all(color: palette.border),
        borderRadius: BorderRadius.circular(6),
      ),
      child: child,
    );
  }
}

class _HomePalette {
  const _HomePalette({
    required this.page,
    required this.panel,
    required this.border,
    required this.primaryText,
    required this.secondary,
    required this.error,
    required this.accent,
    required this.hover,
  });

  final Color page;
  final Color panel;
  final Color border;
  final Color primaryText;
  final Color secondary;
  final Color error;
  final Color accent;
  final Color hover;

  factory _HomePalette.of(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return _HomePalette(
      page: scheme.surface,
      panel: scheme.surfaceContainerLow,
      border: scheme.outlineVariant,
      primaryText: scheme.onSurface,
      secondary: scheme.onSurfaceVariant,
      error: scheme.error,
      accent: scheme.primary,
      hover: scheme.onSurface.withValues(alpha: 0.06),
    );
  }
}

class _DashedBorderPainter extends CustomPainter {
  const _DashedBorderPainter({required this.color, required this.radius});

  final Color color;
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    final path = Path()
      ..addRRect(
        RRect.fromRectAndRadius(Offset.zero & size, Radius.circular(radius)),
      );
    const dash = 5.0;
    const gap = 4.0;
    for (final metric in path.computeMetrics()) {
      var distance = 0.0;
      while (distance < metric.length) {
        canvas.drawPath(metric.extractPath(distance, distance + dash), paint);
        distance += dash + gap;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DashedBorderPainter oldDelegate) {
    return oldDelegate.color != color || oldDelegate.radius != radius;
  }
}

IconData _batteryIcon(int percent) {
  if (percent < 0) return Icons.battery_unknown;
  if (percent > 98) return Icons.battery_full;
  if (percent > 87) return Icons.battery_6_bar;
  if (percent > 75) return Icons.battery_5_bar;
  if (percent > 62) return Icons.battery_4_bar;
  if (percent > 50) return Icons.battery_3_bar;
  if (percent > 37) return Icons.battery_2_bar;
  if (percent > 10) return Icons.battery_1_bar;
  if (percent > 3) return Icons.battery_0_bar;
  return Icons.battery_alert;
}

String _slotAbbreviation(SlotTypes types) {
  final hf = _tagAbbreviation(types.hf);
  final lf = _tagAbbreviation(types.lf);
  if (hf.isNotEmpty && lf.isNotEmpty) return '$hf+$lf';
  if (hf.isNotEmpty) return hf;
  if (lf.isNotEmpty) return lf;
  return '—';
}

String _tagAbbreviation(TagType tag) {
  return switch (tag) {
    TagType.mifareMini => 'Mini',
    TagType.mifare1K => 'M1K',
    TagType.mifare2K => 'M2K',
    TagType.mifare4K => 'M4K',
    TagType.ntag210 => 'N210',
    TagType.ntag212 => 'N212',
    TagType.ntag213 => 'N213',
    TagType.ntag215 => 'N215',
    TagType.ntag216 => 'N216',
    TagType.ultralight => 'UL',
    TagType.ultralightC => 'ULC',
    TagType.ultralight11 => 'UL11',
    TagType.ultralight21 => 'UL21',
    TagType.hf14a4 => 'ISO4',
    TagType.em410X => 'EM',
    TagType.em410X16 => 'EM16',
    TagType.em410X32 => 'EM32',
    TagType.em410X64 => 'EM64',
    TagType.em410XElectra => 'EME',
    TagType.hidProx => 'HID',
    TagType.pac => 'PAC',
    TagType.viking => 'VKG',
    TagType.jablotron => 'JAB',
    TagType.ioProx => 'IO',
    TagType.idteck => 'IDT',
    _ => '',
  };
}
