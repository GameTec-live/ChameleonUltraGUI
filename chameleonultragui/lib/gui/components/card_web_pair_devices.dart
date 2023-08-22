
import 'package:flutter/material.dart';

class CardWebPairDevices extends StatelessWidget {
  final VoidCallback? onPairDevices;

  const CardWebPairDevices({super.key, this.onPairDevices});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18.0),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Pair devices',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 4),
            const Text(
              'Due to the browser security model in Chrome you first need to pair your Chameleon devices before they will show here.',
              textAlign: TextAlign.justify,
            ),
            const SizedBox(height: 4),
            const Text(
              'If you need to pair new devices later on, f.e. after you switch your device to DFU mode to flash the firmware, use the pair button in the upper right corner.',
              textAlign: TextAlign.justify,
            ),
            if (onPairDevices != null)
              const SizedBox(height: 8),
            if (onPairDevices != null)
              FilledButton(
                onPressed: () {
                  onPairDevices!();
                },
                child: const Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Icon(Icons.handshake),
                    SizedBox(width: 8),
                    Text('Pair devices'),
                  ]
                )
              )
          ]
        )
      )
    );
  }
}