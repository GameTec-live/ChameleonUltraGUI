import 'dart:developer';
import 'dart:io';
import 'dart:typed_data';
import 'package:chameleonultragui/chameleon/connector.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../main.dart';

class HomePage extends StatelessWidget {
  // Home Page
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    var appState = context.watch<MyAppState>(); // Get State
    var cml = ChameleonCom(port: appState.chameleon);

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center, // Center
        children: [
          Align(
            alignment: Alignment.topRight,
            child: IconButton(
              onPressed: () {
                // Disconnect
                appState.chameleon.performDisconnect();
                appState.changesMade();
              },
              icon: const Icon(Icons.close),
            ),
          ),
          const Text('Chameleon Ultra GUI'), // Display dummy / debug info
          Text('Platform: ${Platform.operatingSystem}'),
          Text('Android: ${appState.onAndroid}'),
          Text('Serial protocol : ${appState.chameleon}'),
          Text('Serial devices: ${appState.chameleon.availableDevices()}'),
          Text('Chameleon connected: ${appState.chameleon.connected}'),
          Text('Chameleon device type: ${appState.chameleon.device}'),
          ElevatedButton(
            // Connect Button
            onPressed: () {
              appState.chameleon.preformConnection();
              appState.changesMade();
            },
            child: const Text('Connect'),
          ),
          ElevatedButton(
            // Send Button
            onPressed: () {
              // appState.chameleon.sendCommand("test");
            },
            child: const Text('Send'),
          ),
          ElevatedButton(
            // Send Button
            onPressed: () async {
              await cml.setReaderDeviceMode(true);
              print(
                  "Reader mode (should be true): ${await cml.isReaderDeviceMode()}");
              var card = await cml.scan14443aTag();
              print('Card UID: ${card!.UID}');
              print('SAK: ${card.SAK}');
              print('ATQA: ${card.ATQA}');
            },
            child: const Column(children: [
              Text('Read card'),
            ]),
          ),
          ElevatedButton(
            // Send Button
            onPressed: () async {
              await cml.setReaderDeviceMode(true);
              print(await cml.detectMf1Support());
            },
            child: const Column(children: [
              Text('Is MFC?'),
            ]),
          ),
          ElevatedButton(
            // Send Button
            onPressed: () async {
              await cml.setReaderDeviceMode(true);
              print(await cml.getMf1NTLevel());
            },
            child: const Column(children: [
              Text('Get NT level'),
            ]),
          ),
          ElevatedButton(
            // Send Button
            onPressed: () async {
              await cml.setReaderDeviceMode(true);
              print(await cml.checkMf1Darkside());
            },
            child: const Column(children: [
              Text('Check darkside'),
            ]),
          ),
          ElevatedButton(
            // Send Button
            onPressed: () async {
              await cml.setReaderDeviceMode(true);
              var distance = await cml.getMf1NTDistance(0, 0x60,
                  Uint8List.fromList([0xA0, 0xA1, 0xA2, 0xA3, 0xA4, 0xA5]));
              print("UID: ${distance!.UID}");
              print("Distance ${distance.distance}");
            },
            child: const Column(children: [
              Text('Get distance'),
            ]),
          ),
          ElevatedButton(
            // Send Button
            onPressed: () async {
              await cml.setReaderDeviceMode(true);
              var nonces = await cml.getMf1NestedNonces(
                  0,
                  0x60,
                  Uint8List.fromList([0xA0, 0xA1, 0xA2, 0xA3, 0xA4, 0xA5]),
                  0,
                  0x61);
              inspect(nonces);
              // print("UID: ${distance!.UID}");
              // print("Distance ${distance.distance}");
            },
            child: const Column(children: [
              Text('Run nested attack'),
            ]),
          ),
          ElevatedButton(
            // Send Button
            onPressed: () async {
              await cml.setReaderDeviceMode(true);
              var data = await cml.getMf1Darkside(0x03, 0x60, true, 15);
              inspect(data);
              data = await cml.getMf1Darkside(0x03, 0x60, false, 15);
              inspect(data);
            },
            child: const Column(children: [
              Text('Run darkside attack'),
            ]),
          ),
          ElevatedButton(
            // Send Button
            onPressed: () async {
              await cml.setReaderDeviceMode(true);
              var data = await cml.mf1Auth(0x03, 0x60,
                  Uint8List.fromList([0xA0, 0xA1, 0xA2, 0xA3, 0xA4, 0xA5]));
              print(data);
              var block = await cml.mf1ReadBlock(0x02, 0x60,
                  Uint8List.fromList([0xA0, 0xA1, 0xA2, 0xA3, 0xA4, 0xA5]));
              print(block);
              block![0] = 0xFF;
              await cml.mf1WriteBlock(
                  0x02,
                  0x60,
                  Uint8List.fromList([0xA0, 0xA1, 0xA2, 0xA3, 0xA4, 0xA5]),
                  block);
              block = await cml.mf1ReadBlock(0x02, 0x60,
                  Uint8List.fromList([0xA0, 0xA1, 0xA2, 0xA3, 0xA4, 0xA5]));
              print(block);
            },
            child: const Column(children: [
              Text('Auth/read/write'),
            ]),
          ),
          ElevatedButton(
            // Send Button
            onPressed: () async {
              await cml.setReaderDeviceMode(true);
              print(
                  "Reader mode (should be true): ${await cml.isReaderDeviceMode()}");
              var card = await cml.scan14443aTag();
              print('Card UID: ${card!.UID}');
              print('SAK: ${card.SAK}');
              print('ATQA: ${card.ATQA}');
              await cml.setReaderDeviceMode(false);
              await cml.setMf1AntiCollision(card);
            },
            child: const Column(children: [
              Text('Copy card UID to emulator'),
            ]),
          ),
          ElevatedButton(
            // Send Button
            onPressed: () async {
              var name = await cml.getSlotTagName(1, ChameleonTagFrequiency.hf);
              print(name);
              await cml.setSlotTagName(
                  1, "Hello 变色龙!", ChameleonTagFrequiency.hf);
              name = await cml.getSlotTagName(1, ChameleonTagFrequiency.hf);
              print(name);
            },
            child: const Column(children: [
              Text('Test naming'),
            ]),
          ),
        ],
      ),
    );
  }
}
