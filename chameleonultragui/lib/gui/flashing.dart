import 'package:flutter/material.dart';

class FlashingPage extends StatelessWidget {
  const FlashingPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Chameleon DFU'),
      ),
      body: const Center(child: Text("Chameleon is flashing...")),
    );
  }
}
