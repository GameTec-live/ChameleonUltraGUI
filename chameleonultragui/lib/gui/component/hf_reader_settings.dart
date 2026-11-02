import 'package:chameleonultragui/generated/i18n/app_localizations.dart';
import 'package:flutter/material.dart';

/// Session-only reader overrides, available only on firmware with both commands.
class HfReaderSettings extends StatefulWidget {
  final Future<(int, int, int, int)?> Function() onLoad;
  final Future<void> Function(int, int, int, int) onSave;
  final VoidCallback onChanged;

  const HfReaderSettings({
    super.key,
    required this.onLoad,
    required this.onSave,
    required this.onChanged,
  });

  @override
  State<HfReaderSettings> createState() => _HfReaderSettingsState();
}

class _HfReaderSettingsState extends State<HfReaderSettings> {
  late Future<bool> _loadFuture = _load();
  List<int> _values = [0, 0, 0, 0];
  bool _saving = false;

  Future<bool> _load() async {
    final config = await widget.onLoad();
    if (config == null) return false;
    final (bcc, cl2, cl3, rats) = config;
    _values = [bcc, cl2, cl3, rats];
    return true;
  }

  Future<void> _save(List<int> values) async {
    setState(() => _saving = true);
    try {
      // These overrides live in RAM; SAVE_SETTINGS does not persist them.
      await widget.onSave(values[0], values[1], values[2], values[3]);
      if (!mounted) return;
      setState(() => _values = values);
      widget.onChanged();
    } catch (error) {
      if (!mounted) return;
      final localizations = AppLocalizations.of(context)!;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('${localizations.error}: $error')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    return FutureBuilder<bool>(
      future: _loadFuture,
      builder: (context, snapshot) {
        if (snapshot.hasData && !snapshot.data!) {
          return const SizedBox.shrink();
        }
        final labels = [
          l.bcc,
          l.hf_reader_cl2,
          l.hf_reader_cl3,
          l.hf_reader_rats,
        ];
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(l.hf_reader_config),
            const SizedBox(height: 10),
            if (snapshot.hasError) ...[
              Text('${l.error}: ${snapshot.error}'),
              TextButton(
                onPressed: () => setState(() => _loadFuture = _load()),
                child: const Icon(Icons.refresh),
              ),
            ] else if (!snapshot.hasData)
              const CircularProgressIndicator()
            else ...[
              Text(l.hf_reader_config_help),
              for (var i = 0; i < labels.length; i++)
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: DropdownButtonFormField<int>(
                    // Recreate the field after a successful reset.
                    key: ValueKey((i, _values[i])),
                    initialValue: _values[i],
                    isExpanded: true,
                    decoration: InputDecoration(labelText: labels[i]),
                    items: [
                      DropdownMenuItem(
                        value: 0,
                        child: Text(l.hf_reader_standard),
                      ),
                      DropdownMenuItem(
                        value: 1,
                        child: Text(
                          i == 0 ? l.hf_reader_fix_bcc : l.hf_reader_force,
                        ),
                      ),
                      DropdownMenuItem(
                        value: 2,
                        child: Text(
                          i == 0 ? l.hf_reader_ignore_bcc : l.hf_reader_skip,
                        ),
                      ),
                    ],
                    onChanged: _saving
                        ? null
                        : (value) {
                            if (value != null) {
                              setState(() => _values[i] = value);
                            }
                          },
                  ),
                ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 10,
                children: [
                  ElevatedButton(
                    onPressed: _saving ? null : () => _save(List.of(_values)),
                    child: Text(l.save),
                  ),
                  TextButton(
                    onPressed: _saving ? null : () => _save([0, 0, 0, 0]),
                    child: Text(l.reset_default),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 10),
          ],
        );
      },
    );
  }
}
