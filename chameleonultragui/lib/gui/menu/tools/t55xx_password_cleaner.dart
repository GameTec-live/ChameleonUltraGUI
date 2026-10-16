import 'package:chameleonultragui/gui/component/error_page.dart';
import 'package:chameleonultragui/gui/menu/tools/dictionary_download.dart';
import 'package:chameleonultragui/helpers/general.dart';
import 'package:chameleonultragui/helpers/t55xx/keys.dart';
import 'package:chameleonultragui/helpers/validators.dart';
import 'package:chameleonultragui/main.dart';
import 'package:chameleonultragui/sharedprefsprovider.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:chameleonultragui/generated/i18n/app_localizations.dart';

class T55XXPasswordCleanerMenu extends StatefulWidget {
  const T55XXPasswordCleanerMenu({super.key});

  @override
  T55XXPasswordCleanerMenuState createState() =>
      T55XXPasswordCleanerMenuState();
}

class T55XXPasswordCleanerMenuState extends State<T55XXPasswordCleanerMenu> {
  String? selectedDictionaryId;
  final TextEditingController newKeyController = TextEditingController();
  bool isProcessing = false;
  int currentKeyIndex = 0;
  int totalKeys = 0;
  String? foundPassword;
  String? currentKey;

  /// Whether the firmware leaves tags without a password unless asked; null until known.
  /// When true, the tag is left without a password and no new one is needed.
  bool? passwordOptIn;
  bool passwordOptInFailed = false;

  @override
  void initState() {
    super.initState();
    newKeyController.text = t55xxDefaultPassword;
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadPasswordOptIn());
  }

  Future<void> _loadPasswordOptIn() async {
    var communicator = context.read<ChameleonGUIState>().communicator;
    if (communicator == null) return;
    // A failed check must not fall back to old firmware's behaviour: show it and offer a retry.
    setState(() => passwordOptInFailed = false);
    try {
      var value = await communicator.isT55xxPasswordOptIn();
      if (mounted) setState(() => passwordOptIn = value);
    } catch (_) {
      if (mounted) setState(() => passwordOptInFailed = true);
    }
  }

  @override
  void dispose() {
    newKeyController.dispose();
    super.dispose();
  }

  Future<void> _startPasswordReset() async {
    if (selectedDictionaryId == null) return;

    var appState = context.read<ChameleonGUIState>();
    List<Dictionary> dictionaries =
        appState.sharedPreferencesProvider.getDictionaries(keyLength: 8);
    Dictionary? selectedDictionary =
        dictionaries.where((d) => d.id == selectedDictionaryId).firstOrNull;
    if (selectedDictionary == null) return;

    setState(() {
      isProcessing = true;
      currentKeyIndex = 0;
      totalKeys = selectedDictionary.keys.length;
      foundPassword = null;
    });

    var localizations = AppLocalizations.of(context)!;

    try {
      String targetUID = "DE AD BE EF FF";

      for (int i = 0; i < selectedDictionary.keys.length; i++) {
        if (!isProcessing) break;

        setState(() {
          currentKeyIndex = i + 1;
          currentKey = bytesToHexSpace(selectedDictionary.keys[i]);
        });

        try {
          await appState.communicator!.writeEM410XtoT55XX(
              hexToBytes(targetUID),
              hexToBytes(passwordOptIn == true
                  ? t55xxNoPasswordKey
                  : newKeyController.text),
              [selectedDictionary.keys[i]],
              setPassword: passwordOptIn == true ? false : null);

          var newCard = await appState.communicator!.readEM410X();

          if (newCard != null && newCard.toString() == targetUID) {
            setState(() {
              foundPassword = bytesToHexSpace(selectedDictionary.keys[i]);
              isProcessing = false;
            });

            if (mounted) {
              showSuccessDialog(localizations, foundPassword!);
            }
            return;
          }
        } catch (e) {
          continue;
        }
      }

      if (isProcessing) {
        setState(() {
          isProcessing = false;
        });

        if (mounted) {
          showFailureDialog(localizations);
        }
      }
    } catch (e) {
      setState(() {
        isProcessing = false;
      });

      if (mounted) {
        showErrorDialog(e.toString());
      }
    }
  }

  void showSuccessDialog(AppLocalizations localizations, String password) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text(localizations.password_found),
          content: Text(localizations.password_reset_success(password)),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(localizations.ok),
            ),
          ],
        );
      },
    );
  }

  void showFailureDialog(AppLocalizations localizations) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text(localizations.password_reset_failed),
          content: Text(localizations.password_reset_no_match),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(localizations.ok),
            ),
          ],
        );
      },
    );
  }

  void showErrorDialog(String error) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return ErrorPage(errorMessage: error);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    var appState = context.watch<ChameleonGUIState>();
    var localizations = AppLocalizations.of(context)!;

    List<Dictionary> dictionaries =
        appState.sharedPreferencesProvider.getDictionaries(keyLength: 8);

    return AlertDialog(
      title: Text(localizations.t55xx_password_cleaner),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Card(
              color: Colors.orange.withValues(alpha: 0.1),
              child: Padding(
                padding: const EdgeInsets.all(12.0),
                child: Row(
                  children: [
                    const Icon(Icons.warning, color: Colors.orange),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        localizations.t55xx_password_cleaner_warning,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              localizations.select_t55xx_dictionary,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            if (dictionaries.isEmpty) ...[
              Card(
                color: Colors.red.withValues(alpha: 0.1),
                child: Padding(
                  padding: const EdgeInsets.all(12.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(localizations.no_t55xx_dictionaries),
                      const SizedBox(height: 8),
                      ElevatedButton.icon(
                        onPressed: () {
                          showDialog(
                            context: context,
                            builder: (context) =>
                                const DictionaryDownloadMenu(),
                          );
                        },
                        icon: const Icon(Icons.download),
                        label: Text(localizations.download_dictionaries),
                      ),
                    ],
                  ),
                ),
              ),
            ] else ...[
              DropdownButtonFormField<String>(
                initialValue: selectedDictionaryId,
                decoration: InputDecoration(
                  border: const OutlineInputBorder(),
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                ),
                hint: Text(localizations.select_t55xx_dictionary),
                items: dictionaries.map((Dictionary dictionary) {
                  return DropdownMenuItem<String>(
                    value: dictionary.id,
                    child: Text(dictionary.name),
                  );
                }).toList(),
                onChanged: isProcessing
                    ? null
                    : (String? newValue) {
                        setState(() {
                          selectedDictionaryId = newValue;
                        });
                      },
              ),
            ],
            const SizedBox(height: 16),
            if (passwordOptInFailed)
              Row(
                children: [
                  Expanded(
                      child: Text(localizations.t55xx_feature_check_failed)),
                  TextButton(
                    onPressed: _loadPasswordOptIn,
                    child: Text(localizations.retry),
                  ),
                ],
              )
            else if (passwordOptIn == true)
              Text(localizations.t55xx_password_cleaner_no_password)
            else ...[
              Text(
                localizations.enter_new_password,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: newKeyController,
                enabled: !isProcessing,
                decoration: InputDecoration(
                  border: const OutlineInputBorder(),
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                ),
                inputFormatters: hexFormatter,
                validator: (value) => validateHex(value, localizations,
                    exactBytes: 4, fieldName: localizations.key, required: true),
                onChanged: (value) {
                  setState(() {});
                },
              ),
            ],
            if (isProcessing) ...[
              const SizedBox(height: 16),
              Text(
                localizations.password_reset_progress,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              LinearProgressIndicator(
                value: totalKeys > 0 ? currentKeyIndex / totalKeys : 0,
              ),
              const SizedBox(height: 8),
              Text('$currentKeyIndex / $totalKeys'),
              if (currentKey != null) ...[
                const SizedBox(height: 4),
                Text('${localizations.trying_password}: $currentKey'),
              ],
            ],
          ],
        ),
      ),
      actions: [
        if (isProcessing) ...[
          TextButton(
            onPressed: () {
              setState(() {
                isProcessing = false;
              });
            },
            child: Text(localizations.cancel),
          ),
        ] else ...[
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(localizations.cancel),
          ),
          ElevatedButton(
            onPressed: (selectedDictionaryId != null &&
                    passwordOptIn != null &&
                    (passwordOptIn == true ||
                        newKeyController.text.length == 8))
                ? _startPasswordReset
                : null,
            child: Text(localizations.start_password_reset),
          ),
        ],
      ],
    );
  }
}
