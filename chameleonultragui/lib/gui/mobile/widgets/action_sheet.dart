import 'package:flutter/material.dart';

class SheetAction {
  const SheetAction({
    required this.icon,
    required this.label,
    required this.onTap,
    this.enabled = true,
    this.destructive = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool enabled;
  final bool destructive;
}

/// Contextual actions in a modal bottom sheet. The sheet closes before the
/// chosen action runs, so actions can freely open dialogs or routes.
Future<void> showActionSheet(
  BuildContext context, {
  required String title,
  String? subtitle,
  required List<SheetAction> actions,
}) {
  return showModalBottomSheet<void>(
    context: context,
    useSafeArea: true,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (sheetContext) {
      final theme = Theme.of(sheetContext);

      return SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: theme.textTheme.titleLarge),
                  if (subtitle != null)
                    Text(
                      subtitle,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                ],
              ),
            ),
            for (final action in actions)
              ListTile(
                minTileHeight: 56,
                enabled: action.enabled,
                leading: Icon(
                  action.icon,
                  color: action.destructive && action.enabled
                      ? theme.colorScheme.error
                      : null,
                ),
                title: Text(
                  action.label,
                  style: action.destructive && action.enabled
                      ? TextStyle(color: theme.colorScheme.error)
                      : null,
                ),
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  action.onTap();
                },
              ),
            const SizedBox(height: 8),
          ],
        ),
      );
    },
  );
}
