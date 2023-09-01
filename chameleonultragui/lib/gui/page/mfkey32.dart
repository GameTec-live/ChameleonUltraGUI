import 'dart:typed_data';
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
import 'package:uuid/uuid.dart';
import 'package:chameleonultragui/gui/menu/dictionary_edit.dart';
import 'package:chameleonultragui/sharedprefsprovider.dart';

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

    var detections = await appState.communicator!.getMf1DetectionResult(0);
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
              keys.add(
                  u64ToBytes((await recovery.mfkey32(mfkey))[0]).sublist(2, 8));
              controller.text +=
                  "\nUID: ${bytesToHex(u64ToBytes(uid).sublist(4, 8)).toUpperCase()} block $block key $key: ${bytesToHex(u64ToBytes((await recovery.mfkey32(mfkey))[0]).sublist(2, 8)).toUpperCase()}";
              controller.text = controller.text.trim();
              appState.forceMfkey32Page = true;
              appState.changesMade();
            }
          }
        }
      }
    }
  }

  List<Uint8List> deduplicateKeys(List<Uint8List> keys) {
    return <int, Uint8List>{
      for (var v in keys) Object.hashAll(v): v
    }.values.toList();
  }

  String convertUintToDictFile(List<Uint8List> keys) {
    List<Uint8List> dekeys = deduplicateKeys(keys);
    String filecontents = "";
    for (Uint8List key in dekeys) {
      filecontents += "${bytesToHex(key).toUpperCase()}\n";
    }
    return filecontents;
  }

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
                    ElevatedButton(
                      onPressed: (detectionCount > 0)
                          ? () async {
                              await handleMfkeyCalculation();
                              setState(() {
                                saveKeys = true;
                              });
                            }
                          : null,
                      child: Text(
                          localizations.recover_keys_nonce(detectionCount)),
                    ),
                    const SizedBox(height: 8.0),
                    Visibility(
                      visible: saveKeys,
                      child: ElevatedButton(
                        onPressed: () {
                          showDialog<String>(
                              context: context,
                              builder: (BuildContext context) => AlertDialog(
                                    title: Text("Save recovered Keys"),
                                    content: Text(
                                        "Where do you want to save the recovered keys?"),
                                    actions: [
                                      ElevatedButton(
                                        onPressed: () async {
                                          String filecontents =
                                              convertUintToDictFile(keys);
                                          String name = Uuid().v4();
                                          try {
                                            await FileSaver.instance.saveAs(
                                                name: name,
                                                bytes: const Utf8Encoder().convert(filecontents),
                                                ext: 'dict',
                                                mimeType: MimeType.other);
                                          } on UnimplementedError catch (_) {
                                            String? outputFile = await FilePicker.platform.saveFile(
                                              dialogTitle: '${localizations.output_file}:',
                                              fileName: '${name}.dict',
                                            );
                                            if (outputFile != null) {
                                              var file = File(outputFile);
                                              await file.writeAsBytes(const Utf8Encoder().convert(filecontents));
                                            }
                                          }
                                          Navigator.pop(context);
                                        },
                                        child: Text("Save to file"),
                                      ),
                                      ElevatedButton(
                                        onPressed: () async {
                                          await dictSelectDialog(context, deduplicateKeys(keys));
                                          Navigator.pop(context);
                                        },
                                        child: Text(
                                            "Append to existing Dictionary"),
                                      ),
                                      ElevatedButton(
                                        onPressed: () async {
                                          Dictionary dict = Dictionary(
                                            name: "Recovered Keys",
                                            color: Colors.blue,
                                            keys: deduplicateKeys(keys),
                                          );
                                          await showDialog<String>(
                                            context: context,
                                            builder: (BuildContext context) {
                                              return DictionaryEditMenu(dict: dict, isNew: true,);
                                            },
                                          );
                                          Navigator.pop(context);
                                        },
                                        child: Text("Save to new Dictionary"),
                                      ),
                                    ],
                                  ));
                        },
                        child: Text("Save recovered Keys"),
                      ),
                    ),
                    const SizedBox(height: 16.0),
                    Expanded(
                      child: TextField(
                        controller: controller,
                        readOnly: true,
                        keyboardType: TextInputType.multiline,
                        maxLines: null,
                      ),
                    ),
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
      delegate:
          DictSearchDelegate(dicts, keys),
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
    final results = dicts.where((dict) => dict.name.toLowerCase().contains(query.toLowerCase()));

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
    final results = dicts.where((dict) => dict.name.toLowerCase().contains(query.toLowerCase()));

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
