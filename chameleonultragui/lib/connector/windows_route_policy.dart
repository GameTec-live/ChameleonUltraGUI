enum WindowsRoute { usb, ble }

class WindowsRouteDecision {
  const WindowsRouteDecision({
    required this.route,
    required this.reason,
    this.connectUsb = false,
    this.cancelBle = false,
    this.startBle = false,
  });

  final WindowsRoute route;
  final String reason;
  final bool connectUsb;
  final bool cancelBle;
  final bool startBle;
}

/// Pure state machine for Windows USB-over-BLE priority.
class WindowsRoutePolicy {
  bool usbPresent = false;
  bool bleConnected = false;

  WindowsRouteDecision startup({required bool usbFound}) {
    usbPresent = usbFound;
    if (usbFound) {
      return const WindowsRouteDecision(
        route: WindowsRoute.usb,
        reason: 'startup-usb',
        connectUsb: true,
      );
    }
    return const WindowsRouteDecision(
      route: WindowsRoute.ble,
      reason: 'startup-no-usb',
      startBle: true,
    );
  }

  WindowsRouteDecision usbAppeared() {
    usbPresent = true;
    if (bleConnected) {
      return const WindowsRouteDecision(
        route: WindowsRoute.ble,
        reason: 'ble-session-active',
      );
    }
    return const WindowsRouteDecision(
      route: WindowsRoute.usb,
      reason: 'usb-hotplug',
      connectUsb: true,
      cancelBle: true,
    );
  }

  WindowsRouteDecision usbRemoved() {
    usbPresent = false;
    if (bleConnected) {
      return const WindowsRouteDecision(
        route: WindowsRoute.ble,
        reason: 'ble-session-active',
      );
    }
    return const WindowsRouteDecision(
      route: WindowsRoute.ble,
      reason: 'usb-removed',
      startBle: true,
    );
  }

  void markBleConnected(bool connected) {
    bleConnected = connected;
  }
}