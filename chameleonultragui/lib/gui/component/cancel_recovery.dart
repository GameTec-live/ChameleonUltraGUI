import 'package:chameleonultragui/generated/i18n/app_localizations.dart';
import 'package:chameleonultragui/helpers/recovery_operation.dart';
import 'package:flutter/material.dart';

/// A secondary action next to progress, independent of the primary button row.
class CancelRecovery extends StatefulWidget {
  final RecoveryOperation operation;
  const CancelRecovery({super.key, required this.operation});

  @override
  State<CancelRecovery> createState() => _CancelRecoveryState();
}

class _CancelRecoveryState extends State<CancelRecovery> {
  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    return Align(
      alignment: Alignment.centerRight,
      child: TextButton.icon(
        onPressed: widget.operation.isCancelling
            ? null
            : () async {
                final operation = widget.operation;
                final generation = operation.generation;
                final confirmed = await showDialog<bool>(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: Text(l.cancel_recovery_title),
                    content: Text(l.cancel_recovery_message),
                    actions: [
                      TextButton(
                          onPressed: () => Navigator.pop(context, false),
                          child: Text(l.continue_recovery)),
                      TextButton(
                          onPressed: () => Navigator.pop(context, true),
                          child: Text(l.cancel)),
                    ],
                  ),
                );
                if (confirmed == true &&
                    mounted &&
                    operation.isRunning &&
                    operation.generation == generation) {
                  setState(operation.cancel);
                }
              },
        icon: const Icon(Icons.close, size: 18),
        label: Text(
            widget.operation.isCancelling ? l.cancelling_recovery : l.cancel),
      ),
    );
  }
}
