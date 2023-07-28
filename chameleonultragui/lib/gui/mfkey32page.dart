import 'package:chameleonultragui/bridge/chameleon.dart';
import 'package:chameleonultragui/helpers/general.dart';
import 'package:chameleonultragui/main.dart';
import 'package:chameleonultragui/recovery/recovery.dart';
import 'package:chameleonultragui/recovery/recovery.dart' as recovery;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class Mfkey32Page extends StatefulWidget {
  const Mfkey32Page({Key? key}) : super(key: key);

  @override
  Mfkey32PageState createState() => Mfkey32PageState();
}

class Mfkey32PageState extends State<Mfkey32Page> {
  final TextEditingController controller = TextEditingController();
  late Future<(bool, int)> detectionStatusFuture;
  bool isDetectionMode = false;
  int detectionCount = 0;

  @override
  void initState() {
    super.initState();
    detectionStatusFuture = getMf1DetectionStatus();
  }

  Future<(bool, int)> getMf1DetectionStatus() async {
    var appState = context.read<MyAppState>();
    var connection = ChameleonCom(port: appState.connector);
    return (
      await connection.isMf1DetectionMode(),
      await connection.getMf1DetectionCount(),
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
    var appState = context.read<MyAppState>();
    var connection = ChameleonCom(port: appState.connector);

    var detections = await connection.getMf1DetectionResult(0);
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
              controller.text +=
                  "\nUID ${bytesToHex(u64ToBytes(uid).sublist(4, 8))} block $block key $key: ${bytesToHex(u64ToBytes((await recovery.mfkey32(mfkey))[0]).sublist(2, 8))}";
              controller.text = controller.text.trim();
              appState.changesMade();
            }
          }
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
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
          return Text('Error: ${snapshot.error}');
        } else {
          final (isDetectionMode, detectionCount) = snapshot.data;

          return Scaffold(
            appBar: AppBar(
              title: const Text('Mfkey32'),
            ),
            body: Center(
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    mainAxisSize: MainAxisSize.max,
                    children: [
                      const Text(
                        'Recover keys via Mfkey32',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 25.0),
                      ElevatedButton(
                        onPressed: () async {
                          var appState = context.read<MyAppState>();
                          var connection =
                              ChameleonCom(port: appState.connector);
                          await connection
                              .setMf1DetectionStatus(!isDetectionMode);
                          await updateDetectionStatus();
                          appState.changesMade();
                        },
                        child: Text(isDetectionMode
                            ? 'Disable Mfkey32 collection'
                            : 'Enable Mfkey32 collection'),
                      ),
                      const SizedBox(height: 16.0),
                      ElevatedButton(
                        onPressed: () {
                          updateDetectionStatus();
                        },
                        child: const Text('Update'),
                      ),
                      const SizedBox(height: 16.0),
                      ElevatedButton(
                        onPressed: (detectionCount > 0)
                            ? () async {
                                await handleMfkeyCalculation();
                              }
                            : null,
                        child: Text('Calculate $detectionCount keys'),
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
            ),
          );
        }
      },
    );
  }
}
