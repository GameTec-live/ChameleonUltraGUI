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

    return const Center( // Todo: Implement Homepage
      child: SizedBox(
        width: 30,
        height: 30,
        child: CircularProgressIndicator()
        )
    );
  }
}
