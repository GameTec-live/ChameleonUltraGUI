import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../main.dart';

class HomePage extends StatelessWidget {
  // Home Page
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    var appState = context.watch<MyAppState>(); // Get State

    return Center(
      // Todo: Implement Homepage
      child: Column(
          mainAxisAlignment: MainAxisAlignment.center, // Center
          children: [
            Align(
              alignment: Alignment.topRight,
              child: IconButton(
                onPressed: () {
                  // Disconnect
                  appState.changesMade();
                },
                icon: const Icon(Icons.close),
              ),
            ),
            const CircularProgressIndicator.adaptive(),
          ]),
    );
  }
}
