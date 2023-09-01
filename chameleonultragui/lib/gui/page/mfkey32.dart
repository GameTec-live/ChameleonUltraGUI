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
    List<Uint8List> result = [];
    Set<String> set = Set<String>();
    for (Uint8List item in keys) {
      String str = String.fromCharCodes(item);
      if (!set.contains(str)) {
        set.add(str);
        result.add(item);
      }
    }
    return result;
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
                                        onPressed: () {
                                          Navigator.pop(context);
                                        },
                                        child: Text(
                                            "Append to existing Dictionary"),
                                      ),
                                      ElevatedButton(
                                        onPressed: () {
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
}
