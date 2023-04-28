import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:serial_communication/serial_communication.dart'; // Android
import 'package:flutter_libserialport/flutter_libserialport.dart'; // Everyone Else

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (context) => MyAppState(),
      child: MaterialApp(
        title: 'Chameleon Unltra GUI',
        theme: ThemeData(
          useMaterial3: true,
          colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepOrange),
        ),
        home: const MyHomePage(),
      ),
    );
  }
}

class MyAppState extends ChangeNotifier {
  bool onandroid = Platform.isAndroid;
  var chameleon;
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key});

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  var selectedIndex = 0;

  @override
  Widget build(BuildContext context) {
    var appState = context.watch<MyAppState>();
    if (appState.onandroid) {
      appState.chameleon = CommmoduleAndroid();
    } else {
      appState.chameleon = CommmodulePC();
    }
    Widget page;
    switch (selectedIndex) {
      case 0:
        page = const HomePage();
        break;
      case 1:
        page = const Placeholder();
        break;
      case 2:
        page = const Placeholder();
        break;
      case 3:
        page = const Placeholder();
        break;
      case 4:
        page = const Placeholder();
        break;
      case 5:
        page = const Placeholder();
        break;
      default:
        throw UnimplementedError('no widget for $selectedIndex');
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        return Scaffold(
          body: Row(
            children: [
              SafeArea(
                child: NavigationRail(
                  extended: constraints.maxWidth >= 600,
                  destinations: const [
                    NavigationRailDestination(
                      icon: Icon(Icons.home),
                      label: Text('Home'),
                    ),
                    NavigationRailDestination(
                      icon: Icon(Icons.widgets),
                      label: Text('Slot Manager'),
                    ),
                    NavigationRailDestination(
                      icon: Icon(Icons.wifi),
                      label: Text('Live Read/Write'),
                    ),
                    NavigationRailDestination(
                      icon: Icon(Icons.shield),
                      label: Text('Attacks'),
                    ),
                    NavigationRailDestination(
                      icon: Icon(Icons.settings),
                      label: Text('Settings'),
                    ),
                  ],
                  selectedIndex: selectedIndex,
                  onDestinationSelected: (value) {
                    setState(() {
                      selectedIndex = value;
                    });
                  },
                ),
              ),
              Expanded(
                child: Container(
                  color: Theme.of(context).colorScheme.primaryContainer,
                  child: page,
                ),
              ),
            ],
          ),
        );
      }
    );
  }
}

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    var appState = context.watch<MyAppState>();
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text('Chameleon Ultra GUI'),
          Text('Platform: ${Platform.operatingSystem}'),
          Text('Android: ${appState.onandroid}'),
          Text('Chameleon: ${appState.chameleon}'),
          Text('Serial Ports: ${appState.chameleon.availableDevices()}'),
          Text('Serial Port: ${appState.chameleon.port}'),
          Text('Device: ${appState.chameleon.device}'),
          //ElevatedButton(
          //  onPressed: () {
          //    appState.chameleon.connectDevice("/dev/ttyUSB0");
          //  },
          //  child: const Text('Connect'),
          //),
          ElevatedButton(
            onPressed: () {
              appState.chameleon.sendcommand("test");
            },
            child: const Text('Send'),
          ),
        ],
      ),
    );
  }
}

/*
class GeneratorPage extends StatelessWidget {
  const GeneratorPage({super.key});

  @override
  Widget build(BuildContext context) {
    var appState = context.watch<MyAppState>();
    /*var pair = appState.current;

    IconData icon;
    if (appState.favorites.contains(pair)) {
      icon = Icons.favorite;
    } else {
      icon = Icons.favorite_border;
    }*/

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          BigCard(pair: "AB"),
          const SizedBox(height: 10),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              ElevatedButton.icon(
                onPressed: () {
                  //appState.toggleFavorite();
                },
                icon: Icon(Icons.face),
                label: const Text('Like'),
              ),
              const SizedBox(width: 10),
              ElevatedButton(
                onPressed: () {
                  //appState.getNext();
                },
                child: const Text('Next'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}


class BigCard extends StatelessWidget {
  const BigCard({
    super.key,
    required this.pair,
  });

  final String pair;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final style = theme.textTheme.displayMedium!.copyWith(
      color: theme.colorScheme.onPrimary,
    );
    return Card(
      color: theme.colorScheme.primary,
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Text(pair, style: style),
      ),
    );
  }
}

class FavoritesPage extends StatelessWidget {
  const FavoritesPage({super.key});

  @override
  Widget build(BuildContext context) {
    var appState = context.watch<MyAppState>();

    return ListView(
      children: const [
        Text('Empty'),
      ],
    );
  }
}*/

class CommmodulePC {
  SerialPort ?port;
  String ?device;
  List availableDevices() {
    return SerialPort.availablePorts;
  }

  void connectDevice(String adress) {
    port = SerialPort(adress);
  }

  void sendcommand(String command){
    print(command);
    print(port);
  }
} 

class CommmoduleAndroid {
  
}

// https://pub.dev/packages/flutter_libserialport/example
// https://github.com/altera2015/usbserial