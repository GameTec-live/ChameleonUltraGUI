import 'package:chameleonultragui/chameleon/connector.dart';
import 'package:chameleonultragui/helpers/general.dart';
import 'package:chameleonultragui/main.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class Mfkey32Page extends StatefulWidget {
  const Mfkey32Page({super.key});

  @override
  _Mfkey32PageState createState() => _Mfkey32PageState();
}

class _Mfkey32PageState extends State<Mfkey32Page> {
  @override
  Widget build(BuildContext context) {
    var appState = context.watch<MyAppState>();
    var connection = ChameleonCom(port: appState.chameleon);

    return FutureBuilder(
      future: connection.isMf1DetectionMode(),
      builder: (BuildContext context, AsyncSnapshot snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Scaffold(
              appBar: AppBar(
                title: const Text('Mfkey32'),
              ),
              body: const Center(child: CircularProgressIndicator()));
        } else if (snapshot.hasError) {
          return Text('Error: ${snapshot.error}');
        } else {
          final result = snapshot.data;
          print(result);

          return Scaffold(
            appBar: AppBar(
              title: const Text('Mfkey32'),
            ),
            body: const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center, // Center
                children: [],
              ),
            ),
          );
        }
      },
    );
  }
}
