import 'package:chameleonultragui/gui/component/developer_list.dart';
import 'package:chameleonultragui/gui/component/toggle_buttons.dart';
import 'package:chameleonultragui/helpers/general.dart';
import 'package:chameleonultragui/helpers/github.dart';
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';
import 'package:chameleonultragui/helpers/open_collective.dart';
import 'package:chameleonultragui/main.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:file_picker/file_picker.dart';
import 'package:file_saver/file_saver.dart';
import 'dart:convert';
import 'dart:io';
import 'package:chameleonultragui/gui/component/qrcode_viewer.dart';
import 'package:crypto/crypto.dart';
import 'package:chameleonultragui/gui/menu/qrcode_import.dart';
import 'package:chameleonultragui/gui/menu/qrcode_settings.dart';

// Localizations
import 'package:chameleonultragui/generated/i18n/app_localizations.dart';

//TODO: remove and use a language provided string
const localeNameMap = {
  "en": "English",
  "zh": "中文",
  "zh-TW": "臺灣正體",
  "es": "Español",
  "fr": "Français",
  "de": "Deutsch",
  "de-AT": "Deutsch (Österreich)",
  "pt": "Português",
  "pt-BR": "Português (Brasil)",
  "ru": "Русский",
  "it": "Italiano",
  "ja": "日本語",
  "ko": "한국어",
  "nl": "Nederlands",
  "ar": "العربية ",
  "tr": "Türkçe",
  "pl": "Polski",
  "sv": "Svenska",
  "da": "Dansk",
  "no": "Norsk",
  "fi": "Suomi",
  "cs": "Čeština",
  "hu": "Magyar",
  "el": "Ελληνικά",
  "he": "עברית ",
  "th": "ไทย ",
  "id": "Bahasa Indonesia",
  "uk": "Українська",
  "ro": "Română",
  "ms": "Bahasa Melayu",
  "hi": "हिन्दी",
  "vi": "Tiếng Việt",
  "ca": "Català",
  "bg": "Български"
};

class SettingsMainPage extends StatefulWidget {
  const SettingsMainPage({super.key});

  @override
  SettingsMainPageState createState() => SettingsMainPageState();
}

class SettingsMainPageState extends State<SettingsMainPage> {
  @override
  void initState() {
    super.initState();
  }

  Future<(String, List<Map<String, String>>, PackageInfo)>
      getFutureData() async {
    return (
      await fetchOCnames(),
      await fetchContributors(),
      await PackageInfo.fromPlatform()
    );
  }

  Future<String> fetchOCnames() async {
    final List<String> names = await fetchOpenCollectiveContributors();
    String finalNames = "";
    for (String name in names) {
      finalNames += "$name, ";
    }
    return finalNames.substring(0, finalNames.length - 2);
  }

  Future<List<Map<String, String>>> fetchContributors() async {
    return await fetchGitHubContributors();
  }

  @override
  Widget build(BuildContext context) {
    var appState = context.watch<ChameleonGUIState>();
    var localizations = AppLocalizations.of(context)!;
    return Scaffold(
      appBar: AppBar(
        title: Text(localizations.settings),
      ),
      body: SingleChildScrollView(
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const SizedBox(height: 10),
              Text(localizations.sidebar_expansion,
                  style: const TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 5),
              ToggleButtonsWrapper(
                  items: [
                    localizations.expand,
                    localizations.auto,
                    localizations.retract
                  ],
                  selectedValue: appState.sharedPreferencesProvider
                      .getSideBarExpandedIndex(),
                  onChange: (int index) async {
                    if (index == 0) {
                      appState.sharedPreferencesProvider
                          .setSideBarExpanded(true);
                      appState.sharedPreferencesProvider
                          .setSideBarAutoExpansion(false);
                    } else if (index == 2) {
                      appState.sharedPreferencesProvider
                          .setSideBarExpanded(false);
                      appState.sharedPreferencesProvider
                          .setSideBarAutoExpansion(false);
                    } else {
                      appState.sharedPreferencesProvider
                          .setSideBarAutoExpansion(true);
                    }
                    appState.sharedPreferencesProvider
                        .setSideBarExpandedIndex(index);
                    appState.changesMade();

                    WidgetsBinding.instance.addPostFrameCallback(
                        (_) => updateNavigationRailWidth(context));
                  }),
              const SizedBox(height: 10),
              Text(
                localizations.theme,
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 5),
              ToggleButtonsWrapper(
                  items: [
                    localizations.system,
                    localizations.light,
                    localizations.dark
                  ],
                  selectedValue:
                      appState.sharedPreferencesProvider.getTheme().index,
                  onChange: (int index) async {
                    appState.sharedPreferencesProvider
                        .setTheme(ThemeMode.values[index]);
                    appState.changesMade();
                  }),
              const SizedBox(height: 10),
              Text(
                localizations.color_scheme,
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 5),
              DropdownButton(
                value: appState.sharedPreferencesProvider.getThemeColorIndex(),
                icon: const Icon(Icons.arrow_downward),
                elevation: 16,
                onChanged: (value) {
                  appState.sharedPreferencesProvider.setThemeColor(value ?? 0);
                  appState.changesMade();
                },
                items: [
                  DropdownMenuItem(
                    value: 0,
                    child: Text(localizations.def),
                  ),
                  DropdownMenuItem(
                    value: 1,
                    child: Text(localizations.purple),
                  ),
                  DropdownMenuItem(
                    value: 2,
                    child: Text(localizations.blue),
                  ),
                  DropdownMenuItem(
                    value: 3,
                    child: Text(localizations.green),
                  ),
                  DropdownMenuItem(
                    value: 4,
                    child: Text(localizations.indigo),
                  ),
                  DropdownMenuItem(
                    value: 5,
                    child: Text(localizations.lime),
                  ),
                  DropdownMenuItem(
                    value: 6,
                    child: Text(localizations.red),
                  ),
                  DropdownMenuItem(
                    value: 7,
                    child: Text(localizations.yellow),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                localizations.language,
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 5),
              FittedBox(
                fit: BoxFit.scaleDown,
                child: DropdownButton(
                  value: appState.sharedPreferencesProvider.getLocaleString(),
                  onChanged: (value) {
                    appState.sharedPreferencesProvider
                        .setLocale(Locale(value ?? 'en'));
                    appState.changesMade();
                  },
                  items: AppLocalizations.supportedLocales.map((locale) {
                    return DropdownMenuItem(
                        value: locale.toLanguageTag(),
                        child: Text(localeNameMap[locale.toLanguageTag()] ??
                            "Unknown"));
                  }).toList(),
                ),
              ),
              const SizedBox(height: 10),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    localizations.confirm_deletions,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(width: 5),
                  Switch(
                    value:
                        appState.sharedPreferencesProvider.getConfirmDelete(),
                    onChanged: (value) async {
                      appState.sharedPreferencesProvider
                          .setConfirmDelete(value);
                      appState.changesMade();
                    },
                  ),
                ],
              ),
              const SizedBox(height: 10),
              FittedBox(
                fit: BoxFit.scaleDown,
                child: TextButton(
                    onPressed: () => showDialog<String>(
                          context: context,
                          builder: (BuildContext context) => AlertDialog(
                            title: Text(AppLocalizations.of(context)!
                                .choose_export_method),
                            content: Text(AppLocalizations.of(context)!
                                .choose_export_method_description),
                            actions: <Widget>[
                              TextButton(
                                onPressed: () => Navigator.pop(context),
                                child: Text(localizations.cancel),
                              ),
                              TextButton(
                                onPressed: () async {
                                  String string = appState
                                      .sharedPreferencesProvider
                                      .dumpSettingsToJson();

                                  Map<String, int> settings = await showDialog(
                                          context: context,
                                          builder: (BuildContext context) {
                                            return const QRCodeSettings();
                                          }) ??
                                      {};

                                  if (settings.isEmpty) {
                                    return;
                                  }

                                  List<String> qrChunks =
                                      splitStringIntoQrChunks(string,
                                          settings["splitSize"]!); //2048

                                  // Generate Header Info
                                  Map<String, dynamic> headerData = {
                                    "Info": "Chameleon Ultra GUI Settings",
                                    "chunks": qrChunks.length,
                                    "sha256": sha256
                                        .convert(
                                            const Utf8Encoder().convert(string))
                                        .toString(),
                                  };
                                  qrChunks.insert(0, jsonEncode(headerData));

                                  if (context.mounted) {
                                    await showDialog(
                                      context: context,
                                      builder: (BuildContext context) =>
                                          QrCodeViewer(
                                              qrChunks: qrChunks,
                                              errorCorrection:
                                                  settings["errorCorrection"]!),
                                    );
                                  }

                                  appState.changesMade();
                                  if (context.mounted) {
                                    Navigator.pop(context);
                                  }
                                },
                                child: const Text("QR Code"),
                              ),
                              TextButton(
                                onPressed: () async {
                                  try {
                                    await FileSaver.instance.saveAs(
                                        name: 'ChameleonUltraGUISettings',
                                        bytes: const Utf8Encoder().convert(
                                            appState.sharedPreferencesProvider
                                                .dumpSettingsToJson()),
                                        ext: 'json',
                                        mimeType: MimeType.other);
                                  } on UnimplementedError catch (_) {
                                    String? outputFile =
                                        await FilePicker.platform.saveFile(
                                      dialogTitle:
                                          '${localizations.output_file}:',
                                      fileName:
                                          'ChameleonUltraGUISettings.json',
                                    );

                                    if (outputFile != null) {
                                      var file = File(outputFile);
                                      await file.writeAsBytes(
                                          const Utf8Encoder().convert(appState
                                              .sharedPreferencesProvider
                                              .dumpSettingsToJson()));
                                    }
                                  }
                                },
                                child: Text(
                                    AppLocalizations.of(context)!.json_file),
                              ),
                            ],
                          ),
                        ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(AppLocalizations.of(context)!.export_settings),
                        const Icon(Icons.upload)
                      ],
                    )),
              ),
              const SizedBox(height: 10),
              FittedBox(
                fit: BoxFit.scaleDown,
                child: TextButton(
                  onPressed: () => showDialog<String>(
                    context: context,
                    builder: (BuildContext context) => AlertDialog(
                      title:
                          Text(AppLocalizations.of(context)!.import_settings),
                      content: Text(AppLocalizations.of(context)!
                          .import_settings_description),
                      actions: <Widget>[
                        TextButton(
                          onPressed: () => Navigator.pop(context),
                          child: Text(localizations.cancel),
                        ),
                        TextButton(
                          onPressed: () async {
                            if (!(Platform.isAndroid || Platform.isIOS)) {
                              await showDialog(
                                context: context,
                                builder: (BuildContext context) => AlertDialog(
                                  title:
                                      Text(AppLocalizations.of(context)!.error),
                                  content: Text(AppLocalizations.of(context)!
                                      .qr_code_import_not_supported_description),
                                  actions: <Widget>[
                                    TextButton(
                                      onPressed: () => Navigator.pop(context),
                                      child: Text(localizations.ok),
                                    ),
                                  ],
                                ),
                              );
                              return;
                            }

                            String? jsonData = await showDialog(
                                context: context,
                                builder: (BuildContext context) {
                                  return const QrCodeImport();
                                });

                            if (jsonData == null) {
                              return;
                            }
                            appState.sharedPreferencesProvider
                                .restoreSettingsFromJson(jsonData);

                            appState.changesMade();
                            if (context.mounted) {
                              Navigator.pop(context);
                            }
                          },
                          child: const Text("QR Code"),
                        ),
                        TextButton(
                          onPressed: () async {
                            FilePickerResult? result =
                                await FilePicker.platform.pickFiles();
                            if (result != null) {
                              File file = File(result.files.single.path!);
                              var contents = await file.readAsBytes();
                              var string =
                                  const Utf8Decoder().convert(contents);
                              appState.sharedPreferencesProvider
                                  .restoreSettingsFromJson(string);
                              appState.changesMade();
                              if (context.mounted) {
                                Navigator.pop(context);
                              }
                            }
                          },
                          child: Text(AppLocalizations.of(context)!.json_file),
                        ),
                      ],
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(AppLocalizations.of(context)!.import_settings),
                      const Icon(Icons.download),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 10),
              TextButton(
                onPressed: () => showDialog<String>(
                  context: context,
                  builder: (BuildContext context) => AlertDialog(
                    title: Text(localizations.about),
                    content: Center(
                      child: FutureBuilder(
                        future: getFutureData(),
                        builder:
                            (BuildContext context, AsyncSnapshot snapshot) {
                          if (snapshot.connectionState ==
                              ConnectionState.waiting) {
                            return const Center(
                                child: CircularProgressIndicator());
                          } else if (snapshot.hasError) {
                            return Text('Error: ${snapshot.error}');
                          } else {
                            final (names, contributors, packageInfo) =
                                snapshot.data;
                            return SingleChildScrollView(
                                child: Column(
                              children: [
                                const Text('Chameleon Ultra GUI',
                                    style:
                                        TextStyle(fontWeight: FontWeight.bold)),
                                Text(localizations.about_text),
                                const SizedBox(height: 10),
                                Text('${localizations.version}:'),
                                Text(
                                    '${packageInfo.version} (Build ${packageInfo.buildNumber})',
                                    style: const TextStyle(
                                        fontWeight: FontWeight.bold)),
                                const SizedBox(height: 10),
                                Text('${localizations.developed_by}:'),
                                const SizedBox(height: 10),
                                DeveloperList(avatars: developers),
                                const SizedBox(height: 10),
                                Text('${localizations.license}:'),
                                const Text('GNU General Public License v3.0',
                                    style:
                                        TextStyle(fontWeight: FontWeight.bold)),
                                const SizedBox(height: 10),
                                GestureDetector(
                                    onTap: () async {
                                      await launchUrl(Uri.parse(
                                          'https://github.com/GameTec-live/ChameleonUltraGUI'));
                                    },
                                    child: const Text(
                                        'https://github.com/GameTec-live/ChameleonUltraGUI')),
                                const SizedBox(height: 30),
                                GestureDetector(
                                    onTap: () async {
                                      await launchUrl(Uri.parse(
                                          'https://opencollective.com/chameleon-ultra-gui'));
                                    },
                                    child:
                                        Text(localizations.thanks_for_support)),
                                const SizedBox(height: 10),
                                Text(names,
                                    style: const TextStyle(
                                        fontWeight: FontWeight.bold)),
                                const SizedBox(height: 10),
                                Text('${localizations.code_contributors}:'),
                                const SizedBox(height: 10),
                                DeveloperList(avatars: contributors),
                              ],
                            ));
                          }
                        },
                      ),
                    ),
                    actions: <Widget>[
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: Text(localizations.ok),
                      ),
                    ],
                  ),
                ),
                child: Text(localizations.about),
              ),
              const SizedBox(height: 10),
              TextButton(
                onPressed: () => showDialog<String>(
                  context: context,
                  builder: (BuildContext context) => AlertDialog(
                    title: Text(localizations.debug_mode),
                    content: Text(localizations.debug_mode_confirmation(
                        appState.sharedPreferencesProvider.isDebugMode()
                            ? localizations.deactivate.toLowerCase()
                            : localizations.activate.toLowerCase())),
                    actions: <Widget>[
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: Text(localizations.cancel),
                      ),
                      TextButton(
                        onPressed: () {
                          appState.sharedPreferencesProvider.setDebugMode(
                              !appState.sharedPreferencesProvider
                                  .isDebugMode());
                          appState.changesMade();
                          Navigator.pop(context);
                        },
                        child: Text(localizations.ok),
                      ),
                    ],
                  ),
                ),
                child: Text(
                    "${appState.sharedPreferencesProvider.isDebugMode() ? localizations.deactivate : localizations.activate} ${localizations.debug_mode.toLowerCase()}"),
              )
            ],
          ),
        ),
      ),
    );
  }
}
