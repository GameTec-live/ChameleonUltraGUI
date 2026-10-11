# Mobile (smartphone) UI

Android and iOS **phones** use a dedicated Material 3 interface in
`lib/gui/mobile/`. Desktop (Linux/Windows/macOS), Android tablets and iPads keep
the original interface.

## Platform selection

`lib/gui/mobile/platform_selector.dart` → `selectUiMode()`. Mobile UI only if the
platform is Android/iOS (not web) **and** the shortest side of the physical
*display* is below 600 logical px. The display, not the window, is measured, so
resizing a desktop window or rotating a phone never switches interface.
`main.dart` picks `MobileShell` (with `MobileScope.builder`) or the original
`LayoutBuilder` scaffold; theme and localization stay shared.

## Structure

- `mobile_shell.dart` — bottom navigation (Device / Read / Cards / More), tab
  state, back handling, DFU screen without navigation.
- `controllers/device_controller.dart` — loads battery, firmware, slots once per
  connection (pull to refresh to reload); activate/enable slots; upload cards.
- `controllers/connection_controller.dart` — scan/auto-connect, only while the
  connection page is visible and the app is in the foreground.
- `controllers/reader_controller.dart` — HF/LF scan, continuous scan, save.
- `pages/` — connection, device, slots, reader, library, writer, tools (More), DFU.

## Shared logic extracted from desktop pages

Desktop pages now call these (behaviour unchanged):
`helpers/slot_loader.dart` (load card into slot), `helpers/firmware_update.dart`
(check/flash firmware), `gui/menu/dialogs/card/import.dart` (card import),
`readLFCard()` in `helpers/general.dart`, `getToolItems()` in `page/tools.dart`.
`gui/menu/dialogs/settings_actions.dart` holds the settings dialogs shared by both settings pages. `SavedCardsPage` gained a `section`, `WriteCardPage` an `initialCard`/`cardPicker`, and `DebugPage` narrow-screen sizing; defaults keep desktop unchanged. `updateNavigationRailWidth`
tolerates a missing rail.

## Feature checklist (desktop → mobile)

| Desktop feature | Mobile entry |
| --- | --- |
| Connect (BLE/USB), DFU device dialog, pending BLE | Device tab (connection list / connecting / DFU) |
| Home: model, battery, slots, fw version, update check, reader/emulator mode, device settings | Device tab dashboard |
| Slot manager: load card, slot settings (edit, dump editor, export, clear, enable) | Slots (quick action) + slot sheet → existing slot settings dialog |
| Read card: HF/LF, continuous scan, override type, MIFARE Classic/Ultralight helpers, save | Read tab (reuses the same helper widgets) |
| Saved cards: view/edit/export/delete/move, import | Cards tab |
| Card folders (create/edit/move/export/import/delete) | Cards tab → folder button (full-screen `SavedCardsPage(section: cards)`) |
| Dictionaries and dictionary folders | More → Dictionaries (full-screen `SavedCardsPage(section: dictionaries)`) |
| Write card (magic cards) | Quick action, More, or card sheet → "Write to magic card" |
| Tools: dictionary download, T55xx cleaner, HF/LF sniffing | More |
| Firmware management / DFU / flash zip | More → Firmware management (existing dialog) |
| Settings | More → Settings (`MobileSettingsPage`, same preferences/dialogs, no sidebar option) |
| Debug (when enabled) | More → Debug (existing page, responsive on narrow screens) |

## Baseline before this work (desktop, Flutter 3.47.7)

- `flutter analyze`: 10 infos (pre-existing).
- `flutter test`: 15 passed, 5 failed (`test/recovery_test.dart`, pre-existing).

## Not verified

No Chameleon hardware, iOS, Linux, Windows or macOS builds were available.
Hardware-dependent flows (BLE/USB connection, scanning, slot upload, firmware
flashing) were only exercised against `EmulatorSerial`.
