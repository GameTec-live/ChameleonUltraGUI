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
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: sync.enabled ? _VaultView(sync) : _SetupView(sync),
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
      SyncException(code: 'not_found' || 'unauthorized')
          when invalidInput != null =>
        l.sync_error_vault,
      _ => error.toString(),
    };

void _snack(BuildContext context, String text) =>
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

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
  final _url = TextEditingController();
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
      if (mounted) {
        _snack(context, _describe(l, error, invalidInput: invalidInput));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _create(BackendConfig config) => _run(() async {
    final phrase = await widget.sync.createVault(config, _deviceName);
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
      builder: (_) => const _PhraseInputDialog(),
    );
    if (phrase == null) return;
    await _run(
      () => widget.sync.joinWithPhrase(config, phrase, _deviceName),
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
        if (widget.sync.wasRevoked)
          Card(
            color: Theme.of(context).colorScheme.errorContainer,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Text(l.sync_revoked),
            ),
          ),
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
          onSelectionChanged: (value) => setState(() => _webdav = value.first),
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
    final words = widget.phrase.split(' ');
    return AlertDialog(
      title: Text(l.sync_recovery_phrase),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(l.sync_recovery_phrase_description),
            const SizedBox(height: 12),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final (index, word) in words.indexed)
                  Chip(label: Text('${index + 1}. $word')),
              ],
            ),
            TextButton.icon(
              onPressed: () =>
                  Clipboard.setData(ClipboardData(text: widget.phrase)),
              icon: const Icon(Icons.copy),
              label: Text(l.copy),
            ),
            CheckboxListTile(
              value: _confirmed,
              onChanged: (value) => setState(() => _confirmed = value!),
              title: Text(l.sync_recovery_phrase_confirm),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _confirmed ? () => Navigator.pop(context) : null,
          child: Text(l.done),
        ),
      ],
    );
  }
}

class _PhraseInputDialog extends StatefulWidget {
  const _PhraseInputDialog();

  @override
  State<_PhraseInputDialog> createState() => _PhraseInputDialogState();
}

class _PhraseInputDialogState extends State<_PhraseInputDialog> {
  final _phrase = TextEditingController();

  @override
  void dispose() {
    _phrase.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    return AlertDialog(
      title: Text(l.sync_recovery_phrase),
      content: TextField(
        controller: _phrase,
        minLines: 3,
        maxLines: 5,
        autocorrect: false,
        enableSuggestions: false,
        decoration: InputDecoration(hintText: l.sync_enter_phrase),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l.cancel),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, _phrase.text),
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
      if (!_cancelled) {
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
        _ =>
          sync.lastSync == null
              ? l.sync_status_idle
              : '${l.sync_status_idle} · '
                    '${l.sync_last_sync(_formatTime(context, sync.lastSync))}',
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
            subtitle: Text(_backendLabel()),
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
              ].where((s) => s.isNotEmpty).join(' · '),
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
                ].where((s) => s.isNotEmpty).join(' · '),
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
                TextButton.icon(
                  onPressed: () =>
                      Clipboard.setData(ClipboardData(text: offer.code)),
                  icon: const Icon(Icons.copy),
                  label: Text(l.copy),
                ),
                const SizedBox(height: 8),
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
