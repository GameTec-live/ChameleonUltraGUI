import 'dart:convert';
import 'dart:io';

import 'package:chameleonultragui/gui/component/developer_list.dart';
import 'package:chameleonultragui/gui/component/error_page.dart';
import 'package:chameleonultragui/gui/component/qrcode_viewer.dart';
import 'package:chameleonultragui/gui/menu/dialogs/qr/import.dart';
import 'package:chameleonultragui/gui/menu/dialogs/qr/settings.dart';
import 'package:chameleonultragui/helpers/github.dart';
import 'package:chameleonultragui/helpers/open_collective.dart';
import 'package:chameleonultragui/main.dart';
import 'package:crypto/crypto.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

// Localizations
import 'package:chameleonultragui/generated/i18n/app_localizations.dart';

// Dialogs and actions of the settings screens, shared by the desktop settings
// page and the mobile one.

Future<String> loadLicense(String license) async {
  return await rootBundle.loadString('assets/licenses/$license.md');
}

Future<String> fetchOpenCollectiveNames(BuildContext context) async {
  final List<String> names = await fetchOpenCollectiveContributors();

  if (names.isEmpty && context.mounted) {
    return AppLocalizations.of(context)!.failed_to_fetch_oc_contributors;
  }

  String finalNames = "";
  for (String name in names) {
    finalNames += "$name, ";
  }
  return finalNames.substring(0, finalNames.length - 2);
}

Future<(String, List<Map<String, String>>, PackageInfo)> fetchAboutData(
  BuildContext context,
) async {
  return (
    await fetchOpenCollectiveNames(context),
    await fetchGitHubContributors(),
    await PackageInfo.fromPlatform(),
  );
}

Future<void> showExportSettingsDialog(BuildContext context) async {
  final appState = context.read<ChameleonGUIState>();
  final localizations = AppLocalizations.of(context)!;
  await showDialog<String>(
    context: context,
    builder: (BuildContext context) => AlertDialog(
      title: Text(AppLocalizations.of(context)!.choose_export_method),
      content: Text(
        AppLocalizations.of(context)!.choose_export_method_description,
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(localizations.cancel),
        ),
        TextButton(
          onPressed: () async {
            String string = appState.sharedPreferencesProvider
                .dumpSettingsToJson();

            Map<String, int> settings =
                await showDialog(
                  context: context,
                  builder: (BuildContext context) {
                    return const QRCodeSettings();
                  },
                ) ??
                {};

            if (settings.isEmpty) {
              return;
            }

            List<String> qrChunks = splitStringIntoQrChunks(
              string,
              settings["splitSize"]!,
            ); //2048

            // Generate Header Info
            Map<String, dynamic> headerData = {
              "Info": "Chameleon Ultra GUI Settings",
              "chunks": qrChunks.length,
              "sha256": sha256
                  .convert(const Utf8Encoder().convert(string))
                  .toString(),
            };
            qrChunks.insert(0, jsonEncode(headerData));

            if (context.mounted) {
              await showDialog(
                context: context,
                builder: (BuildContext context) => QrCodeViewer(
                  qrChunks: qrChunks,
                  errorCorrection: settings["errorCorrection"]!,
                ),
              );
            }

            appState.changesMade();
            if (context.mounted) {
              Navigator.pop(context);
            }
          },
          child: Text(localizations.qr_code),
        ),
        TextButton(
          onPressed: () async {
            await FilePicker.saveFile(
              dialogTitle: '${localizations.output_file}:',
              fileName: 'ChameleonUltraGUISettings.json',
              bytes: const Utf8Encoder().convert(
                appState.sharedPreferencesProvider.dumpSettingsToJson(),
              ),
            );
          },
          child: Text(AppLocalizations.of(context)!.json_file),
        ),
      ],
    ),
  );
}

Future<void> showImportSettingsDialog(BuildContext context) async {
  final appState = context.read<ChameleonGUIState>();
  final localizations = AppLocalizations.of(context)!;
  await showDialog<String>(
    context: context,
    builder: (BuildContext context) => AlertDialog(
      title: Text(AppLocalizations.of(context)!.import_settings),
      content: Text(AppLocalizations.of(context)!.import_settings_description),
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
                  title: Text(AppLocalizations.of(context)!.error),
                  content: Text(
                    AppLocalizations.of(context)!
                        .qr_code_import_not_supported_description,
                  ),
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
              },
            );

            if (jsonData == null) {
              return;
            }
            appState.sharedPreferencesProvider.restoreSettingsFromJson(
              jsonData,
            );

            appState.changesMade();
            if (context.mounted) {
              Navigator.pop(context);
            }
          },
          child: Text(localizations.qr_code),
        ),
        TextButton(
          onPressed: () async {
            PlatformFile? result = await FilePicker.pickFile();
            if (result != null) {
              File file = File(result.path!);
              var contents = await file.readAsBytes();
              var string = const Utf8Decoder().convert(contents);
              appState.sharedPreferencesProvider.restoreSettingsFromJson(
                string,
              );
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
  );
}

Future<void> showAboutAppDialog(BuildContext context) async {
  final appState = context.read<ChameleonGUIState>();
  final localizations = AppLocalizations.of(context)!;
  await showDialog<String>(
    context: context,
    builder: (BuildContext context) => AlertDialog(
      title: Text(localizations.about),
      content: Center(
        child: FutureBuilder(
          future: fetchAboutData(context),
          builder: (BuildContext context, AsyncSnapshot snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            } else if (snapshot.hasError) {
              appState.connector!.performDisconnect();
              return ErrorPage(errorMessage: snapshot.error.toString());
            } else {
              final (names, contributors, packageInfo) = snapshot.data;
              return SingleChildScrollView(
                child: Column(
                  children: [
                    const Text(
                      'Chameleon Ultra GUI',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    Text(localizations.about_text),
                    const SizedBox(height: 10),
                    Text('${localizations.version}:'),
                    Text(
                      '${packageInfo.version} (Build ${packageInfo.buildNumber})',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 10),
                    Text('${localizations.developed_by}:'),
                    const SizedBox(height: 10),
                    DeveloperList(avatars: developers),
                    const SizedBox(height: 10),
                    Text('${localizations.license}:'),
                    const Text(
                      'GNU General Public License v3.0',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 10),
                    GestureDetector(
                      onTap: () async {
                        await launchUrl(
                          Uri.parse(
                            'https://github.com/GameTec-live/ChameleonUltraGUI',
                          ),
                        );
                      },
                      child: const Text(
                        'https://github.com/GameTec-live/ChameleonUltraGUI',
                      ),
                    ),
                    const SizedBox(height: 30),
                    GestureDetector(
                      onTap: () async {
                        await launchUrl(
                          Uri.parse(
                            'https://opencollective.com/chameleon-ultra-gui',
                          ),
                        );
                      },
                      child: Text(localizations.thanks_for_support),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      names,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 10),
                    Text('${localizations.code_contributors}:'),
                    const SizedBox(height: 10),
                    DeveloperList(avatars: contributors),
                    const SizedBox(height: 10),
                    Text(localizations.trademarks_mifare),
                    const SizedBox(height: 10),
                    Text(localizations.trademarks_em),
                    const SizedBox(height: 10),
                    Text(localizations.trademarks_hid),
                  ],
                ),
              );
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
  );
}

Future<void> toggleEmulatedDeviceDialog(BuildContext context) async {
  final appState = context.read<ChameleonGUIState>();
  final localizations = AppLocalizations.of(context)!;
  await showDialog<String>(
    context: context,
    builder: (BuildContext context) => AlertDialog(
      title: Text(localizations.emulate_device),
      content: Text(
        localizations.emulate_device_confirmation(
          appState.sharedPreferencesProvider.isEmulatedChameleon()
              ? localizations.deactivate.toLowerCase()
              : localizations.activate.toLowerCase(),
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(localizations.cancel),
        ),
        TextButton(
          onPressed: () {
            appState.sharedPreferencesProvider.setEmulatedChameleon(
              !appState.sharedPreferencesProvider.isEmulatedChameleon(),
            );
            appState.connector = null;
            appState.changesMade();
            Navigator.pop(context);
          },
          child: Text(localizations.ok),
        ),
      ],
    ),
  );
}

Future<void> toggleDebugModeDialog(BuildContext context) async {
  final appState = context.read<ChameleonGUIState>();
  final localizations = AppLocalizations.of(context)!;
  await showDialog<String>(
    context: context,
    builder: (BuildContext context) => AlertDialog(
      title: Text(localizations.debug_mode),
      content: Text(
        localizations.debug_mode_confirmation(
          appState.sharedPreferencesProvider.isDebugMode()
              ? localizations.deactivate.toLowerCase()
              : localizations.activate.toLowerCase(),
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(localizations.cancel),
        ),
        TextButton(
          onPressed: () {
            appState.sharedPreferencesProvider.setDebugMode(
              !appState.sharedPreferencesProvider.isDebugMode(),
            );
            appState.changesMade();
            Navigator.pop(context);
          },
          child: Text(localizations.ok),
        ),
      ],
    ),
  );
}

Future<void> showLicenses(BuildContext context) async {
  Map<String, String> licenses = {
    'BSD-3-Clause': await loadLicense('BSD-3-Clause'),
    'GPL3': await loadLicense('GPL3'),
    'LGPL3': await loadLicense('LGPL3'),
    'MIT': await loadLicense('MIT'),
  };

  // font.dart
  LicenseRegistry.addLicense(
    () => Stream<LicenseEntry>.value(
      LicenseEntryWithLineBreaks(<String>[
        'chinese_font_library',
      ], licenses['BSD-3-Clause']!),
    ),
  );

  // ported hardnested to Windows + MSVC, separation from proxmark3 code
  LicenseRegistry.addLicense(
    () => Stream<LicenseEntry>.value(
      LicenseEntryWithLineBreaks(<String>[
        'FlipperNestedRecovery',
      ], licenses['LGPL3']!),
    ),
  );

  LicenseRegistry.addLicense(
    () => Stream<LicenseEntry>.value(
      LicenseEntryWithLineBreaks(<String>['proxmark3'], licenses['GPL3']!),
    ),
  );

  // hardnested tables uncompressor
  LicenseRegistry.addLicense(
    () => Stream<LicenseEntry>.value(
      LicenseEntryWithLineBreaks(<String>['minlzma'], licenses['MIT']!),
    ),
  );

  if (context.mounted) {
    showLicensePage(context: context);
  }
}
