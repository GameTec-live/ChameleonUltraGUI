import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:chameleonultragui/bridge/chameleon.dart';
import 'package:chameleonultragui/main.dart';

class SlotChanger extends StatefulWidget {
  const SlotChanger({Key? key}) : super(key: key);

  @override
  SlotChangerState createState() => SlotChangerState();
}

class SlotChangerState extends State<SlotChanger> {
  var selectedSlot = 1;

  @override
  void initState() {
    super.initState();
  }

  Future<List<Icon>> getFutureData() async {
    var appState = context.read<MyAppState>();
    var connection = ChameleonCom(port: appState.connector);
    List<(ChameleonTag, ChameleonTag)> usedSlots;
    try {
      usedSlots = await connection.getUsedSlots();
    } catch (_) {
      usedSlots = [];
    }

    return await getSlotIcons(connection, usedSlots);
  }

  Future<List<Icon>> getSlotIcons(ChameleonCom connection,
      List<(ChameleonTag, ChameleonTag)> usedSlots) async {
    List<Icon> icons = [];
    try {
      selectedSlot = await connection.getActiveSlot() + 1;
    } catch (_) {
      selectedSlot = 1;
    }
    for (int i = 1; i < 9; i++) {
      if (i == selectedSlot) {
        icons.add(const Icon(
          Icons.circle_outlined,
          color: Colors.red,
        ));
      } else if (false) {
        icons.add(const Icon(Icons.circle));
      } else {
        icons.add(const Icon(Icons.circle_outlined));
      }
    }
    return icons;
  }

  @override
  Widget build(BuildContext context) {
    var appState = context.read<MyAppState>();
    var connection = ChameleonCom(port: appState.connector);

    return FutureBuilder(
      future: getFutureData(),
      builder: (BuildContext context, AsyncSnapshot snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        } else if (snapshot.hasError) {
          appState.connector.preformDisconnect();
          return Text('Error: ${snapshot.error.toString()}');
        } else {
          final slotIcons = snapshot.data;

          return Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(
                onPressed: () async {
                  if (selectedSlot > 1) {
                    await connection.activateSlot(selectedSlot - 2);
                    setState(() {});
                    appState.changesMade();
                  }
                },
                icon: const Icon(Icons.arrow_back),
              ),
              ...slotIcons,
              IconButton(
                onPressed: () async {
                  if (selectedSlot < 8) {
                    await connection.activateSlot(selectedSlot);
                    setState(() {});
                    appState.changesMade();
                  }
                },
                icon: const Icon(Icons.arrow_forward),
              ),
            ],
          );
        }
      }
    );
  }
}