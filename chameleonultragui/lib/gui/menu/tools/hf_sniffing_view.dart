part of 'hf_sniffing.dart';

// Presentation for capture summaries, frames, nonces, recovery, and raw data.
extension on _HfSniffingMenuState {
  Widget _buildHeaderControls(AppLocalizations localizations) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= 760;

        final field = ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 430),
          child: TextFormField(
            controller: _timeoutController,
            enabled: !_isCapturing,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: InputDecoration(
              labelText: localizations.hf_sniff_timeout,
              helperText: localizations.hf_sniff_timeout_help,
              border: const OutlineInputBorder(),
            ),
            validator: (value) => validateIntRange(
              value,
              localizations,
              min: 1,
              max: 30000,
            ),
          ),
        );

        final buttons = Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            FilledButton.icon(
              onPressed: (_isCapturing || _capabilitySupported == false)
                  ? null
                  : _captureFrames,
              icon: _isCapturing
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.radar),
              label: Text(localizations.hf_sniff_capture),
            ),
            OutlinedButton.icon(
              onPressed: _capture == null ? null : _exportCapture,
              icon: const Icon(Icons.download),
              label: Text(localizations.save_to_file),
            ),
            OutlinedButton.icon(
              onPressed: _capture == null
                  ? null
                  : () => _copyText(
                        _rawHexDump(),
                        localizations.hf_sniff_hex_copied,
                      ),
              icon: const Icon(Icons.copy_all),
              label: Text(localizations.hf_sniff_copy_hex),
            ),
          ],
        );

        if (isWide) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              field,
              const SizedBox(width: 20),
              Expanded(
                  child:
                      Align(alignment: Alignment.centerLeft, child: buttons)),
            ],
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            field,
            const SizedBox(height: 12),
            buttons,
          ],
        );
      },
    );
  }

  Widget _buildCapabilityBanner(AppLocalizations localizations) {
    if (_capabilitySupported != false) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Card(
        color: Colors.orange.withValues(alpha: 0.1),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.warning, color: Colors.orange),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  localizations.hf_sniff_firmware_unsupported,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatusBlock() {
    if (_errorMessage != null) {
      return DecoratedBox(
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.errorContainer,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Text(_errorMessage!),
        ),
      );
    }

    if (_statusMessage == null) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: Text(_statusMessage!),
    );
  }

  Widget _buildSummaryTab(AppLocalizations localizations) {
    final capture = _capture;
    if (capture == null) {
      return _buildEmptyState(localizations.hf_sniff_capture_prompt);
    }

    final summary = capture.summary;
    final amount = summary.amountMinorUnits == null
        ? null
        : '${(summary.amountMinorUnits! ~/ 100)}.${(summary.amountMinorUnits! % 100).toString().padLeft(2, '0')}';

    return ListView(
      padding: EdgeInsets.zero,
      children: [
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            _summaryCard(
              localizations.hf_sniff_frames,
              '${summary.frameCount}',
              '${summary.readerFrameCount} / ${summary.cardFrameCount}',
            ),
            _summaryCard(
              localizations.hf_sniff_uid,
              summary.uid ?? localizations.unknown,
              summary.uid == null
                  ? localizations.hf_sniff_note
                  : localizations.hf_sniff_uid,
            ),
            _summaryCard(
              localizations.hf_sniff_protocol,
              summary.ratsSeen ? 'ISO14443-4' : 'ISO14443-A',
              summary.ratsSeen
                  ? localizations.hf_sniff_protocol
                  : localizations.hf_sniff_note,
            ),
          ],
        ),
        const SizedBox(height: 12),
        _buildPanel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                localizations.hf_sniff_summary,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 12),
              _infoRow(localizations.hf_sniff_reader_frames,
                  '${summary.readerFrameCount}'),
              _infoRow(localizations.hf_sniff_card_frames,
                  '${summary.cardFrameCount}'),
              _infoRow(localizations.hf_sniff_uid,
                  summary.uid ?? localizations.unknown),
              _infoRow(localizations.hf_sniff_protocol,
                  summary.ratsSeen ? 'ISO14443-4 (RATS)' : 'ISO14443-A'),
              _infoRow(
                  localizations.hf_sniff_auth,
                  summary.authRequests.isEmpty
                      ? localizations.no
                      : summary.authRequests
                          .map((request) => request.block >= 0
                              ? '${request.keyType} block ${request.block}'
                              : request.keyType)
                          .join(', ')),
              if (summary.aids.isNotEmpty)
                _infoRow(localizations.hf_sniff_aids, summary.aids.join('\n')),
              if (summary.atcLabel != null)
                _infoRow(localizations.hf_sniff_atc, summary.atcLabel!),
              if (amount != null)
                _infoRow(localizations.hf_sniff_amount, amount),
              if (summary.arqcSeen)
                _infoRow(localizations.hf_sniff_auth_type, 'ARQC'),
              if (summary.tcSeen)
                _infoRow(localizations.hf_sniff_auth_type, 'TC'),
              if (summary.halted)
                _infoRow(localizations.hf_sniff_end, 'HALT / DESELECT'),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildFramesTab(AppLocalizations localizations) {
    final capture = _capture;
    if (capture == null) {
      return _buildEmptyState(localizations.hf_sniff_capture_prompt);
    }

    if (capture.annotatedFrames.isEmpty) {
      return _buildEmptyState(localizations.hf_sniff_no_decoded_frames);
    }

    return ListView.separated(
      padding: EdgeInsets.zero,
      itemCount: capture.annotatedFrames.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final annotated = capture.annotatedFrames[index];
        return _buildFrameTranscriptEntry(
          localizations,
          index,
          annotated.frame,
          annotated.label,
        );
      },
    );
  }

  Widget _buildNoncesTab(AppLocalizations localizations) {
    final capture = _capture;
    if (capture == null) {
      return _buildEmptyState(localizations.hf_sniff_capture_prompt);
    }

    if (capture.nonceGroups.isEmpty) {
      return _buildEmptyState(localizations.hf_sniff_nonce_groups);
    }

    return ListView.separated(
      padding: EdgeInsets.zero,
      itemCount: capture.nonceGroups.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        final group = capture.nonceGroups[index];
        return _buildPanel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                localizations.hf_sniff_nonce_group_value(
                  group.block,
                  group.keyType,
                  group.uid,
                ),
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 10),
              for (int i = 0; i < group.exchanges.length; i++) ...[
                SelectableText(
                  localizations.hf_sniff_nonce_exchange_value(
                    i,
                    group.exchanges[i].ntHex,
                    group.exchanges[i].nrHex,
                    group.exchanges[i].arHex,
                  ),
                  style: const TextStyle(fontFamily: 'RobotoMono'),
                ),
                const SizedBox(height: 6),
              ],
              const SizedBox(height: 6),
              SelectableText(
                buildMfkey64Command(group),
                style: const TextStyle(fontFamily: 'RobotoMono'),
              ),
              const SizedBox(height: 6),
              if (group.canRecover)
                SelectableText(
                  buildMfkey32Command(group),
                  style: const TextStyle(fontFamily: 'RobotoMono'),
                ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  OutlinedButton.icon(
                    onPressed: () => _copyText(
                      buildMfkey64Command(group),
                      localizations.hf_sniff_command_copied,
                    ),
                    icon: const Icon(Icons.copy),
                    label: Text(localizations.hf_sniff_mfkey64),
                  ),
                  if (group.canRecover)
                    OutlinedButton.icon(
                      onPressed: () => _copyText(
                        buildMfkey32Command(group),
                        localizations.hf_sniff_command_copied,
                      ),
                      icon: const Icon(Icons.copy),
                      label: Text(localizations.hf_sniff_mfkey32),
                    ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildRecoveryTab(AppLocalizations localizations) {
    final capture = _capture;
    if (capture == null) {
      return _buildEmptyState(localizations.hf_sniff_capture_prompt);
    }

    final groups = capture.nonceGroups;
    if (groups.isEmpty) {
      return _buildEmptyState(localizations.hf_sniff_nonce_groups);
    }

    final recoverableGroups =
        groups.where((group) => group.canRecover).toList();

    return ListView(
      padding: EdgeInsets.zero,
      children: [
        if (recoverableGroups.isNotEmpty) ...[
          Align(
            alignment: Alignment.centerLeft,
            child: FilledButton.icon(
              onPressed: _isRecoveringAll ? null : _recoverAll,
              icon: _isRecoveringAll
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.key),
              label: Text(localizations.hf_sniff_recover_all),
            ),
          ),
          const SizedBox(height: 12),
        ],
        for (final group in groups) ...[
          _buildRecoveryGroup(localizations, group),
          const SizedBox(height: 10),
        ],
      ],
    );
  }

  Widget _buildRecoveryGroup(
      AppLocalizations localizations, HfSniffNonceGroup group) {
    final state = _recoveryStates[group.id];

    return _buildPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            localizations.hf_sniff_nonce_group_value(
              group.block,
              group.keyType,
              group.uid,
            ),
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 10),
          if (!group.canRecover) ...[
            Text(localizations.hf_sniff_nonce_single),
            const SizedBox(height: 8),
            SelectableText(
              buildMfkey64Command(group),
              style: const TextStyle(fontFamily: 'RobotoMono'),
            ),
          ] else ...[
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.icon(
                  onPressed: state?.isLoading == true
                      ? null
                      : () => _recoverGroup(group),
                  icon: state?.isLoading == true
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.key),
                  label: Text(localizations.hf_sniff_recover_key),
                ),
                OutlinedButton.icon(
                  onPressed: () => _copyText(
                    buildMfkey64Command(group),
                    localizations.hf_sniff_command_copied,
                  ),
                  icon: const Icon(Icons.copy),
                  label: Text(localizations.hf_sniff_mfkey64),
                ),
                OutlinedButton.icon(
                  onPressed: () => _copyText(
                    buildMfkey32Command(group),
                    localizations.hf_sniff_command_copied,
                  ),
                  icon: const Icon(Icons.copy),
                  label: Text(localizations.hf_sniff_mfkey32),
                ),
              ],
            ),
            const SizedBox(height: 10),
            if (state == null) Text(localizations.hf_sniff_recovery_pending),
            if (state?.isLoading == true)
              Text(localizations.hf_sniff_recovery_in_progress),
            if (state?.key != null) ...[
              Text(
                localizations.hf_sniff_recovery_method(state!.method ?? ''),
              ),
              const SizedBox(height: 6),
              SelectableText(
                _formatKey(state.key!),
                style: const TextStyle(
                  fontFamily: 'RobotoMono',
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  OutlinedButton.icon(
                    onPressed: () => _copyText(
                      _formatKey(state.key!),
                      localizations.hf_sniff_key_copied,
                    ),
                    icon: const Icon(Icons.copy),
                    label: Text(localizations.hf_sniff_copy_key),
                  ),
                  FilledButton.icon(
                    onPressed: () => _saveRecoveredKey(group, state.key!),
                    icon: const Icon(Icons.save),
                    label: Text(localizations.save_recovered_keys),
                  ),
                ],
              ),
            ],
            if (state?.error != null) ...[
              const SizedBox(height: 6),
              Text(
                state!.error!,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.error,
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }

  Widget _buildRawTab(AppLocalizations localizations) {
    final capture = _capture;
    if (capture == null) {
      return _buildEmptyState(localizations.hf_sniff_capture_prompt);
    }

    final shownBytes = math.min(capture.rawBytes.length, 1024);
    final shownData =
        Uint8List.fromList(capture.rawBytes.take(shownBytes).toList());

    return ListView(
      padding: EdgeInsets.zero,
      children: [
        Text(localizations.hf_sniff_raw_help(
            shownBytes, capture.rawBytes.length)),
        const SizedBox(height: 12),
        _buildPanel(
          padding: const EdgeInsets.all(12),
          child: HexViewer(
            data: shownData,
            scrollVertically: false,
            style: const TextStyle(fontFamily: 'RobotoMono', fontSize: 12),
          ),
        ),
        const SizedBox(height: 12),
        _buildPanel(
          child: SelectableText(
            _rawHexDump(maxBytes: 1024).toUpperCase(),
            style: const TextStyle(fontFamily: 'RobotoMono'),
          ),
        ),
      ],
    );
  }

  Widget _buildFrameTranscriptEntry(
    AppLocalizations localizations,
    int index,
    HfSniffFrame frame,
    String label,
  ) {
    final isReader = frame.isReaderToCard;
    final colorScheme = Theme.of(context).colorScheme;
    final accentColor = isReader ? colorScheme.primary : colorScheme.tertiary;
    final bubbleColor = isReader
        ? colorScheme.primaryContainer.withValues(alpha: 0.42)
        : colorScheme.tertiaryContainer.withValues(alpha: 0.46);
    final routeLabel = isReader ? 'reader -> card' : 'card -> reader';
    final bubbleAlignment =
        isReader ? Alignment.centerLeft : Alignment.centerRight;
    final crossAxisAlignment =
        isReader ? CrossAxisAlignment.start : CrossAxisAlignment.end;
    final textAlign = isReader ? TextAlign.left : TextAlign.right;

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final bubbleMaxWidth =
            width < 520 ? width * 0.94 : math.min(760.0, width * 0.84);

        return SizedBox(
          width: double.infinity,
          child: Align(
            alignment: bubbleAlignment,
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: bubbleMaxWidth),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: bubbleColor,
                  borderRadius: BorderRadius.circular(16),
                  border:
                      Border.all(color: accentColor.withValues(alpha: 0.28)),
                ),
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  child: Column(
                    crossAxisAlignment: crossAxisAlignment,
                    children: [
                      Wrap(
                        spacing: 8,
                        runSpacing: 6,
                        alignment:
                            isReader ? WrapAlignment.start : WrapAlignment.end,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Text(
                            '#${index + 1}',
                            style: Theme.of(context)
                                .textTheme
                                .labelLarge
                                ?.copyWith(
                                  color: accentColor,
                                  fontWeight: FontWeight.w700,
                                ),
                          ),
                          Text(
                            routeLabel,
                            style: Theme.of(context)
                                .textTheme
                                .labelLarge
                                ?.copyWith(
                                  color: accentColor,
                                  fontWeight: FontWeight.w700,
                                ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: accentColor.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Text(
                              '${frame.bitLength}b',
                              style: Theme.of(context)
                                  .textTheme
                                  .labelSmall
                                  ?.copyWith(
                                    color: accentColor,
                                    fontWeight: FontWeight.w700,
                                  ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      SelectableText(
                        frame.hexString.toUpperCase(),
                        textAlign: textAlign,
                        style: const TextStyle(
                          fontFamily: 'RobotoMono',
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        label,
                        textAlign: textAlign,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildEmptyState(String message) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(
          message,
          textAlign: TextAlign.center,
        ),
      ),
    );
  }

  Widget _summaryCard(String title, String value, String subtitle) {
    return SizedBox(
      width: 260,
      child: _buildPanel(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            Text(value, style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 8),
            Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
      ),
    );
  }

  Widget _buildPanel({
    required Widget child,
    EdgeInsetsGeometry padding = const EdgeInsets.all(16),
  }) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.36),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Padding(
        padding: padding,
        child: child,
      ),
    );
  }

  Widget _infoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 160,
            child: Text(
              label,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }
}
