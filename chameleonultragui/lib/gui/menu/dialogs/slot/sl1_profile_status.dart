import 'package:flutter/material.dart';
import 'package:chameleonultragui/generated/i18n/app_localizations.dart';
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
  Future<void> run(Future<dynamic> Function() action) async {
    if (!mounted) return;
    final localizations = AppLocalizations.of(context)!;
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
          '${localizations.card_auth_raw_status}: ${Sl1Profile.encodeBytes(status)}\n'
          '${localizations.card_auth_configured}: ${status[2] & 1 != 0}\n'
          '${localizations.enabled}: ${status[2] & 2 != 0}\n'
          '${localizations.card_auth_runtime_enabled}: ${status[2] & 4 != 0}\n'
          '${localizations.card_auth_staged}: ${status[2] & 8 != 0}\n'
          '${localizations.card_auth_stale_binding}: ${status[2] & 16 != 0}\n'
          '${localizations.card_auth_entropy_ready}: ${status[2] & 32 != 0}\n'
          '${localizations.card_auth_incomplete_save}: $incompleteSave\n'
          '${localizations.card_auth_received_blocks}: ${(status[8] << 8) | status[9]}/${(status[10] << 8) | status[11]}\n'
          '${localizations.card_auth_last_status}: ${status[12]}, ${localizations.card_auth_stage}: ${status[13]}\n'
          '${localizations.card_auth_status_rf_hint}';
    } catch (error) {
      statusKnown = false;
      completeStage = false;
      message =
          '${actionError == null ? '' : '$actionError\n\n'}'
          '${localizations.card_auth_status_unavailable}: $error\n'
          '${localizations.card_auth_refresh_required}';
    }
    if (mounted) setState(() => busy = false);
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => run(() async {}));
  }

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context)!;
    return AlertDialog(
      title: Text('${localizations.slot} ${widget.slot + 1} CardAuth'),
      content: SingleChildScrollView(
        child: SelectableText(
          '$message${incompleteSave ? '\n\n${localizations.card_auth_recovery_hint}' : ''}',
        ),
      ),
      actions: [
        if (busy) const CircularProgressIndicator(),
        if (completeStage)
          TextButton(
            onPressed: busy
                ? null
                : () => run(() => widget.uploader.save(widget.slot)),
            child: Text(localizations.card_auth_save_staged),
          ),
        TextButton(
          onPressed: busy ? null : () => run(() async {}),
          child: Text(localizations.refresh),
        ),
        TextButton(
          onPressed: busy || !statusKnown || incompleteSave
              ? null
              : () => run(() => widget.uploader.setEnabled(widget.slot, true)),
          child: Text(localizations.enable),
        ),
        TextButton(
          onPressed: busy || !statusKnown || incompleteSave
              ? null
              : () => run(() => widget.uploader.setEnabled(widget.slot, false)),
          child: Text(localizations.disable),
        ),
        TextButton(
          onPressed: busy
              ? null
              : () => run(() => widget.uploader.cancel(widget.slot)),
          child: Text(localizations.card_auth_cancel_staged),
        ),
        TextButton(
          onPressed: busy || !statusKnown || incompleteSave
              ? null
              : () => run(() => widget.uploader.clear(widget.slot)),
          child: Text(localizations.card_auth_clear),
        ),
        TextButton(
          onPressed: busy ? null : () => Navigator.pop(context),
          child: Text(localizations.close),
        ),
      ],
    );
  }
}
