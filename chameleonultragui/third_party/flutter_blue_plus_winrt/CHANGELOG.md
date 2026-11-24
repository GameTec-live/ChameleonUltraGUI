## 0.0.23
* Fix: a restarted scan found nothing until the app restarted. startScan now waits for a stopping watcher to stop before starting it again.

## 0.0.22
* Write without response now completes once the stack has the packet, as on Android and Darwin, instead of after the send. Back-to-back writes no longer wait a connection event each (Windows 10 FOTA 7.8 -> 10 KB/s).

## 0.0.21
* Fix: MTU stayed 23 again (the GattSession was never opened). Connect now opens it and reports the negotiated MTU, then every change.
* Windows 11: request ThroughputOptimized connection parameters while connected.

## 0.0.18
* Fix multithreading & connection stability (#5)

## 0.0.17
* Fix: Initialize `manufacturer_data` map correctly (#10)

## 0.0.16
* Fix: MTU was always 23 on Windows. Now reports negotiated MTU correctly.

## 0.0.15
* Fix: missing runtimeobject.lib (#7)

## 0.0.14
* Improve: `systemDevices` now discovers both paired and connected devices.
* Fix: Build error (unused variable warning) in `flutterRestart`.

## 0.0.13
* Feat: Add bonding support and improve connection logic.

## 0.0.12
* Fix: Resolve extensive compilation errors (C2220, C2065, C2653, C4456) caused by scope resolution and variable shadowing in GATT discovery logic.
* Fix: `readRssi` now handles cache misses gracefully by returning 0 instead of throwing an exception when RSSI is not in the cache.

## 0.0.11
* Refactor characteristic lookup and fix memory management.

## 0.0.10
* Fix: ensure memory resources (like RSSI cache) are properly cleared upon disconnection.

## 0.0.9
* Fix: "vector erase iterator outside range" crash by safely handling device closure to avoid synchronous vector modifications.

## 0.0.8
* Fix: ensure `connect` method waits for actual physical connection completion before returning a result.

## 0.0.7
* Fix: ensure `connect` returns `false` on failure instead of throwing an exception.
* Improvement: refined connection state waiting logic for better reliability.

## 0.0.6
* Fix: ensure `connect` method waits for actual physical connection completion before returning a result.
* Fix: enhanced thread safety during rapid connection and disconnection to prevent `vector erase` crashes.
* Improvement: more robust resource cleanup when connection attempts fail.

## 0.0.5
* Fix: compilation errors (C2220) and typos in method signatures.

## 0.0.4
* Fix: crash during connection/disconnection caused by invalid vector iterators.
* Feature: add `setOptions` implementation.

## 0.0.3
* Fix: ensure physical disconnection by explicitly closing all GATT services.
* Fix: potential race condition where a device might stay connected if disconnected during the connection process.
* Fix: properly clear characteristic and descriptor caches upon disconnection.

## 0.0.2
* Fix: a version issue with `flutter_blue_plus_platform_interface` #1

## 0.0.1
* Initial release.
