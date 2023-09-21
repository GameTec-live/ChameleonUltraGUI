import 'dart:io';
import 'dart:convert';

import 'package:chameleonultragui/helpers/general.dart';
import 'package:chameleonultragui/main.dart';
import 'package:chameleonultragui/recovery/recovery.dart';
import 'package:chameleonultragui/recovery/recovery.dart' as recovery;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:file_picker/file_picker.dart';
import 'package:file_saver/file_saver.dart';
import 'package:chameleonultragui/gui/menu/dictionary_edit.dart';
import 'package:chameleonultragui/sharedprefsprovider.dart';
import 'package:flutter/services.dart';

// Localizations
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

class Mfkey32Page extends StatefulWidget {
  const Mfkey32Page({Key? key}) : super(key: key);

  @override
  Mfkey32PageState createState() => Mfkey32PageState();
}

class Mfkey32PageState extends State<Mfkey32Page> {
  final TextEditingController controller = TextEditingController();
  late Future<(bool, int)> detectionStatusFuture;
  bool isDetectionMode = false;
  int detectionCount = -1;
  List<Uint8List> keys = [];
  bool saveKeys = false;
  bool loading = false;
  String outputUid = "";
  List<Row> displayKeys = [];
  List<int> displayedKeys = [];
  int progress = -1;

  @override
  void initState() {
    super.initState();
    detectionStatusFuture = getMf1DetectionStatus();
  }

  Future<(bool, int)> getMf1DetectionStatus() async {
    var appState = context.read<ChameleonGUIState>();

    return (
      await appState.communicator!.isMf1DetectionMode(),
      await appState.communicator!.getMf1DetectionCount(),
    );
  }

  Future<void> updateDetectionStatus() async {
    var (mode, count) = await getMf1DetectionStatus();

    setState(() {
      isDetectionMode = mode;
      detectionCount = count;
    });
  }

  Future<void> handleMfkeyCalculation() async {
    var appState = context.read<ChameleonGUIState>();

    var count = await appState.communicator!.getMf1DetectionCount();
    var detections = await appState.communicator!.getMf1DetectionResult(count);
    for (var item in detections.entries) {
      var uid = item.key;
      for (var item in item.value.entries) {
        var block = item.key;
        for (var item in item.value.entries) {
          var key = item.key;
          for (var i = 0; i < item.value.length; i++) {
            for (var j = i + 1; j < item.value.length; j++) {
              var item0 = item.value[i];
              var item1 = item.value[j];
              var mfkey = Mfkey32Dart(
                uid: uid,
                nt0: item0.nt,
                nt1: item1.nt,
                nr0Enc: item0.nr,
                ar0Enc: item0.ar,
                nr1Enc: item1.nr,
                ar1Enc: item1.ar,
              );
              var recoveredKey = await recovery.mfkey32(mfkey);
              keys.add(u64ToBytes((recoveredKey)[0]).sublist(2, 8));
              outputUid =
                  bytesToHex(u64ToBytes(uid).sublist(4, 8)).toUpperCase();
              if (!displayedKeys.contains(Object.hashAll(
                  u64ToBytes((recoveredKey)[0]).sublist(4, 8)))) {
                displayKeys.add(Row(
                  children: [
                    Text(
                      bytesToHex(u64ToBytes(uid).sublist(4, 8)).toUpperCase(),
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(width: 8.0),
                    TextButton(
                      onPressed: () async {
                        ClipboardData data = ClipboardData(
                            text: bytesToHex(
                                    u64ToBytes((recoveredKey)[0]).sublist(2, 8))
                                .toUpperCase());
                        await Clipboard.setData(data);
                      },
                      child: Text(
                        "block $block key $key: ${bytesToHex(u64ToBytes((recoveredKey)[0]).sublist(2, 8)).toUpperCase()}",
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ));
                displayedKeys.add(Object.hashAll(
                    u64ToBytes((recoveredKey)[0]).sublist(4, 8)));
              }
              setState(() {
                displayKeys = displayKeys;
                progress = (i * 100 / item.value.length).round();
              });
              appState.forceMfkey32Page = true;
              appState.changesMade();
            }
          }
        }
      }
    }
  }

  List<Uint8List> deduplicateKeys(List<Uint8List> keys) {
    return <int, Uint8List>{for (var key in keys) Object.hashAll(key): key}
        .values
        .toList();
  }

  String convertKeysToDictFile(List<Uint8List> keys) {
    List<Uint8List> deduplicatedKeys = deduplicateKeys(keys);
    String fileContents = "";
    for (Uint8List key in deduplicatedKeys) {
      fileContents += "${bytesToHex(key).toUpperCase()}\n";
    }
    return fileContents;
  }

  // ignore_for_file: use_build_context_synchronously
  @override
  Widget build(BuildContext context) {
    var localizations = AppLocalizations.of(context)!;
    return FutureBuilder(
      future: detectionStatusFuture,
      builder: (BuildContext context, AsyncSnapshot snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Scaffold(
            appBar: AppBar(
              title: const Text('Mfkey32'),
            ),
            body: const Center(child: CircularProgressIndicator()),
          );
        } else if (snapshot.hasError) {
          return Text('${localizations.error}: ${snapshot.error}');
        } else {
          if (detectionCount == -1) {
            updateDetectionStatus();
            return Scaffold(
              appBar: AppBar(
                title: const Text('Mfkey32'),
              ),
              body: const Center(child: CircularProgressIndicator()),
            );
          }

          return Scaffold(
            appBar: AppBar(
              title: const Text('Mfkey32'),
            ),
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  mainAxisSize: MainAxisSize.max,
                  children: [
                    Text(
                      localizations.recover_keys_via("Mfkey32"),
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 25.0),
                    loading
                        ? OutlinedButton(
                            onPressed: null,
                            child: Text(localizations
                                .recover_keys_nonce(detectionCount)),
                          )
                        : ElevatedButton(
                            onPressed: (detectionCount > 0)
                                ? () async {
                                    setState(() {
                                      loading = true;
                                    });
                                    await handleMfkeyCalculation();
                                    setState(() {
                                      saveKeys = true;
                                      loading = false;
                                      progress = -1;
                                    });
                                  }
                                : null,
                            child: Text(localizations
                                .recover_keys_nonce(detectionCount)),
                          ),
                    const SizedBox(height: 8.0),
                    Visibility(
                      visible: saveKeys,
                      child: ElevatedButton(
                        onPressed: () {
                          showDialog<String>(
                              context: context,
                              builder: (BuildContext context) => AlertDialog(
                                    title:
                                        Text(localizations.save_recovered_keys),
                                    content: Text(localizations
                                        .save_recovered_keys_where),
                                    actions: [
                                      ElevatedButton(
                                        onPressed: () async {
                                          String fileContents =
                                              convertKeysToDictFile(keys);
                                          try {
                                            await FileSaver.instance.saveAs(
                                                name: outputUid,
                                                bytes: const Utf8Encoder()
                                                    .convert(fileContents),
                                                ext: 'dic',
                                                mimeType: MimeType.other);
                                          } on UnimplementedError catch (_) {
                                            String? outputFile =
                                                await FilePicker.platform
                                                    .saveFile(
                                              dialogTitle:
                                                  '${localizations.output_file}:',
                                              fileName: '$outputUid.dic',
                                            );
                                            if (outputFile != null) {
                                              var file = File(outputFile);
                                              await file.writeAsBytes(
                                                  const Utf8Encoder()
                                                      .convert(fileContents));
                                            }
                                          }
                                          Navigator.pop(context);
                                        },
                                        child: Text(localizations
                                            .save_recovered_keys_to_file),
                                      ),
                                      ElevatedButton(
                                        onPressed: () async {
                                          await dictSelectDialog(
                                              context, deduplicateKeys(keys));
                                          Navigator.pop(context);
                                        },
                                        child: Text(localizations
                                            .add_recovered_keys_to_existing_dict),
                                      ),
                                      ElevatedButton(
                                        onPressed: () async {
                                          Dictionary dict = Dictionary(
                                            name: outputUid,
                                            color: Colors.blue,
                                            keys: deduplicateKeys(keys),
                                          );
                                          await showDialog<String>(
                                            context: context,
                                            builder: (BuildContext context) {
                                              return DictionaryEditMenu(
                                                  dict: dict, isNew: true);
                                            },
                                          );
                                          Navigator.pop(context);
                                        },
                                        child: Text(localizations
                                            .create_new_dict_with_recovered_keys),
                                      ),
                                    ],
                                  ));
                        },
                        child: Text(localizations.save_recovered_keys),
                      ),
                    ),
                    const SizedBox(height: 16.0),
                    Expanded(
                      child: ListView(
                        children: [
                          ...displayKeys,
                          loading
                              ? const Center(child: CircularProgressIndicator())
                              : const SizedBox(),
                          loading
                              ? const SizedBox(height: 8.0)
                              : const SizedBox(),
                          loading
                              ? Center(
                                  child:
                                      Text(localizations.recovery_in_progress))
                              : const SizedBox(),
                        ],
                      ),
                    ),
                    if (progress != -1)
                      LinearProgressIndicator(
                        value: (progress / 100).toDouble(),
                      )
                  ],
                ),
              ),
            ),
          );
        }
      },
    );
  }

  Future<String?> dictSelectDialog(BuildContext context, List<Uint8List> keys) {
    var appState = context.read<ChameleonGUIState>();
    var dicts = appState.sharedPreferencesProvider.getDictionaries();

    dicts.sort((a, b) => a.name.compareTo(b.name));

    return showSearch<String>(
      context: context,
      delegate: DictSearchDelegate(dicts, keys),
    );
  }
}

class DictSearchDelegate extends SearchDelegate<String> {
  final List<Dictionary> dicts;
  final List<Uint8List> keys;

  DictSearchDelegate(this.dicts, this.keys);

  @override
  List<Widget> buildActions(BuildContext context) {
    return [
      IconButton(
        icon: const Icon(Icons.clear),
        onPressed: () {
          query = '';
        },
      ),
    ];
  }

  @override
  Widget buildLeading(BuildContext context) {
    return IconButton(
      icon: const Icon(Icons.arrow_back),
      onPressed: () {
        close(context, '');
      },
    );
  }

  @override
  Widget buildResults(BuildContext context) {
    final results = dicts
        .where((dict) => dict.name.toLowerCase().contains(query.toLowerCase()));

    return ListView.builder(
      itemCount: results.length,
      itemBuilder: (BuildContext context, int index) {
        final dict = results.elementAt(index);
        return ListTile(
          leading: Icon(Icons.key, color: dict.color),
          title: Text(dict.name),
          subtitle: Text("${dict.keys.length.toString()} keys"),
          onTap: () async {},
        );
      },
    );
  }

  @override
  Widget buildSuggestions(BuildContext context) {
    final results = dicts
        .where((dict) => dict.name.toLowerCase().contains(query.toLowerCase()));

    var appState = context.read<ChameleonGUIState>();
    return ListView.builder(
      itemCount: results.length,
      itemBuilder: (BuildContext context, int index) {
        final dict = results.elementAt(index);
        return ListTile(
          leading: Icon(Icons.key, color: dict.color),
          title: Text(dict.name),
          subtitle: Text("${dict.keys.length.toString()} keys"),
          onTap: () async {
            dict.keys.addAll(keys);
            appState.sharedPreferencesProvider.setDictionaries(dicts);
            appState.changesMade();
            Navigator.pop(context);
          },
        );
      },
    );
  }
}
