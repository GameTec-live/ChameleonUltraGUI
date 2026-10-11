import 'package:chameleonultragui/gui/mobile/widgets/message_view.dart';
import 'package:chameleonultragui/gui/page/write_card.dart';
import 'package:chameleonultragui/main.dart';
import 'package:chameleonultragui/sharedprefsprovider.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

// Localizations
import 'package:chameleonultragui/generated/i18n/app_localizations.dart';

/// Full-screen entry point for writing a saved card to a magic card.
///
/// Reuses the existing write workflow; this wrapper only adds the
/// device-required state and an optional preselected [card].
class MobileWriterPage extends StatelessWidget {
  const MobileWriterPage({super.key, this.card});

  final CardSave? card;

  @override
  Widget build(BuildContext context) {
    final connected = context.select<ChameleonGUIState, bool>(
      (s) =>
          s.connector != null && s.connector!.connected && !s.connector!.isDFU,
    );
    final localizations = AppLocalizations.of(context)!;

    if (!connected) {
      return Scaffold(
        appBar: AppBar(title: Text(localizations.write_card)),
        body: MessageView(
          icon: Icons.usb_off,
          title: localizations.connect_device_to_use,
          actions: [
            FilledButton(
              onPressed: () => Navigator.of(context).maybePop(),
              child: Text(localizations.go_to_device),
            ),
          ],
        ),
      );
    }

    return WriteCardPage(initialCard: card);
  }
}
