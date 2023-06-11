import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../main.dart';

class HomePage extends StatelessWidget {
  // Home Page
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    var appState = context.watch<MyAppState>(); // Get State

    return Scaffold(
      appBar: AppBar(
        title: const Text('Home'),
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center, // Center
          children: [
            Align(
              alignment: Alignment.topRight,
              child: Padding(
                padding: const EdgeInsets.all(8.0),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        IconButton(
                          onPressed: () {
                            // Disconnect
                            appState.chameleon.performDisconnect();
                            appState.changesMade();
                          },
                          icon: const Icon(Icons.close),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    const Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        Text("COM11",style: TextStyle(fontSize: 20)),
                        Icon(Icons.usb),
                        Icon(Icons.battery_3_bar_rounded),
                      ],
                    ),

                  ],
                ),
              ),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [Text("Chameleon Ultra",style: TextStyle(fontWeight: FontWeight.bold, fontSize: MediaQuery.of(context).size.width / 25)),],
            ),
            const SizedBox(height: 20),
            Text("Used Slots: 2/8",style: TextStyle(fontSize: MediaQuery.of(context).size.width / 50)),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton(
                  onPressed: () {},
                  icon: const Icon(Icons.arrow_back),
                ),
                const Icon(Icons.circle_outlined, color: Colors.red,),
                const Icon(Icons.circle),
                const Icon(Icons.circle_outlined),
                const Icon(Icons.circle_outlined),
                const Icon(Icons.circle_outlined),
                const Icon(Icons.circle),
                const Icon(Icons.circle_outlined),
                const Icon(Icons.circle_outlined),
                IconButton(
                  onPressed: () {},
                  icon: const Icon(Icons.arrow_forward),
                ),
              ],
            ),
            Expanded(child: FractionallySizedBox(
              widthFactor: 0.4,
              child: Image.asset('assets/black-ultra-standing-front.png', fit: BoxFit.contain,),
            ),),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text("Firmware Version: ",style: TextStyle(fontWeight: FontWeight.bold, fontSize: MediaQuery.of(context).size.width / 50)),
                Text("1.0.0",style: TextStyle(fontSize: MediaQuery.of(context).size.width / 50)),
              ],
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text("Memory Usage: ",style: TextStyle(fontWeight: FontWeight.bold, fontSize: MediaQuery.of(context).size.width / 50)),
                Text("10/40",style: TextStyle(fontSize: MediaQuery.of(context).size.width / 50)),
              ],
            ),
            Align(
              alignment: Alignment.bottomRight,
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: IconButton(
                      onPressed: () {
                        // Device Settings (DFU, etc)
                        appState.changesMade();
                      },
                      icon: const Icon(Icons.settings),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
