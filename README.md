# Chameleon Ultra GUI 1.4.1

A cross-platform graphical interface for the Chameleon Ultra and Chameleon Lite, based on Chameleon Ultra GUI 1.4 upstream and distributed under GPL-3.0.

## Changes from upstream

- Automatic Bluetooth connection: the app keeps scanning in the background and connects when the device advertises; Windows remembers the last device and tries a direct connection.
- USB priority on Windows: startup checks USB first and does not start Bluetooth scanning when a USB Chameleon is present; plugging in USB during a Bluetooth attempt cancels it; unplugging USB resumes Bluetooth listening after about one second.
- System pairing: PIN entry uses the Windows system pairing dialog instead of an in-app PIN dialog; the settings page never displays the PIN and logs never contain it.
- Bluetooth stability: Windows uses Balanced connection parameters, a one-second keep-alive, automatic retries, and releases Bluetooth devices correctly on exit.
- Home page: redesigned as a device status overview that adapts to light/dark themes, every color scheme, and narrow phone layouts, showing the current slot, eight slots, and recent cards.
- Windows fixes: removes serial-port scanning lag on the connect page and remembers window position, size, and maximized state.
- Localization: connection hints and status messages use the existing localization system, with all 27 languages covered.
- Battery: unknown charge is shown as “—” and only a real value below 20% is shown in red; short retries run after the handshake without continuous polling.

## Building

Windows: install Flutter 3.47 or newer and the Visual Studio 2022 “Desktop development with C++” workload.

```powershell
flutter pub get
flutter build windows --release
```

Android: install Flutter 3.47 or newer, JDK 17, Android SDK Platform 37, and NDK 28.2. Release signing requires your own release keystore configured in `android/key.properties`; use `android/key.properties.example` as the template.

```powershell
flutter pub get
flutter build apk --release --target-platform android-arm64
```

## Notes

- If an app with the same package name but a different signature is already installed, uninstall it before installing this build. Export your saved cards before uninstalling.
- The PIN is validated by the device firmware. Enable BLE pairing in the device settings and restart the device before connecting.
- Saved cards and settings remain in the application data directory, but builds with different signatures cannot be installed over each other.

## License

GPL-3.0. The upstream project is Chameleon Ultra GUI; the original LICENSE and copyright notices remain in the repository.
