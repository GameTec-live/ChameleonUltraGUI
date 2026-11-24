import 'package:chameleonultragui/generated/i18n/app_localizations.dart';
import 'package:chameleonultragui/helpers/ble_status.dart';
import 'package:flutter/material.dart';

class ConnectionStatus extends StatelessWidget {
  const ConnectionStatus({
    super.key,
    required this.connected,
    required this.connecting,
  });

  final bool connected;
  final bool connecting;

  String _label(AppLocalizations localizations, BlePhase phase) {
    if (connected) {
      return localizations.status_connected;
    }
    switch (phase) {
      case BlePhase.pinRequired:
        return localizations.status_pin_required;
      case BlePhase.pinError:
        return localizations.status_pin_error;
      case BlePhase.failedRetrying:
        return localizations.status_failed_retrying;
      case BlePhase.connecting:
        return localizations.status_connecting;
      case BlePhase.waiting:
        break;
    }
    return connecting
        ? localizations.status_connecting
        : localizations.status_waiting_for_device;
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<BlePhase>(
      valueListenable: BleStatus.phase,
      builder: (context, phase, _) {
        final localizations = AppLocalizations.of(context)!;
        return Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const SizedBox(
                width: 44,
                height: 44,
                child: CircularProgressIndicator(strokeWidth: 3),
              ),
              const SizedBox(height: 18),
              Text(
                _label(localizations, phase),
                style: const TextStyle(fontSize: 16),
              ),
            ],
          ),
        );
      },
    );
  }
}
