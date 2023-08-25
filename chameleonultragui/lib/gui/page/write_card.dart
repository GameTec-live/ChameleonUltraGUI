import 'package:flutter/material.dart';

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
    return Scaffold(
      appBar: AppBar(
        title: const Text('Write Card'),
      ),
      body: Column(
        children: [
          Center(
            child: Text('Write Card Page'),
          ),
        ],
      ),
    );
  }
}
