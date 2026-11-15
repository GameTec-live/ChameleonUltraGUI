import 'dart:convert';
import 'dart:io';

import 'package:chameleonultragui/generated/i18n/app_localizations.dart';
import 'package:chameleonultragui/gui/component/qrcode_scanner.dart';
import 'package:chameleonultragui/sync/backend.dart';
import 'package:chameleonultragui/sync/crypto.dart';
import 'package:chameleonultragui/sync/engine.dart';
import 'package:chameleonultragui/sync/hlc.dart';
import 'package:chameleonultragui/sync/sync_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';

/// Settings → Sync: set up a vault, pair devices, browse history.
class SyncPage extends StatelessWidget {
  const SyncPage({super.key});

  @override
  Widget build(BuildContext context) {
    final sync = context.watch<SyncService>();
    return Scaffold(
      appBar: AppBar(title: Text(AppLocalizations.of(context)!.sync)),
      // Keeps the last buttons clear of Android's navigation bar (edge to edge).
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 640),
              child: sync.enabled ? _VaultView(sync) : _SetupView(sync),
            ),
          ),
        ),
      ),
    );
  }
}

/// User-facing text for sync failures. [invalidInput] describes a
/// [FormatException] (bad phrase or pairing code) in the current context.
String _describe(AppLocalizations l, Object? error, {String? invalidInput}) =>
    switch (error) {
      FormatException() when invalidInput != null => invalidInput,
      SyncException(code: 'expired') => l.sync_error_expired,
      SyncException(code: 'mac') => l.sync_error_mac,
      SyncException(code: 'members') => l.sync_error_members,
      SyncException(code: 'rate_limited') => l.sync_error_rate_limited,
      SyncException(code: 'signup_closed') => l.sync_error_signup_closed,
      SyncException(code: 'signup_token') => l.sync_error_signup_token,
      SyncException(code: 'not_found' || 'unauthorized')
          when invalidInput != null =>
        l.sync_error_vault,
      _ => error.toString(),
    };

/// Shows a sync server's notice before setup; true if the user continues.
Future<bool> _acceptNotice(BuildContext context, String notice) async {
  final l = AppLocalizations.of(context)!;
  final accepted = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(l.sync_notice_title),
      content: SingleChildScrollView(child: SelectableText(notice)),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: Text(l.cancel),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          child: Text(l.continue_action),
        ),
      ],
    ),
  );
  return accepted ?? false;
}

void _snack(BuildContext context, String text) =>
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

/// Copies [text] to the clipboard and confirms it in place.
class _CopyButton extends StatefulWidget {
  final String text;
  const _CopyButton(this.text);

  @override
  State<_CopyButton> createState() => _CopyButtonState();
}

class _CopyButtonState extends State<_CopyButton> {
  bool _copied = false;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    return TextButton.icon(
      onPressed: () async {
        await Clipboard.setData(ClipboardData(text: widget.text));
        if (mounted) setState(() => _copied = true);
      },
      icon: Icon(_copied ? Icons.check : Icons.copy),
      label: Text(_copied ? l.sync_copied : l.sync_copy),
    );
  }
}

String _formatTime(BuildContext context, DateTime? time) => time == null
    ? ''
    : DateFormat.yMd(Localizations.localeOf(context).toLanguageTag())
          .add_jm()
          .format(time);

bool get _canScan => !kIsWeb && (Platform.isAndroid || Platform.isIOS);

String _defaultDeviceName() {
  if (kIsWeb) return 'Web';
  final os = Platform.operatingSystem;
  final name = '${os[0].toUpperCase()}${os.substring(1)}';
  try {
    final host = Platform.localHostname;
    return host.isEmpty || host == 'localhost' ? name : '$name ($host)';
  } catch (_) {
    return name;
  }
}

class _SetupView extends StatefulWidget {
  final SyncService sync;
  const _SetupView(this.sync);

  @override
  State<_SetupView> createState() => _SetupViewState();
}

class _SetupViewState extends State<_SetupView> {
  final _url = TextEditingController(text: defaultSyncServer);
  final _user = TextEditingController();
  final _password = TextEditingController();
  final _name = TextEditingController(text: _defaultDeviceName());
  bool _webdav = false;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    for (final controller in [_url, _user, _password, _name]) {
      controller.addListener(() => setState(() {}));
    }
    // Shown once, when this view replaces the vault (or on the next visit).
    if (widget.sync.wasRevoked) {
      widget.sync.wasRevoked = false;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(AppLocalizations.of(context)!.sync_revoked),
            showCloseIcon: true,
            duration: const Duration(seconds: 10),
          ),
        );
      });
    }
  }

  @override
  void dispose() {
    for (final controller in [_url, _user, _password, _name]) {
      controller.dispose();
    }
    super.dispose();
  }

  BackendConfig? get _config {
    final url = Uri.tryParse(_url.text.trim());
    if (url == null || !url.hasScheme || url.host.isEmpty) return null;
    return _webdav
        ? WebDavConfig(url, _user.text, _password.text)
        : ServerConfig(url);
  }

  String get _deviceName =>
      _name.text.trim().isEmpty ? _defaultDeviceName() : _name.text.trim();

  Future<void> _run(
    Future<void> Function() action, {
    String? invalidInput,
  }) async {
    final l = AppLocalizations.of(context)!;
    setState(() => _busy = true);
    try {
      await action();
    } catch (error) {
      // `cancelled`: the user declined the server's notice.
      final declined = error is SyncException && error.code == 'cancelled';
      if (mounted && !declined) {
        _snack(context, _describe(l, error, invalidInput: invalidInput));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _create(BackendConfig config) => _run(() async {
    final l = AppLocalizations.of(context)!;
    final phrase = await widget.sync.createVault(
      config,
      _deviceName,
      acceptNotice: (notice) => _acceptNotice(context, notice),
      askSignupToken: () => showDialog<String>(
        context: context,
        builder: (_) => _InputDialog(l.sync_signup_token, l.sync_signup_hint),
      ),
    );
    if (!mounted) return;
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => _PhraseDialog(phrase),
    );
  });

  Future<void> _joinWithPhrase(BackendConfig config) async {
    final l = AppLocalizations.of(context)!;
    final phrase = await showDialog<String>(
      context: context,
      builder: (_) => _InputDialog(
        l.sync_recovery_phrase,
        l.sync_enter_phrase,
        multiline: true,
      ),
    );
    if (phrase == null) return;
    await _run(
      () => widget.sync.joinWithPhrase(
        config,
        phrase,
        _deviceName,
        acceptNotice: (notice) => _acceptNotice(context, notice),
      ),
      invalidInput: l.sync_error_phrase,
    );
  }

  Future<void> _joinWithCode() => showDialog(
    context: context,
    barrierDismissible: false,
    builder: (_) => _JoinCodeDialog(widget.sync, _deviceName),
  );

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final config = _config;
    final ready = config != null && !_busy;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(l.sync_description),
        const SizedBox(height: 16),
        TextField(
          controller: _name,
          decoration: InputDecoration(labelText: l.sync_device_name),
        ),
        const SizedBox(height: 16),
        FilledButton.tonalIcon(
          onPressed: _busy ? null : _joinWithCode,
          icon: const Icon(Icons.qr_code),
          label: Text(l.sync_join_code),
        ),
        const Divider(height: 32),
        Text(l.sync_backend, style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 8),
        SegmentedButton<bool>(
          segments: [
            ButtonSegment(value: false, label: Text(l.sync_backend_server)),
            ButtonSegment(value: true, label: Text(l.sync_backend_webdav)),
          ],
          selected: {_webdav},
          onSelectionChanged: (value) => setState(() {
            _webdav = value.first;
            // The preset only applies to the sync server.
            if (_webdav && _url.text == defaultSyncServer) {
              _url.clear();
            } else if (!_webdav && _url.text.isEmpty) {
              _url.text = defaultSyncServer;
            }
          }),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _url,
          keyboardType: TextInputType.url,
          decoration: InputDecoration(
            labelText: _webdav ? l.sync_webdav_url : l.sync_server_url,
            hintText: _webdav
                ? 'https://cloud.example.com/remote.php/dav/files/me/chameleon'
                : 'https://sync.example.com',
          ),
        ),
        if (_webdav) ...[
          TextField(
            controller: _user,
            decoration: InputDecoration(labelText: l.sync_username),
          ),
          TextField(
            controller: _password,
            obscureText: true,
            decoration: InputDecoration(labelText: l.sync_password),
          ),
        ],
        const SizedBox(height: 16),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            FilledButton(
              onPressed: ready ? () => _create(config) : null,
              child: Text(l.sync_create_vault),
            ),
            OutlinedButton(
              onPressed: ready ? () => _joinWithPhrase(config) : null,
              child: Text(l.sync_join_phrase),
            ),
          ],
        ),
        if (_busy)
          const Padding(
            padding: EdgeInsets.only(top: 16),
            child: LinearProgressIndicator(),
          ),
      ],
    );
  }
}

class _PhraseDialog extends StatefulWidget {
  final String phrase;
  const _PhraseDialog(this.phrase);

  @override
  State<_PhraseDialog> createState() => _PhraseDialogState();
}

class _PhraseDialogState extends State<_PhraseDialog> {
  bool _confirmed = false;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final words = widget.phrase.split(' ');
    // Row by row, numbered, so it can be copied onto paper in order.
    final columns = switch (MediaQuery.sizeOf(context).width) {
      >= 600 => 4,
      >= 480 => 3,
      _ => 2,
    };
    final number = theme.textTheme.bodyMedium!.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    final word = theme.textTheme.bodyLarge!.copyWith(
      fontWeight: FontWeight.w600,
    );
    return AlertDialog(
      title: Text(l.sync_recovery_phrase),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(l.sync_recovery_phrase_description),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  children: [
                    for (var row = 0; row * columns < words.length; row++)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        child: Row(
                          children: [
                            for (
                              var i = row * columns;
                              i < (row + 1) * columns;
                              i++
                            )
                              Expanded(
                                child: Row(
                                  children: [
                                    SizedBox(
                                      width: 24,
                                      child: Text(
                                        '${i + 1}',
                                        textAlign: TextAlign.right,
                                        style: number,
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Flexible(
                                      child: Text(
                                        i < words.length ? words[i] : '',
                                        style: word,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              CheckboxListTile(
                value: _confirmed,
                onChanged: (value) => setState(() => _confirmed = value!),
                controlAffinity: ListTileControlAffinity.leading,
                contentPadding: EdgeInsets.zero,
                title: Text(l.sync_recovery_phrase_confirm),
              ),
            ],
          ),
        ),
      ),
      actionsAlignment: MainAxisAlignment.spaceBetween,
      actions: [
        _CopyButton(widget.phrase),
        FilledButton(
          onPressed: _confirmed ? () => Navigator.pop(context) : null,
          child: Text(l.done),
        ),
      ],
    );
  }
}

/// Asks for a secret (recovery phrase, signup token); pops the text or null.
class _InputDialog extends StatefulWidget {
  final String title;
  final String hint;
  final bool multiline;
  const _InputDialog(this.title, this.hint, {this.multiline = false});

  @override
  State<_InputDialog> createState() => _InputDialogState();
}

class _InputDialogState extends State<_InputDialog> {
  final _text = TextEditingController();

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    return AlertDialog(
      title: Text(widget.title),
      content: TextField(
        controller: _text,
        minLines: widget.multiline ? 3 : 1,
        maxLines: widget.multiline ? 5 : 1,
        autofocus: true,
        autocorrect: false,
        enableSuggestions: false,
        decoration: InputDecoration(hintText: widget.hint),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l.cancel),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, _text.text.trim()),
          child: Text(l.continue_action),
        ),
      ],
    );
  }
}

/// New device side of pairing: enter/scan the code, show the fingerprint,
/// wait for approval.
class _JoinCodeDialog extends StatefulWidget {
  final SyncService sync;
  final String deviceName;
  const _JoinCodeDialog(this.sync, this.deviceName);

  @override
  State<_JoinCodeDialog> createState() => _JoinCodeDialogState();
}

class _JoinCodeDialogState extends State<_JoinCodeDialog> {
  final _code = TextEditingController();
  bool _joining = false;
  bool _cancelled = false;
  String? _fingerprint;

  @override
  void dispose() {
    _cancelled = true;
    _code.dispose();
    super.dispose();
  }

  Future<void> _scan() async {
    final code = await showDialog<String>(
      context: context,
      builder: (_) => const QrCodeScanner(),
    );
    if (code != null) {
      _code.text = code;
      await _join();
    }
  }

  Future<void> _join() async {
    final l = AppLocalizations.of(context)!;
    setState(() => _joining = true);
    try {
      await widget.sync.joinWithCode(
        _code.text,
        widget.deviceName,
        acceptNotice: (notice) => _acceptNotice(context, notice),
        onWaiting: (fingerprint) {
          if (mounted) setState(() => _fingerprint = fingerprint);
        },
        cancelled: () => _cancelled,
      );
      if (mounted) Navigator.pop(context);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _joining = false;
        _fingerprint = null;
      });
      // Also thrown when the dialog was closed.
      final declined = error is SyncException && error.code == 'cancelled';
      if (!_cancelled && !declined) {
        _snack(context, _describe(l, error, invalidInput: l.sync_error_code));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    return AlertDialog(
      title: Text(l.sync_join_code),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_fingerprint case final fingerprint?) ...[
            Text(l.sync_waiting_approval),
            const SizedBox(height: 12),
            SelectableText(
              fingerprint,
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 12),
            const LinearProgressIndicator(),
          ] else ...[
            TextField(
              controller: _code,
              enabled: !_joining,
              maxLines: 3,
              decoration: InputDecoration(
                labelText: l.sync_pairing_code,
                hintText: l.sync_paste_code,
              ),
            ),
            if (_canScan)
              TextButton.icon(
                onPressed: _joining ? null : _scan,
                icon: const Icon(Icons.qr_code_scanner),
                label: Text(l.sync_scan_code),
              ),
            if (_joining) const LinearProgressIndicator(),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: () {
            _cancelled = true;
            Navigator.pop(context);
          },
          child: Text(l.cancel),
        ),
        if (!_joining)
          TextButton(onPressed: _join, child: Text(l.continue_action)),
      ],
    );
  }
}

class _VaultView extends StatelessWidget {
  final SyncService sync;
  const _VaultView(this.sync);

  String _status(BuildContext context, AppLocalizations l) =>
      switch (sync.status) {
        SyncStatus.syncing => l.sync_status_syncing,
        SyncStatus.error => l.sync_status_error(_describe(l, sync.lastError)),
        _ => l.sync_status_idle,
      };

  String _backendLabel() => switch (sync.backendConfig) {
    ServerConfig(:final url) => url.toString(),
    WebDavConfig(:final url, :final user) => '$user @ $url',
    null => '',
  };

  Future<void> _guard(
    BuildContext context,
    Future<void> Function() action, {
    String? done,
  }) async {
    final l = AppLocalizations.of(context)!;
    try {
      await action();
      if (done != null && context.mounted) _snack(context, done);
    } catch (error) {
      if (context.mounted) _snack(context, _describe(l, error));
    }
  }

  Future<void> _remove(BuildContext context, DeviceInfo device) async {
    final l = AppLocalizations.of(context)!;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l.sync_remove_device),
        content: Text(
          [
            l.sync_remove_device_description(device.name),
            if (!(sync.capabilities?.serverEnforced ?? true))
              l.sync_remove_device_webdav,
          ].join('\n\n'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(l.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(l.sync_remove_device),
          ),
        ],
      ),
    );
    if (confirmed == true && context.mounted) {
      await _guard(context, () => sync.revoke(device.id));
    }
  }

  Future<void> _leave(BuildContext context) async {
    final l = AppLocalizations.of(context)!;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l.sync_leave),
        content: Text(l.sync_leave_description),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(l.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(l.sync_leave),
          ),
        ],
      ),
    );
    if (confirmed == true) await sync.leave();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final history = sync.capabilities?.history ?? false;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Card(
          child: ListTile(
            leading: Icon(switch (sync.status) {
              SyncStatus.error => Icons.sync_problem,
              SyncStatus.syncing => Icons.sync,
              _ => Icons.cloud_done,
            }),
            title: Text(_status(context, l)),
            subtitle: Text(
              [
                if (sync.lastSync case final time?)
                  l.sync_last_sync(_formatTime(context, time)),
                _backendLabel(),
              ].join('\n'),
            ),
            isThreeLine: sync.lastSync != null,
            trailing: IconButton(
              tooltip: l.sync_now,
              icon: const Icon(Icons.refresh),
              onPressed: sync.status == SyncStatus.syncing
                  ? null
                  : () => sync.syncNow(),
            ),
          ),
        ),
        if (sync.oversized.isNotEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(
              l.sync_oversized(sync.oversized.join(', ')),
              style: TextStyle(color: theme.colorScheme.error),
            ),
          ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: Text(l.sync_devices, style: theme.textTheme.titleMedium),
            ),
            FilledButton.tonalIcon(
              onPressed: () => showDialog(
                context: context,
                barrierDismissible: false,
                builder: (_) => _PairingDialog(sync),
              ),
              icon: const Icon(Icons.add),
              label: Text(l.sync_add_device),
            ),
          ],
        ),
        for (final device in sync.devices())
          ListTile(
            leading: const Icon(Icons.devices),
            title: Text(device.name),
            subtitle: Text(
              [
                if (device.isThisDevice) l.sync_this_device,
                _formatTime(context, device.added?.toLocal()),
              ].where((s) => s.isNotEmpty).join(' - '),
            ),
            trailing: device.isThisDevice
                ? null
                : IconButton(
                    tooltip: l.sync_remove_device,
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () => _remove(context, device),
                  ),
          ),
        if (history) ...[
          const SizedBox(height: 16),
          Text(l.sync_recent_changes, style: theme.textTheme.titleMedium),
          for (final (collection, id, meta) in sync.recent().take(30))
            ListTile(
              dense: true,
              leading: Icon(meta.deleted ? Icons.delete : Icons.history),
              title: Text(meta.label),
              subtitle: Text(
                [
                  _collectionName(l, collection),
                  _formatTime(context, Hlc.time(meta.time)),
                  if (meta.deleted) l.sync_deleted,
                ].where((s) => s.isNotEmpty).join(' - '),
              ),
              onTap: () => showDialog(
                context: context,
                builder: (_) =>
                    _HistoryDialog(sync, collection, id, meta.label),
              ),
            ),
        ],
        const SizedBox(height: 24),
        OutlinedButton.icon(
          style: OutlinedButton.styleFrom(
            foregroundColor: theme.colorScheme.error,
          ),
          onPressed: () => _leave(context),
          icon: const Icon(Icons.logout),
          label: Text(l.sync_leave),
        ),
      ],
    );
  }
}

String _collectionName(AppLocalizations l, String collection) =>
    switch (collection) {
      'cards' => l.sync_collection_cards,
      'card_folders' => l.sync_collection_card_folders,
      'dictionaries' => l.sync_collection_dictionaries,
      'dictionary_folders' => l.sync_collection_dictionary_folders,
      'plugins' => l.sync_collection_plugins,
      'settings' => l.sync_collection_settings,
      _ => collection,
    };

/// Existing device side of pairing: show the code, wait, approve.
class _PairingDialog extends StatefulWidget {
  final SyncService sync;
  const _PairingDialog(this.sync);

  @override
  State<_PairingDialog> createState() => _PairingDialogState();
}

class _PairingDialogState extends State<_PairingDialog> {
  PairingOffer? _offer;
  JoinRequest? _request;
  Object? _error;
  bool _approving = false;

  @override
  void initState() {
    super.initState();
    _start();
  }

  @override
  void dispose() {
    _offer?.cancelled = true;
    super.dispose();
  }

  Future<void> _start() async {
    try {
      final offer = await widget.sync.startPairing();
      if (!mounted) {
        offer.cancelled = true;
        return;
      }
      setState(() => _offer = offer);
      final request = await widget.sync.waitForJoin(offer);
      if (mounted) setState(() => _request = request);
    } catch (error) {
      if (mounted && !(_offer?.cancelled ?? false)) {
        setState(() => _error = error);
      }
    }
  }

  Future<void> _approve() async {
    final l = AppLocalizations.of(context)!;
    setState(() => _approving = true);
    try {
      await widget.sync.approve(_offer!, _request!);
      if (mounted) {
        Navigator.pop(context);
        _snack(context, l.sync_device_added);
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _error = error;
          _approving = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final offer = _offer;
    final request = _request;
    final webdav = widget.sync.backendConfig is WebDavConfig;
    return AlertDialog(
      title: Text(l.sync_add_device),
      content: SizedBox(
        width: 360,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_error case final error?)
                Text(
                  _describe(l, error),
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                )
              else if (request != null) ...[
                Text(l.sync_approve_device(request.name)),
                const SizedBox(height: 12),
                SelectableText(
                  fingerprint(request.publicKey),
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
              ] else if (offer != null) ...[
                Text(l.sync_add_device_description),
                if (webdav) ...[
                  const SizedBox(height: 8),
                  Text(
                    l.sync_add_device_webdav_warning,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                QrImageView(
                  data: offer.code,
                  size: 240,
                  backgroundColor: Colors.white,
                  padding: const EdgeInsets.all(12),
                ),
                const SizedBox(height: 12),
                _CopyButton(offer.code),
                const SizedBox(height: 12),
                Text(l.sync_waiting_device),
                const SizedBox(height: 8),
                const LinearProgressIndicator(),
              ] else
                const LinearProgressIndicator(),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () {
            _offer?.cancelled = true;
            Navigator.pop(context);
          },
          child: Text(request == null ? l.cancel : l.sync_reject),
        ),
        if (request != null && _error == null)
          TextButton(
            onPressed: _approving ? null : _approve,
            child: Text(l.sync_approve),
          ),
      ],
    );
  }
}

class _HistoryDialog extends StatelessWidget {
  final SyncService sync;
  final String collection;
  final String id;
  final String label;
  const _HistoryDialog(this.sync, this.collection, this.id, this.label);

  static String? _name(String? value) {
    if (value == null) return null;
    final json = jsonDecode(value);
    return json is Map && json['name'] is String
        ? json['name'] as String
        : value;
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    return AlertDialog(
      title: Text('${l.sync_history}: $label'),
      content: SizedBox(
        width: 420,
        child: FutureBuilder<List<RecordVersion>>(
          future: sync.history(collection, id),
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return Text(_describe(l, snapshot.error));
            }
            final versions = snapshot.data;
            if (versions == null) return const LinearProgressIndicator();
            if (versions.length < 2) return Text(l.sync_history_empty);
            return ListView(
              shrinkWrap: true,
              children: [
                for (final (index, version) in versions.indexed)
                  ListTile(
                    leading: Icon(
                      version.value == null
                          ? Icons.delete
                          : Icons.description_outlined,
                    ),
                    title: Text(_name(version.value) ?? l.sync_deleted),
                    subtitle: Text(
                      _formatTime(context, Hlc.time(version.time)),
                    ),
                    // The first entry is the current version.
                    trailing: index == 0
                        ? null
                        : TextButton(
                            onPressed: () async {
                              await sync.restore(collection, id, version.value);
                              if (context.mounted) {
                                Navigator.pop(context);
                                _snack(context, l.sync_restored);
                              }
                            },
                            child: Text(l.sync_restore),
                          ),
                  ),
              ],
            );
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l.close),
        ),
      ],
    );
  }
}
