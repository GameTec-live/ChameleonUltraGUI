import 'package:chameleonultragui/gui/mobile/controllers/device_controller.dart';
import 'package:chameleonultragui/helpers/definitions.dart';
import 'package:chameleonultragui/helpers/general.dart';
import 'package:flutter/material.dart';

// Localizations
import 'package:chameleonultragui/generated/i18n/app_localizations.dart';

TagType _slotType(
  MobileDeviceController device,
  int slot,
  TagFrequency frequency,
) => frequency == TagFrequency.hf
    ? device.slotTypes[slot].hf
    : device.slotTypes[slot].lf;

/// "name (type)" for one frequency of a slot, or "Empty".
String slotFrequencyLabel(
  MobileDeviceController device,
  int slot,
  TagFrequency frequency,
  AppLocalizations localizations,
) {
  final type = _slotType(device, slot, frequency);
  if (type == TagType.unknown) {
    return localizations.empty;
  }

  final name =
      (frequency == TagFrequency.hf
              ? device.slotNames[slot].hf
              : device.slotNames[slot].lf)
          .trim();
  final typeName = chameleonTagToString(type, localizations);
  return name.isEmpty ? typeName : '$name ($typeName)';
}

/// Compact numbered tile for the dashboard's eight-slot grid.
class SlotGridTile extends StatelessWidget {
  const SlotGridTile({
    super.key,
    required this.slot,
    required this.device,
    required this.onTap,
    required this.onLongPress,
  });

  final int slot;
  final MobileDeviceController device;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final localizations = AppLocalizations.of(context)!;
    final active = device.activeSlot == slot;
    final types = device.slotTypes[slot];
    final enabled = device.enabledSlots[slot];

    return Semantics(
      button: true,
      selected: active,
      label: '${localizations.slot} ${slot + 1}',
      child: Material(
        color: active ? scheme.primaryContainer : scheme.surfaceContainerHigh,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: active
              ? BorderSide(color: scheme.primary, width: 2)
              : BorderSide.none,
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          onLongPress: onLongPress,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 72),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    '${slot + 1}',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      color: active
                          ? scheme.onPrimaryContainer
                          : scheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.credit_card,
                        size: 16,
                        color: types.hf == TagType.unknown
                            ? scheme.outlineVariant
                            : (enabled.hf ? scheme.primary : scheme.outline),
                      ),
                      const SizedBox(width: 6),
                      Icon(
                        Icons.wifi,
                        size: 16,
                        color: types.lf == TagType.unknown
                            ? scheme.outlineVariant
                            : (enabled.lf ? scheme.primary : scheme.outline),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Full slot entry for the slot manager list.
class SlotCard extends StatelessWidget {
  const SlotCard({
    super.key,
    required this.slot,
    required this.device,
    required this.onTap,
    required this.onToggle,
  });

  final int slot;
  final MobileDeviceController device;
  final VoidCallback onTap;
  final void Function(TagFrequency frequency, bool enabled) onToggle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final localizations = AppLocalizations.of(context)!;
    final active = device.activeSlot == slot;

    Widget row(TagFrequency frequency) {
      final type = _slotType(device, slot, frequency);
      final isEnabled = frequency == TagFrequency.hf
          ? device.enabledSlots[slot].hf
          : device.enabledSlots[slot].lf;
      final empty = type == TagType.unknown;

      return Row(
        children: [
          Icon(
            frequency == TagFrequency.hf ? Icons.credit_card : Icons.wifi,
            size: 20,
            color: empty ? scheme.outline : scheme.primary,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                slotFrequencyLabel(device, slot, frequency, localizations),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: empty
                    ? theme.textTheme.bodyMedium?.copyWith(
                        color: scheme.onSurfaceVariant,
                      )
                    : theme.textTheme.bodyMedium,
              ),
            ),
          ),
          Switch(
            value: isEnabled,
            onChanged: empty || device.isUploading
                ? null
                : (v) => onToggle(frequency, v),
          ),
        ],
      );
    }

    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      color: active ? scheme.primaryContainer : null,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '${localizations.slot} ${slot + 1}',
                      style: theme.textTheme.titleMedium,
                    ),
                  ),
                  if (active)
                    Chip(
                      avatar: const Icon(Icons.check_circle, size: 18),
                      label: Text(localizations.active_slot),
                      visualDensity: VisualDensity.compact,
                    ),
                  const Icon(Icons.more_vert),
                  const SizedBox(width: 8),
                ],
              ),
              row(TagFrequency.hf),
              row(TagFrequency.lf),
            ],
          ),
        ),
      ),
    );
  }
}
