import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import 'package:provider/provider.dart';
import 'package:chameleonultragui/main.dart';
import 'package:chameleonultragui/generated/i18n/app_localizations.dart';
import 'package:chameleonultragui/plugins/localization.dart';
import 'package:chameleonultragui/plugins/api.dart';
import 'package:chameleonultragui/plugins/plugin.dart';
import 'package:chameleonultragui/plugins/runtime.dart';
import 'package:chameleonultragui/plugins/store.dart';

class PluginsPage extends StatefulWidget {
  const PluginsPage({super.key});
  @override
  State<PluginsPage> createState() => _PluginsPageState();
}

class _PluginsPageState extends State<PluginsPage> {
  AppLocalizations get _localizations =>
      AppLocalizations.of(context) ?? pluginLocalizations;
  final _store = PluginStore();
  List<Plugin> _plugins = [];
  bool _loading = true;

  bool _loadStarted = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_loadStarted) {
      _loadStarted = true;
      _load();
    }
  }

  Future<void> _load() async {
    try {
      final plugins = await withPluginLocalizations(
        _localizations,
        _store.load,
      );
      if (mounted) setState(() => _plugins = plugins);
    } catch (error) {
      if (mounted) _error(error);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _error(Object error) =>
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(error.toString())));

  Future<void> _save(List<Plugin> plugins) async {
    await withPluginLocalizations(_localizations, () => _store.save(plugins));
    if (mounted) setState(() => _plugins = plugins);
  }

  Future<void> _edit([Plugin? plugin]) async {
    final result = await showDialog<Plugin>(
      context: context,
      builder: (_) => _PluginEditor(plugin: plugin),
    );
    if (result == null || !mounted) return;
    try {
      await _save([..._plugins.where((p) => p.id != result.id), result]);
    } catch (error) {
      if (mounted) _error(error);
    }
  }

  Future<bool> _confirm(String title, String message) async =>
      await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(title),
          content: Text(message),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(_localizations.cancel),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(_localizations.continue_action),
            ),
          ],
        ),
      ) ==
      true;

  Future<void> _import() async {
    if (!await _confirm(
      _localizations.plugin_import,
      _localizations.plugin_import_warning,
    )) {
      return;
    }
    try {
      final file = await FilePicker.pickFile();
      if (file == null) return;
      final input = File(file.path!);
      if (await input.length() > Plugin.maxDataBytes * 2) {
        throw FormatException(_localizations.plugin_error_file_size);
      }
      final source = await input.readAsString();
      final plugin = await withPluginLocalizations(
        _localizations,
        () => Plugin.decode(source, freshId: true),
      );
      if (mounted) await _save([..._plugins, plugin]);
    } catch (error) {
      if (mounted) _error(error);
    }
  }

  Future<void> _export(Plugin plugin) async {
    var compress = false;
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, update) => AlertDialog(
          title: Text(_localizations.plugin_export_title(plugin.name)),
          content: CheckboxListTile(
            title: Text(_localizations.plugin_compress_export),
            value: compress,
            onChanged: (value) => update(() => compress = value ?? false),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(_localizations.cancel),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(_localizations.export),
            ),
          ],
        ),
      ),
    );
    if (accepted != true) return;
    try {
      await FilePicker.saveFile(
        fileName:
            '${plugin.name.replaceAll(RegExp(r'[^\w -]'), '_')}.plugin.json',
        bytes: utf8.encode(
          const JsonEncoder.withIndent('  ')
              .convert(plugin.toJson(compress: compress)),
        ),
      );
    } catch (error) {
      if (mounted) _error(error);
    }
  }

  Future<void> _run(Plugin plugin) async {
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) =>
          _PluginRun(plugin: plugin, app: context.read<ChameleonGUIState>()),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(_localizations.plugins),
      actions: [
        IconButton(
          tooltip: _localizations.plugin_import,
          onPressed: _loading ? null : _import,
          icon: const Icon(Icons.file_upload),
        ),
        IconButton(
          tooltip: _localizations.plugin_create,
          onPressed: _loading ? null : _edit,
          icon: const Icon(Icons.add),
        ),
      ],
    ),
    body: _loading
        ? const Center(child: CircularProgressIndicator())
        : _plugins.isEmpty
        ? Center(child: Text(_localizations.plugin_empty))
        : LayoutBuilder(
            builder: (context, constraints) => GridView.builder(
              padding: const EdgeInsets.all(12),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: constraints.maxWidth >= 700 ? 2 : 1,
                mainAxisExtent: 170,
                mainAxisSpacing: 10,
                crossAxisSpacing: 10,
              ),
              itemCount: _plugins.length,
              itemBuilder: (context, index) {
                final plugin = _plugins[index];
                return Card(
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    onTap: () => _run(plugin),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(Icons.extension, color: Color(plugin.color)),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  plugin.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: Theme.of(context).textTheme.titleLarge,
                                ),
                              ),
                              PopupMenuButton<String>(
                                onSelected: (action) async {
                                  switch (action) {
                                    case 'edit':
                                      await _edit(plugin);
                                    case 'export':
                                      await _export(plugin);
                                    case 'delete':
                                      if (await _confirm(
                                        _localizations.plugin_delete_title(
                                          plugin.name,
                                        ),
                                        _localizations.plugin_delete_message,
                                      )) {
                                        try {
                                          await _save(
                                            _plugins
                                                .where((p) => p.id != plugin.id)
                                                .toList(),
                                          );
                                        } catch (error) {
                                          if (mounted) _error(error);
                                        }
                                      }
                                  }
                                },
                                itemBuilder: (_) => ['edit', 'export', 'delete']
                                    .map(
                                      (action) => PopupMenuItem(
                                        value: action,
                                        child: Text(switch (action) {
                                          'edit' => _localizations.edit,
                                          'export' => _localizations.export,
                                          _ => _localizations.delete,
                                        }),
                                      ),
                                    )
                                    .toList(),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Expanded(
                            child: Text(
                              plugin.description,
                              maxLines: 3,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          Text(
                            _localizations.plugin_tap_to_run,
                            style: TextStyle(fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
  );
}

class _PluginEditor extends StatefulWidget {
  final Plugin? plugin;
  const _PluginEditor({this.plugin});
  @override
  State<_PluginEditor> createState() => _PluginEditorState();
}

class _PluginEditorState extends State<_PluginEditor> {
  AppLocalizations get _localizations =>
      AppLocalizations.of(context) ?? pluginLocalizations;
  late final _name = TextEditingController(text: widget.plugin?.name ?? '');
  late final _description = TextEditingController(
    text: widget.plugin?.description ?? '',
  );
  late final _code = TextEditingController(
    text:
        widget.plugin?.code ??
        'chameleon.ui.info(${jsonEncode(_localizations.plugin_default_greeting)})',
  );
  late final _resources = TextEditingController(
    text: const JsonEncoder.withIndent('  ')
        .convert(widget.plugin?.resources ?? <String, String>{}),
  );
  late Color _color = Color(widget.plugin?.color ?? 0xffff5722);
  String? _error;

  @override
  void dispose() {
    for (final controller in [_name, _description, _code, _resources]) {
      controller.dispose();
    }
    super.dispose();
  }

  void _save() {
    try {
      final resources = (jsonDecode(_resources.text) as Map<String, dynamic>)
          .cast<String, String>();
      final plugin = withPluginLocalizations(
        _localizations,
        () => Plugin(
          id: widget.plugin?.id,
          name: _name.text.trim(),
          description: _description.text,
          color: _color.toARGB32(),
          code: _code.text,
          resources: resources,
        ),
      );
      Navigator.pop(context, plugin);
    } catch (error) {
      setState(() => _error = error.toString());
    }
  }

  @override
  Widget build(BuildContext context) => Dialog.fullscreen(
    child: Scaffold(
      appBar: AppBar(
        title: Text(
          widget.plugin == null
              ? _localizations.plugin_create
              : _localizations.plugin_edit,
        ),
        actions: [
          TextButton(onPressed: _save, child: Text(_localizations.save)),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            TextField(
              controller: _name,
              decoration: InputDecoration(labelText: _localizations.name),
            ),
            TextField(
              controller: _description,
              decoration: InputDecoration(
                labelText: _localizations.description,
              ),
              maxLines: 2,
            ),
            ExpansionTile(
              title: Text(_localizations.color),
              leading: Icon(Icons.palette, color: _color),
              children: [
                ColorPicker(
                  pickerColor: _color,
                  onColorChanged: (value) => setState(() => _color = value),
                ),
              ],
            ),
            TextField(
              controller: _code,
              decoration: InputDecoration(
                labelText: _localizations.plugin_lua_code,
              ),
              minLines: 12,
              maxLines: null,
              style: const TextStyle(fontFamily: 'RobotoMono'),
              keyboardType: TextInputType.multiline,
            ),
            const SizedBox(height: 20),
            TextField(
              controller: _resources,
              decoration: InputDecoration(
                labelText: _localizations.plugin_resources_label,
                helperText: _localizations.plugin_resources_help,
              ),
              minLines: 5,
              maxLines: null,
              style: const TextStyle(fontFamily: 'RobotoMono'),
            ),
            if (_error != null)
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
          ],
        ),
      ),
    ),
  );
}

class _PluginRun extends StatefulWidget {
  final Plugin plugin;
  final ChameleonGUIState app;
  const _PluginRun({required this.plugin, required this.app});
  @override
  State<_PluginRun> createState() => _PluginRunState();
}

class _PluginRunState extends State<_PluginRun> {
  AppLocalizations get _localizations =>
      AppLocalizations.of(context) ?? pluginLocalizations;
  final _runtime = PluginRuntime();
  late PluginApi _api;
  bool _finished = false;
  bool _stopping = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _run());
  }

  Future<void> _run() async {
    _api = PluginApi(context, widget.app, widget.plugin);
    try {
      await _runtime.run(
        widget.plugin,
        _api.methods.keys,
        _api.call,
        localizations: _localizations,
      );
    } catch (error) {
      _error = error.toString();
    } finally {
      if (mounted) setState(() => _finished = true);
    }
  }

  @override
  void dispose() {
    _runtime.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: _finished,
    child: AlertDialog(
      title: Text(widget.plugin.name),
      scrollable: true,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (!_finished) const LinearProgressIndicator(),
          const SizedBox(height: 12),
          Text(
            _error ??
                (_finished
                    ? _localizations.plugin_finished
                    : _stopping
                    ? _localizations.plugin_stopping
                    : _localizations.plugin_running),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: _finished
              ? () => Navigator.pop(context)
              : _stopping
              ? null
              : () {
                  setState(() => _stopping = true);
                  _api.cancel();
                  _runtime.stop();
                },
          child: Text(_finished ? _localizations.close : _localizations.stop),
        ),
      ],
    ),
  );
}
