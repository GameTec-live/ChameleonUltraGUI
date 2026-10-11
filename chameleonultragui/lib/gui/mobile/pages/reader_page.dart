import 'package:chameleonultragui/connector/serial_abstract.dart';
import 'package:chameleonultragui/gui/component/error_message.dart';
import 'package:chameleonultragui/gui/component/mifare/classic.dart';
import 'package:chameleonultragui/gui/component/mifare/ultralight.dart';
import 'package:chameleonultragui/gui/mobile/controllers/reader_controller.dart';
import 'package:chameleonultragui/helpers/definitions.dart';
import 'package:chameleonultragui/helpers/general.dart';
import 'package:chameleonultragui/helpers/mifare_classic/general.dart';
import 'package:chameleonultragui/helpers/mifare_ultralight/general.dart';
import 'package:chameleonultragui/main.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

// Localizations
import 'package:chameleonultragui/generated/i18n/app_localizations.dart';

/// "Read" tab of the mobile shell. Scans HF or LF cards through
/// [MobileReaderController] and reuses the desktop advanced widgets.
class MobileReaderPage extends StatefulWidget {
  const MobileReaderPage({super.key});

  @override
  State<MobileReaderPage> createState() => _MobileReaderPageState();
}

class _MobileReaderPageState extends State<MobileReaderPage> {
  late final MobileReaderController _controller;

  @override
  void initState() {
    super.initState();
    _controller = MobileReaderController(context.read<ChameleonGUIState>());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!TickerMode.valuesOf(context).enabled) {
      _controller.stopScans();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _saveCard({required bool isHf}) async {
    final localizations = AppLocalizations.of(context)!;

    final name = await showDialog<String>(
      context: context,
      builder: (BuildContext context) => const _CardNameDialog(),
    );
    if (name == null || !mounted) return;

    if (isHf) {
      await _controller.saveHfUid(name, localizations);
    } else {
      await _controller.saveLf(name);
    }

    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(localizations.done)));
  }

  Future<void> _openOverrideDialog() async {
    final localizations = AppLocalizations.of(context)!;

    await showDialog<void>(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: Text(localizations.override_card_type),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                localizations.override_card_type_description,
                style: const TextStyle(fontSize: 14),
              ),
              const SizedBox(height: 16),
              DropdownButton<TagType?>(
                isExpanded: true,
                value: _controller.hfInfo.type,
                onChanged: (TagType? newValue) {
                  if (newValue == null) return;
                  Navigator.of(dialogContext).pop();
                  _controller.overrideHfType(context, newValue);
                },
                items: [
                  ...[
                    ...getTagTypesByFrequency(TagFrequency.hf),
                    TagType.unknown,
                  ].map((TagType tagType) {
                    return DropdownMenuItem<TagType?>(
                      value: tagType,
                      child: Text(chameleonTagToString(tagType, localizations)),
                    );
                  }),
                ],
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: Text(localizations.cancel),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context)!;
    final appState = context.watch<ChameleonGUIState>();
    final isLite = appState.connector?.device == ChameleonDevice.lite;

    return Scaffold(
      appBar: AppBar(title: Text(localizations.read_card)),
      body: ListenableBuilder(
        listenable: _controller,
        builder: (context, _) {
          final controller = _controller;
          final isHf = controller.frequency == ReaderFrequency.hf;

          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SegmentedButton<ReaderFrequency>(
                  segments: [
                    ButtonSegment<ReaderFrequency>(
                      value: ReaderFrequency.hf,
                      icon: const Icon(Icons.credit_card),
                      label: Text(localizations.hf),
                    ),
                    ButtonSegment<ReaderFrequency>(
                      value: ReaderFrequency.lf,
                      icon: const Icon(Icons.wifi),
                      label: Text(localizations.lf),
                    ),
                  ],
                  selected: {controller.frequency},
                  onSelectionChanged: (Set<ReaderFrequency> selection) =>
                      controller.setFrequency(selection.first),
                ),
                const SizedBox(height: 16),
                if (isLite)
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        children: [
                          Icon(
                            Icons.info_outline,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                          const SizedBox(width: 16),
                          Expanded(child: Text(localizations.lite_no_read)),
                        ],
                      ),
                    ),
                  )
                else
                  _ScanButtons(controller: controller),
                if (controller.error != null) ...[
                  const SizedBox(height: 16),
                  ErrorMessage(errorMessage: controller.error.toString()),
                ],
                if (isHf) ...[
                  if (!controller.hfInfo.cardExist) ...[
                    const SizedBox(height: 16),
                    ErrorMessage(errorMessage: localizations.no_card_found),
                  ],
                  if (controller.hfInfo.uid.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    _buildHfResult(localizations, controller),
                  ],
                ] else ...[
                  if (!controller.lfInfo.cardExist) ...[
                    const SizedBox(height: 16),
                    ErrorMessage(errorMessage: localizations.no_card_found),
                  ],
                  if (controller.lfInfo.card != null) ...[
                    const SizedBox(height: 16),
                    _buildLfResult(localizations, controller),
                  ],
                ],
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildHfResult(
    AppLocalizations localizations,
    MobileReaderController controller,
  ) {
    final hfInfo = controller.hfInfo;
    final isClassic = isMifareClassic(hfInfo.type);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  localizations.hf_tag_info,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 8),
                _FieldText(label: localizations.uid, value: hfInfo.uid),
                _FieldText(label: localizations.sak, value: hfInfo.sak),
                _FieldText(label: localizations.atqa, value: hfInfo.atqa),
                _FieldText(label: localizations.ats, value: hfInfo.ats),
                Row(
                  children: [
                    Expanded(
                      child: _FieldText(
                        label: localizations.card_tech,
                        value: hfInfo.tech,
                      ),
                    ),
                    IconButton(
                      onPressed: _openOverrideDialog,
                      icon: const Icon(Icons.edit),
                      tooltip: localizations.override_card_type,
                    ),
                  ],
                ),
                if (isClassic) ...[
                  if (controller.mfcInfo.ntLevel != null)
                    _FieldText(
                      label: localizations.prng_type,
                      value: mfClassicGetPrngType(
                        controller.mfcInfo.ntLevel!,
                        localizations,
                      ),
                    ),
                  if (controller.mfcInfo.hasBackdoor != null)
                    _FieldText(
                      label: localizations.has_backdoor_support,
                      value: controller.mfcInfo.hasBackdoor!
                          ? localizations.yes
                          : localizations.no,
                    ),
                ],
                const SizedBox(height: 8),
                OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(48),
                  ),
                  onPressed: () => _saveCard(isHf: true),
                  child: Text(localizations.save_only_uid),
                ),
              ],
            ),
          ),
        ),
        if (isClassic) ...[
          const SizedBox(height: 16),
          MifareClassicHelper(
            mfcInfo: controller.mfcInfo,
            hfInfo: controller.hfInfo,
          ),
        ],
        if (isMifareUltralight(hfInfo.type)) ...[
          const SizedBox(height: 16),
          MifareUltralightHelper(hfInfo: controller.hfInfo),
        ],
      ],
    );
  }

  Widget _buildLfResult(
    AppLocalizations localizations,
    MobileReaderController controller,
  ) {
    final card = controller.lfInfo.card!;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              localizations.lf_tag_info,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            _FieldText(
              label: localizations.uid,
              value: card.toViewableString(),
            ),
            _FieldText(
              label: localizations.card_tech,
              value: chameleonTagToString(card.type, localizations),
            ),
            const SizedBox(height: 8),
            FilledButton.tonal(
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(48),
              ),
              onPressed: () => _saveCard(isHf: false),
              child: Text(localizations.save),
            ),
          ],
        ),
      ),
    );
  }
}

class _ScanButtons extends StatelessWidget {
  const _ScanButtons({required this.controller});

  final MobileReaderController controller;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context)!;
    final scanning = controller.scanInProgress;
    final continuous = controller.continuousScan;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FilledButton.icon(
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
          onPressed: scanning ? null : () => controller.scanOnce(context),
          icon: scanning
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.sensors),
          label: Text(localizations.scan_card),
        ),
        const SizedBox(height: 8),
        OutlinedButton(
          style: OutlinedButton.styleFrom(
            minimumSize: const Size.fromHeight(48),
          ),
          onPressed: continuous
              ? controller.stopScans
              : (scanning
                    ? null
                    : () => controller.startContinuousScan(context)),
          child: Text(
            continuous ? localizations.cancel : localizations.continuous_scan,
          ),
        ),
      ],
    );
  }
}

class _FieldText extends StatelessWidget {
  const _FieldText({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.bodyLarge;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: SelectableText.rich(
        TextSpan(
          style: style,
          children: [
            TextSpan(
              text: '$label: ',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            TextSpan(text: value),
          ],
        ),
      ),
    );
  }
}

class _CardNameDialog extends StatefulWidget {
  const _CardNameDialog();

  @override
  State<_CardNameDialog> createState() => _CardNameDialogState();
}

class _CardNameDialogState extends State<_CardNameDialog> {
  final TextEditingController _nameController = TextEditingController();

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context)!;

    return AlertDialog(
      title: Text(localizations.enter_name_of_card),
      content: TextField(
        controller: _nameController,
        autofocus: true,
        onSubmitted: (value) => Navigator.of(context).pop(value),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(localizations.cancel),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_nameController.text),
          child: Text(localizations.ok),
        ),
      ],
    );
  }
}
