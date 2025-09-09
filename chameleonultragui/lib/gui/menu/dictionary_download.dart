import 'package:chameleonultragui/helpers/definitions.dart';
import 'package:chameleonultragui/main.dart';
import 'package:chameleonultragui/sharedprefsprovider.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:http/http.dart' as http;

// Localizations
import 'package:chameleonultragui/generated/i18n/app_localizations.dart';

class DictionaryLocation {
  final String name;
  final String url;

  DictionaryLocation({
    required this.name,
    required this.url,
  });
}

class DictionaryDownloadMenu extends StatefulWidget {
  const DictionaryDownloadMenu({super.key});

  @override
  State<DictionaryDownloadMenu> createState() => DictionaryDownloadMenuState();
}

class DictionaryDownloadMenuState extends State<DictionaryDownloadMenu> {
  final ScrollController _scrollController = ScrollController();
  final Set<String> _downloading = <String>{};

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _downloadDictionary(ChameleonGUIState appState,
      DictionaryLocation dictLocation, AppLocalizations localizations) async {
    setState(() {
      _downloading.add(dictLocation.url);
    });

    try {
      final response = await http.get(Uri.parse(dictLocation.url));

      if (response.statusCode == 200) {
        Dictionary dict = Dictionary.fromString(response.body);
        dict.name = dictLocation.name;

        var dictionaries = appState.sharedPreferencesProvider.getDictionaries();
        dictionaries.add(dict);
        appState.sharedPreferencesProvider.setDictionaries(dictionaries);
        appState.changesMade();

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
                content: Text(localizations
                    .dictionary_download_success(dictLocation.name))),
          );
        }
      }
    } catch (_) {
    } finally {
      if (mounted) {
        setState(() {
          _downloading.remove(dictLocation.url);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    var appState = context.watch<ChameleonGUIState>();
    var localizations = AppLocalizations.of(context)!;

    List<DictionaryLocation> dictionaries = [
      DictionaryLocation(
          name: 'Proxmark3 (Mifare Classic)',
          url:
              'https://raw.githubusercontent.com/RfidResearchGroup/proxmark3/refs/heads/master/client/dictionaries/mfc_default_keys.dic'),
      DictionaryLocation(
          name: 'Proxmark3 (T55XX)',
          url:
              'https://raw.githubusercontent.com/RfidResearchGroup/proxmark3/refs/heads/master/client/dictionaries/t55xx_default_pwds.dic'),
      DictionaryLocation(
          name: 'Proxmark3 (Mifare Ultralight C)',
          url:
              'https://raw.githubusercontent.com/RfidResearchGroup/proxmark3/refs/heads/master/client/dictionaries/mfulc_default_keys.dic'),
      DictionaryLocation(
          name: 'Proxmark3 (Mifare Plus)',
          url:
              'https://raw.githubusercontent.com/RfidResearchGroup/proxmark3/refs/heads/master/client/dictionaries/mfp_default_keys.dic'),
      DictionaryLocation(
          name: 'Flipper Zero Unleashed Firmware (Mifare Classic)',
          url:
              'https://raw.githubusercontent.com/DarkFlippers/unleashed-firmware/refs/heads/dev/applications/main/nfc/resources/nfc/assets/mf_classic_dict.nfc'),
    ];

    return AlertDialog(
      title: Text(localizations.dictionary_download,
          maxLines: 3, overflow: TextOverflow.ellipsis),
      content: SizedBox(
        width: double.maxFinite,
        child: SingleChildScrollView(
          controller: _scrollController,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.start,
            children: List.generate(dictionaries.length, (index) {
              final dict = dictionaries[index];
              final isDownloading = _downloading.contains(dict.url);

              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 4.0),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        dict.name,
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton(
                      onPressed: isDownloading
                          ? null
                          : () => _downloadDictionary(
                              appState, dict, localizations),
                      child: isDownloading
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.download),
                    ),
                  ],
                ),
              );
            }),
          ),
        ),
      ),
      actions: [
        ElevatedButton(
          onPressed: () {
            Navigator.pop(context);
          },
          child: Text(localizations.ok),
        ),
      ],
    );
  }
}
