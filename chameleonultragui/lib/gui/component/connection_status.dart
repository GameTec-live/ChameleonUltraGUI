import 'package:flutter/material.dart';

class ConnectionStatus extends StatelessWidget {
  const ConnectionStatus({
    super.key,
    required this.connected,
    required this.connecting,
  });

  final bool connected;
  final bool connecting;

  @override
  Widget build(BuildContext context) {
    final label = connected
        ? '已连接'
        : connecting
        ? '正在连接…'
        : '等待设备…';

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const SizedBox(
            width: 44,
            height: 44,
            child: CircularProgressIndicator(strokeWidth: 3),
          ),
          const SizedBox(height: 18),
          Text(label, style: const TextStyle(fontSize: 16)),
        ],
      ),
    );
  }
}
