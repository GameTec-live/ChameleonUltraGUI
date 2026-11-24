import 'package:chameleonultragui/helpers/ble_status.dart';
import 'package:flutter/material.dart';

class ConnectionStatus extends StatelessWidget {
  const ConnectionStatus({
    super.key,
    required this.connected,
    required this.connecting,
  });

  final bool connected;
  final bool connecting;

  String _label(BlePhase phase) {
    if (connected) {
      return '已连接';
    }
    switch (phase) {
      case BlePhase.pinRequired:
        return '需要输入 PIN';
      case BlePhase.pinError:
        return 'PIN 错误';
      case BlePhase.failedRetrying:
        return '连接失败，重试中…';
      case BlePhase.connecting:
        return '正在连接…';
      case BlePhase.waiting:
        break;
    }
    return connecting ? '正在连接…' : '等待设备…';
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<BlePhase>(
      valueListenable: BleStatus.phase,
      builder: (context, phase, _) {
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
              Text(_label(phase), style: const TextStyle(fontSize: 16)),
            ],
          ),
        );
      },
    );
  }
}
