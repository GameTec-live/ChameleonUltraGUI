import 'package:chameleonultragui/generated/i18n/app_localizations.dart';
import 'package:chameleonultragui/gui/component/key_check_marks.dart';
import 'package:chameleonultragui/gui/page/read_card.dart';
import 'package:chameleonultragui/helpers/definitions.dart';
import 'package:chameleonultragui/helpers/general.dart';
import 'package:chameleonultragui/helpers/mifare_classic/general.dart';
import 'package:chameleonultragui/helpers/mifare_classic/value_blocks.dart';
import 'package:chameleonultragui/main.dart';
import 'package:chameleonultragui/sharedprefsprovider.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class MifareValueBlocksTool extends StatefulWidget {
  const MifareValueBlocksTool({super.key});

  @override
  State<MifareValueBlocksTool> createState() => _MifareValueBlocksToolState();
}

class _MifareValueBlocksToolState extends State<MifareValueBlocksTool> {
  final _amount = TextEditingController(text: '1');
  final _writeValue = TextEditingController(text: '0');
  MifareValueBlocks? _card;
  HFCardInfo? _info;
  bool _busy = false;
  bool _skipDefault = false;
  bool _chooseDestination = false;
  int? _source;
  int? _destination;
  String? _error;
  String? _result;

  AppLocalizations get l => AppLocalizations.of(context)!;

  @override
  void dispose() {
    _amount.dispose();
    _writeValue.dispose();
    super.dispose();
  }

  void _update() {
    if (mounted) setState(() {});
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
      _result = null;
    });
    try {
      await action();
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _scan() => _run(() async {
    setState(() {
      _card = null;
      _info = null;
      _source = null;
      _destination = null;
      _chooseDestination = false;
    });
    final appState = context.read<ChameleonGUIState>();
    final communicator = appState.communicator!;
    final (info, mfc, _) = await readHFInfo(context, _update);
    if (!mounted) return;
    if (!info.cardExist ||
        mfc.type == MifareClassicType.none ||
        mfc.recovery == null) {
      throw StateError(l.value_block_scan_classic);
    }
    final capabilities = await communicator.getDeviceCapabilities();
    if (!mounted) return;
    mfc.recovery!.dictionaries = [
      Dictionary(id: '', name: l.empty, keys: []),
      ...appState.sharedPreferencesProvider.getDictionaries(keyLength: 12),
    ];
    mfc.recovery!.selectedDictionary = mfc.recovery!.dictionaries.first;
    setState(() {
      _info = info;
      _card = MifareValueBlocks(
        communicator: communicator,
        recovery: mfc.recovery!,
        uid: info.uid,
        capabilities: capabilities.toSet(),
      );
    });
  });

  Future<void> _recover({required bool dictionary}) => _run(() async {
    final card = _card!;
    await card.ensureCard();
    card.recovery.error = '';
    if (dictionary) {
      await card.recovery.checkKeys(skipDefaultDictionary: _skipDefault);
    } else {
      await card.recovery.recoverKeys();
    }
    if (card.recovery.error.isNotEmpty) throw StateError(card.recovery.error);
    await _readLayout(card);
  });

  Future<void> _readLayout(MifareValueBlocks card) async {
    if (!card.capabilities.contains(ChameleonCommand.mf1ReadBlock.value)) {
      throw StateError(l.value_block_unsupported);
    }
    await card.refresh();
    if (!mounted) return;
    _source ??= List.generate(card.blockCount, (index) => index)
        .where((block) => card.isDataBlock(block) && card.value(block) != null)
        .firstOrNull;
    _destination ??= _source;
    _result = l.value_block_layout_loaded;
  }

  Future<void> _apply(ValueBlockOperation operation) async {
    final card = _card!;
    final source = _source;
    final destination = operation == ValueBlockOperation.write
        ? source
        : _destination;
    if (_busy || source == null || destination == null) return;
    final amount = operation == ValueBlockOperation.transfer
        ? 0
        : int.tryParse(
            operation == ValueBlockOperation.write
                ? _writeValue.text
                : _amount.text,
          );
    final minimum = operation == ValueBlockOperation.write ? -0x80000000 : 0;
    if (amount == null || amount < minimum || amount > 0x7FFFFFFF) {
      setState(() => _error = '$minimum … 2147483647');
      return;
    }
    await _run(() async {
      await card.apply(operation, source, destination, amount);
      if (!mounted) return;
      _result = l.value_block_done;
      // A successful transfer must not look like a failed mutation if readback
      // is forbidden or the card was removed afterward.
      try {
        final data = await card.readBlock(destination);
        if (data == null) _result = l.value_block_done_unverified;
      } catch (_) {
        _result = l.value_block_done_unverified;
      }
    });
  }

  Widget _recovery(MifareValueBlocks card) {
    final recovery = card.recovery;
    return Card(
      child: ExpansionTile(
        initiallyExpanded: true,
        title: Text(l.keys),
        subtitle: Text(l.value_block_recovery_hint),
        childrenPadding: const EdgeInsets.all(16),
        children: [
          AbsorbPointer(
            absorbing: _busy,
            child: KeyCheckMarks(
              checkmarkCount: card.sectorCount,
              checkmarkPerRow: MediaQuery.sizeOf(context).width < 600 ? 8 : 16,
              checkMarks: recovery.checkMarks,
              validKeys: recovery.validKeys,
              onCheckmarkChanged: (index, state) => setState(() {
                recovery.checkMarks[index] = state;
              }),
            ),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            key: ObjectKey(recovery),
            initialValue: recovery.selectedDictionary!.id,
            decoration: InputDecoration(labelText: l.additional_key_dict),
            items: recovery.dictionaries
                .map(
                  (dictionary) => DropdownMenuItem(
                    value: dictionary.id,
                    child: Text(
                      '${dictionary.name} (${dictionary.keys.length})',
                    ),
                  ),
                )
                .toList(),
            onChanged: _busy
                ? null
                : (id) => setState(() {
                    recovery.selectedDictionary = recovery.dictionaries
                        .firstWhere((entry) => entry.id == id);
                  }),
          ),
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(l.skip_default_dictionary),
            value: _skipDefault,
            onChanged: _busy
                ? null
                : (value) => setState(() => _skipDefault = value!),
          ),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton.icon(
                onPressed: _busy ? null : () => _recover(dictionary: true),
                icon: const Icon(Icons.search),
                label: Text(l.check_keys_dict),
              ),
              OutlinedButton.icon(
                onPressed: _busy ? null : () => _recover(dictionary: false),
                icon: const Icon(Icons.key),
                label: Text(l.recover_keys),
              ),
            ],
          ),
          if (recovery.state.isNotEmpty) Text(recovery.state),
          if (recovery.keyCheckProgress != null)
            LinearProgressIndicator(value: recovery.keyCheckProgress),
          if (recovery.hardnestedProgress != null)
            LinearProgressIndicator(value: recovery.hardnestedProgress),
        ],
      ),
    );
  }

  Widget _block(MifareValueBlocks card, int block) {
    final isData = card.isDataBlock(block);
    final knownKey = card.keyTypeFor(block, 0) != null;
    final value = card.value(block);
    final selected = block == (_chooseDestination ? _destination : _source);
    final colors = Theme.of(context).colorScheme;
    final label = block == 0
        ? l.value_block_manufacturer
        : !isData
        ? l.sector_trailer
        : !knownKey
        ? l.value_block_locked
        : card.blocks[block] == null
        ? l.value_block_unread
        : value == null
        ? l.value_block_data
        : '$value';
    return SizedBox(
      width: 112,
      height: 102,
      child: Tooltip(
        message: '${l.block} $block • $label',
        child: Card(
          margin: EdgeInsets.zero,
          color: selected
              ? colors.primaryContainer
              : value != null
              ? colors.secondaryContainer
              : null,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(
              color: selected ? colors.primary : colors.outlineVariant,
              width: selected ? 2 : 1,
            ),
          ),
          child: InkWell(
            key: ValueKey('value-block-$block'),
            borderRadius: BorderRadius.circular(12),
            onTap: _busy || !isData || !knownKey
                ? null
                : () => setState(() {
                    if (_chooseDestination) {
                      _destination = block;
                    } else {
                      if (_destination == null || _destination == _source) {
                        _destination = block;
                      }
                      _source = block;
                    }
                    _error = null;
                    _result = null;
                  }),
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          '${l.block} $block',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.labelMedium,
                        ),
                      ),
                      if (!isData || !knownKey)
                        const Icon(Icons.lock_outline, size: 14),
                    ],
                  ),
                  const Spacer(),
                  Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: value != null
                        ? Theme.of(context).textTheme.titleMedium
                        : null,
                  ),
                  Row(
                    children: [
                      if (_source == block) const Icon(Icons.output, size: 14),
                      if (_destination == block)
                        const Icon(Icons.input, size: 14),
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

  Widget _layout(MifareValueBlocks card) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(l.value_block_layout, style: Theme.of(context).textTheme.titleLarge),
      const SizedBox(height: 8),
      Text(l.value_block_layout_hint),
      const SizedBox(height: 12),
      for (var sector = 0; sector < card.sectorCount; sector++)
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${l.sector} $sector',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (
                      var offset = 0;
                      offset < mfClassicGetBlockCountBySector(sector);
                      offset++
                    )
                      _block(
                        card,
                        mfClassicGetFirstBlockCountBySector(sector) + offset,
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
    ],
  );

  Widget _selection(String title, int? block, MifareValueBlocks card) =>
      Expanded(
        child: Column(
          children: [
            Text(title),
            Text(
              block == null ? '—' : '${l.block} $block',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            if (block != null) Text(card.value(block)?.toString() ?? '—'),
          ],
        ),
      );

  Widget _actions(MifareValueBlocks card) {
    final source = _source;
    final destination = _destination;
    bool canApply(ValueBlockOperation op) =>
        !_busy &&
        source != null &&
        card.canApply(
          op,
          source,
          op == ValueBlockOperation.write ? source : destination ?? -1,
        );
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              l.value_block_operations,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 12),
            SegmentedButton<bool>(
              segments: [
                ButtonSegment(
                  value: false,
                  icon: const Icon(Icons.output),
                  label: Text(l.value_block_select_source),
                ),
                ButtonSegment(
                  value: true,
                  icon: const Icon(Icons.input),
                  label: Text(l.value_block_select_destination),
                ),
              ],
              selected: {_chooseDestination},
              onSelectionChanged: _busy
                  ? null
                  : (selection) =>
                        setState(() => _chooseDestination = selection.single),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                _selection(l.value_block_select_source, source, card),
                const Icon(Icons.arrow_forward),
                _selection(l.value_block_select_destination, destination, card),
              ],
            ),
            if (source != null && card.address(source) != null)
              Text('${l.value_block_address}: ${card.address(source)}'),
            const SizedBox(height: 12),
            TextField(
              controller: _amount,
              enabled: !_busy,
              decoration: InputDecoration(
                labelText: l.value_block_amount,
                border: const OutlineInputBorder(),
              ),
              keyboardType: TextInputType.number,
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.tonalIcon(
                  onPressed: canApply(ValueBlockOperation.increment)
                      ? () => _apply(ValueBlockOperation.increment)
                      : null,
                  icon: const Icon(Icons.add),
                  label: Text(l.value_block_increment),
                ),
                FilledButton.tonalIcon(
                  onPressed: canApply(ValueBlockOperation.decrement)
                      ? () => _apply(ValueBlockOperation.decrement)
                      : null,
                  icon: const Icon(Icons.remove),
                  label: Text(l.value_block_decrement),
                ),
                OutlinedButton.icon(
                  onPressed: canApply(ValueBlockOperation.transfer)
                      ? () => _apply(ValueBlockOperation.transfer)
                      : null,
                  icon: const Icon(Icons.arrow_forward),
                  label: Text(l.value_block_copy),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              l.value_block_access_hint,
              style: Theme.of(context).textTheme.bodySmall,
            ),
            ExpansionTile(
              tilePadding: EdgeInsets.zero,
              title: Text(l.value_block_write),
              children: [
                Text(l.value_block_write_hint),
                const SizedBox(height: 8),
                TextField(
                  controller: _writeValue,
                  enabled: !_busy,
                  decoration: InputDecoration(labelText: l.value),
                  keyboardType: const TextInputType.numberWithOptions(
                    signed: true,
                  ),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: canApply(ValueBlockOperation.write)
                      ? () => _apply(ValueBlockOperation.write)
                      : null,
                  icon: const Icon(Icons.edit),
                  label: Text(l.value_block_write),
                ),
              ],
            ),
            if (_result != null) Text(_result!),
            if (_error != null)
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final connected = context.watch<ChameleonGUIState>().communicator != null;
    final card = _card;
    return PopScope(
      canPop: !_busy,
      child: Scaffold(
        appBar: AppBar(title: Text(l.live_value_blocks)),
        body: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(l.value_block_tool_hint),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 12,
                    runSpacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      FilledButton.icon(
                        onPressed: _busy || !connected ? null : _scan,
                        icon: const Icon(Icons.nfc),
                        label: Text(l.value_block_scan),
                      ),
                      if (card != null)
                        OutlinedButton.icon(
                          onPressed: _busy || !connected
                              ? null
                              : () => _run(() => _readLayout(card)),
                          icon: const Icon(Icons.refresh),
                          label: Text(l.value_block_refresh),
                        ),
                      if (_info != null) Text('${_info!.uid} • ${_info!.tech}'),
                    ],
                  ),
                  if (!connected) Text(l.device_required),
                  if (_busy) const LinearProgressIndicator(),
                  if (card == null && _error != null)
                    Text(
                      _error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                ],
              ),
            ),
            Expanded(
              child: card == null
                  ? Center(child: Text(l.value_block_scan_classic))
                  : LayoutBuilder(
                      builder: (context, constraints) {
                        final recovery = _recovery(card);
                        final layout = _layout(card);
                        final actions = _actions(card);
                        if (constraints.maxWidth >= 1000) {
                          return Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: ListView(
                                  padding: const EdgeInsets.fromLTRB(
                                    16,
                                    0,
                                    8,
                                    16,
                                  ),
                                  children: [recovery, layout],
                                ),
                              ),
                              SizedBox(
                                width: 380,
                                child: ListView(
                                  padding: const EdgeInsets.fromLTRB(
                                    8,
                                    0,
                                    16,
                                    16,
                                  ),
                                  children: [actions],
                                ),
                              ),
                            ],
                          );
                        }
                        return ListView(
                          padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
                          children: [recovery, actions, layout],
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
