import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

// Localizations
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

class WriteCardPage extends StatefulWidget {
  const WriteCardPage({Key? key}) : super(key: key);

  @override
  WriteCardPageState createState() => WriteCardPageState();
}

class WriteCardPageState extends State<WriteCardPage> {
  @override
  void initState() {
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    var localizations = AppLocalizations.of(context)!;
    return Scaffold(
      appBar: AppBar(
        title: Text(localizations.write_card),
      ),
      body: Column(
        children: [
          Center(child: Text(localizations.not_implemented)),
        ],
      ),
    );
  }
}
