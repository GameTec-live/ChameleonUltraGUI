import 'package:chameleonultragui/generated/i18n/app_localizations.dart';
import 'package:chameleonultragui/helpers/definitions.dart';
import 'package:chameleonultragui/helpers/general.dart';
import 'package:chameleonultragui/main.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

/// Inspects every card record returned by scan-keep. Selection is local:
/// firmware commands that rescan cannot be targeted using this selection.
class HfSelectionMenu extends StatefulWidget {
  const HfSelectionMenu({super.key});

  @override
  State<HfSelectionMenu> createState() => _HfSelectionMenuState();
}

class _HfSelectionMenuState extends State<HfSelectionMenu> {
  List<CardData> _cards = [];
  int? _selected;
  bool _busy = false;
  String? _message;

  Future<void> _scan() async {
    final l = AppLocalizations.of(context)!;
    final communicator = context.read<ChameleonGUIState>().communicator;
    if (communicator == null) return;
    setState(() {
      _busy = true;
      _cards = [];
      _selected = null;
      _message = null;
    });
    try {
      final capabilities = await communicator.getDeviceCapabilities();
      if (!capabilities.contains(ChameleonCommand.hf14aScanKeep.value)) {
        if (mounted) setState(() => _message = l.hf_tool_unsupported);
        return;
      }
      if (!await communicator.isReaderDeviceMode()) {
        await communicator.setReaderDeviceMode(true);
      }
      final List<CardData> cards;
      try {
        cards = await communicator.scan14443aTagKeep();
      } finally {
        // Scan-keep leaves the antenna powered, even when no records arrive.
        await communicator.hf14aSetFieldOff();
      }
      if (!mounted) return;
      setState(() {
        _cards = cards;
        _selected = cards.isEmpty ? null : 0;
        if (cards.isEmpty) _message = l.hf_selection_empty;
      });
    } catch (error) {
      if (mounted) setState(() => _message = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final card = _selected == null ? null : _cards[_selected!];
    return PopScope(
      canPop: !_busy,
      child: AlertDialog(
        title: Text(l.hf_selection),
        content: SizedBox(
          width: 650,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(l.hf_selection_help),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: _busy ? null : _scan,
                  icon: _busy
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.radar),
                  label: Text(l.hf_selection_scan),
                ),
                if (_message != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(_message!),
                  ),
                for (var i = 0; i < _cards.length; i++)
                  ListTile(
                    title: Text(bytesToHexSpace(_cards[i].uid)),
                    selected: _selected == i,
                    leading: Icon(
                      _selected == i
                          ? Icons.radio_button_checked
                          : Icons.radio_button_off,
                    ),
                    onTap: () => setState(() => _selected = i),
                  ),
                if (card != null) ...[
                  const Divider(),
                  SelectableText(
                    'UID: ${bytesToHexSpace(card.uid)}\n'
                    'ATQA: ${bytesToHexSpace(card.atqa)}\n'
                    'SAK: ${card.sak.toRadixString(16).padLeft(2, '0').toUpperCase()}\n'
                    'ATS: ${card.ats.isEmpty ? l.no : bytesToHexSpace(card.ats)}',
                  ),
                ],
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: _busy ? null : () => Navigator.pop(context),
            child: Text(l.close),
          ),
        ],
      ),
    );
  }
}
