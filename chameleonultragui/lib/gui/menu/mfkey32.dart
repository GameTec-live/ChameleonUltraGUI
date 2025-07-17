import 'package:chameleonultragui/gui/menu/dictionary_export.dart';
import 'package:chameleonultragui/helpers/general.dart';
import 'package:chameleonultragui/main.dart';
import 'package:chameleonultragui/recovery/recovery.dart';
import 'package:chameleonultragui/recovery/recovery.dart' as recovery;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter/services.dart';

// Localizations
import 'package:chameleonultragui/generated/i18n/app_localizations.dart';

class Mfkey32Menu extends StatefulWidget {
  const Mfkey32Menu({super.key});

  @override
  Mfkey32MenuState createState() => Mfkey32MenuState();
}

class Mfkey32MenuState extends State<Mfkey32Menu> {
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
            }
          }
        }
      }
    }
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
                              builder: (BuildContext context) =>
                                  DictionaryExportMenu(
                                      defaultName: outputUid, keys: keys));
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
}