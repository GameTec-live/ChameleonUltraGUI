import 'package:flutter/material.dart';
import 'package:chameleonultragui/helpers/sl1_profile_uploader.dart';
import 'package:chameleonultragui/helpers/sl1_profile.dart';

class Sl1SlotDialog extends StatefulWidget {
  final int slot;
  final Sl1Uploader uploader;
  const Sl1SlotDialog({super.key, required this.slot, required this.uploader});
  @override
  State<Sl1SlotDialog> createState() => _Sl1SlotDialogState();
}

class _Sl1SlotDialogState extends State<Sl1SlotDialog> {
  String message = '';
  bool busy = false;
  bool completeStage = false;
  bool incompleteSave = false;
  bool statusKnown = false;
  static const recoveryExplanation =
      'An incomplete profile save is pending. Enable, Disable and Clear cannot recover it. Upload a complete profile again, or explicitly retry Save staged profile if the complete volatile stage is still available. Cancel discards only the volatile stage; it does not repair the incomplete save.';
  Future<void> run(Future<dynamic> Function() action) async {
    if (!mounted) return;
    setState(() => busy = true);
    Object? actionError;
    try {
      await action();
    } catch (error) {
      actionError = error;
    }
    // Persistence failures can change durable state. Always query separately,
    // while retaining the action's original error and never retrying it.
    try {
      final status = await widget.uploader.status(widget.slot);
      if (status.length != 14 || status[0] != 1 || status[1] != widget.slot) {
        throw const FormatException('Malformed SL1 status');
      }
      statusKnown = true;
      completeStage = Sl1Uploader.hasCompleteStage(status);
      incompleteSave = status[2] & 0x40 != 0;
      message =
          '${actionError == null ? '' : '$actionError\n\n'}'
          'Raw status: ${Sl1Profile.encodeBytes(status)}\nConfigured: ${status[2] & 1 != 0}\nEnabled: ${status[2] & 2 != 0}\nRuntime enabled: ${status[2] & 4 != 0}\nStaged: ${status[2] & 8 != 0}\nStale/corrupt binding: ${status[2] & 16 != 0}\nEntropy ready: ${status[2] & 32 != 0}\nIncomplete save: $incompleteSave\nReceived blocks: ${(status[8] << 8) | status[9]}/${(status[10] << 8) | status[11]}\nLast status: ${status[12]}, stage: ${status[13]}\nThis status does not verify RF authentication.';
    } catch (error) {
      statusKnown = false;
      completeStage = false;
      message =
          '${actionError == null ? '' : '$actionError\n\n'}Status unavailable: $error\nRefresh status before using persistent controls.';
    }
    if (mounted) setState(() => busy = false);
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => run(() async {}));
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text('Slot ${widget.slot + 1} CardAuth'),
    content: SingleChildScrollView(
      child: SelectableText(
        '$message${incompleteSave ? '\n\n$recoveryExplanation' : ''}',
      ),
    ),
    actions: [
      if (busy) const CircularProgressIndicator(),
      if (completeStage)
        TextButton(
          onPressed: busy
              ? null
              : () => run(() => widget.uploader.save(widget.slot)),
          child: const Text('Save staged profile'),
        ),
      TextButton(
        onPressed: busy ? null : () => run(() async {}),
        child: const Text('Refresh'),
      ),
      TextButton(
        onPressed: busy || !statusKnown || incompleteSave
            ? null
            : () => run(() => widget.uploader.setEnabled(widget.slot, true)),
        child: const Text('Enable'),
      ),
      TextButton(
        onPressed: busy || !statusKnown || incompleteSave
            ? null
            : () => run(() => widget.uploader.setEnabled(widget.slot, false)),
        child: const Text('Disable'),
      ),
      TextButton(
        onPressed: busy
            ? null
            : () => run(() => widget.uploader.cancel(widget.slot)),
        child: const Text('Cancel staged upload'),
      ),
      TextButton(
        onPressed: busy || !statusKnown || incompleteSave
            ? null
            : () => run(() => widget.uploader.clear(widget.slot)),
        child: const Text('Clear CardAuth'),
      ),
      TextButton(
        onPressed: busy ? null : () => Navigator.pop(context),
        child: const Text('Close'),
      ),
    ],
  );
}
