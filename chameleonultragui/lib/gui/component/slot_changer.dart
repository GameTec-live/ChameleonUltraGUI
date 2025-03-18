import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:chameleonultragui/bridge/chameleon.dart';
import 'package:chameleonultragui/main.dart';

// Localizations
import 'package:chameleonultragui/generated/i18n/app_localizations.dart';

class SlotChanger extends StatefulWidget {
  const SlotChanger({super.key});

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
    var appState = context.read<ChameleonGUIState>();
    List<SlotTypes> usedSlots;

    try {
      usedSlots = await appState.communicator!.getSlotTagTypes();
    } catch (_) {
      usedSlots = [];
    }

    return await getSlotIcons(usedSlots);
  }

  Future<List<Icon>> getSlotIcons(List<SlotTypes> usedSlots) async {
    var appState = context.read<ChameleonGUIState>();
    List<Icon> icons = [];

    try {
      selectedSlot = await appState.communicator!.getActiveSlot() + 1;
    } catch (_) {
      selectedSlot = 1;
    }

    if (usedSlots.isEmpty) {
      return [const Icon(Icons.warning)];
    }

    for (int i = 0; i < 8; i++) {
      if (i == selectedSlot - 1) {
        icons.add(const Icon(
          Icons.circle_outlined,
          color: Colors.red,
        ));
      } else if (usedSlots[i].notMatch()) {
        icons.add(const Icon(Icons.circle));
      } else {
        icons.add(const Icon(Icons.circle_outlined));
      }
    }
    return icons;
  }

  List<Icon> presold = [
    const Icon(Icons.circle_outlined),
    const Icon(Icons.circle_outlined),
    const Icon(Icons.circle_outlined),
    const Icon(Icons.circle_outlined),
    const Icon(Icons.circle_outlined),
    const Icon(Icons.circle_outlined),
    const Icon(Icons.circle_outlined),
    const Icon(Icons.circle_outlined),
  ];

  @override
  Widget build(BuildContext context) {
    var appState = context.read<ChameleonGUIState>();
    var localizations = AppLocalizations.of(context)!;
    return FutureBuilder(
        future: getFutureData(),
        builder: (BuildContext context, AsyncSnapshot snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton(
                  onPressed: () async {},
                  icon: const Icon(Icons.arrow_back),
                ),
                ...presold,
                IconButton(
                  onPressed: () async {},
                  icon: const Icon(Icons.arrow_forward),
                ),
              ],
            );
          } else if (snapshot.hasError) {
            appState.connector!.performDisconnect();
            return Text('${localizations.error}: ${snapshot.error.toString()}');
          } else {
            final slotIcons = snapshot.data;
            presold = slotIcons;

            return Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton(
                  onPressed: () async {
                    if (selectedSlot > 1) {
                      await appState.communicator!
                          .activateSlot(selectedSlot - 2);
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
                      await appState.communicator!.activateSlot(selectedSlot);
                      setState(() {});
                      appState.changesMade();
                    }
                  },
                  icon: const Icon(Icons.arrow_forward),
                ),
              ],
            );
          }
        });
  }
}
