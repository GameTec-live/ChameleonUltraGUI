import 'package:chameleonultragui/connector/windows_route_policy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('WindowsRoutePolicy', () {
    test('startup with USB selects USB and never starts BLE', () {
      final policy = WindowsRoutePolicy();
      final decision = policy.startup(usbFound: true);
      expect(decision.route, WindowsRoute.usb);
      expect(decision.connectUsb, isTrue);
      expect(decision.startBle, isFalse);
      expect(decision.cancelBle, isFalse);
      expect(decision.reason, 'startup-usb');
    });

    test('startup without USB starts BLE', () {
      final policy = WindowsRoutePolicy();
      final decision = policy.startup(usbFound: false);
      expect(decision.route, WindowsRoute.ble);
      expect(decision.connectUsb, isFalse);
      expect(decision.startBle, isTrue);
      expect(decision.reason, 'startup-no-usb');
    });

    test('USB appears during a BLE attempt cancels it in favour of USB', () {
      final policy = WindowsRoutePolicy()..markBleConnected(false);
      final decision = policy.usbAppeared();
      expect(decision.route, WindowsRoute.usb);
      expect(decision.connectUsb, isTrue);
      expect(decision.cancelBle, isTrue);
      expect(decision.reason, 'usb-hotplug');
    });

    test('USB appears during an established BLE session keeps BLE', () {
      final policy = WindowsRoutePolicy()..markBleConnected(true);
      final decision = policy.usbAppeared();
      expect(decision.route, WindowsRoute.ble);
      expect(decision.cancelBle, isFalse);
      expect(decision.connectUsb, isFalse);
      expect(decision.reason, 'ble-session-active');
    });

    test('USB removal resumes BLE listening', () {
      final policy = WindowsRoutePolicy();
      policy.usbAppeared();
      final decision = policy.usbRemoved();
      expect(decision.route, WindowsRoute.ble);
      expect(decision.startBle, isTrue);
      expect(decision.reason, 'usb-removed');
      expect(policy.usbPresent, isFalse);
    });
  });
}