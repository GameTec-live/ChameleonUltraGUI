import 'package:chameleonultragui/gui/mobile/controllers/device_controller.dart';
import 'package:chameleonultragui/gui/mobile/pages/connection_page.dart';
import 'package:chameleonultragui/gui/mobile/pages/device_page.dart';
import 'package:chameleonultragui/gui/mobile/pages/dfu_page.dart';
import 'package:chameleonultragui/gui/mobile/pages/library_page.dart';
import 'package:chameleonultragui/gui/mobile/pages/reader_page.dart';
import 'package:chameleonultragui/gui/mobile/pages/tools_page.dart';
import 'package:chameleonultragui/gui/mobile/widgets/message_view.dart';
import 'package:chameleonultragui/main.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

// Localizations
import 'package:chameleonultragui/generated/i18n/app_localizations.dart';

/// Provides the state shared by all mobile pages. It sits above the
/// navigator (via `MaterialApp.builder`) so pushed routes can reach it too.
class MobileScope extends StatelessWidget {
  const MobileScope({super.key, required this.child});

  final Widget child;

  static Widget builder(BuildContext context, Widget? child) =>
      MobileScope(child: child ?? const SizedBox.shrink());

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return ChangeNotifierProvider<MobileDeviceController>(
      create: (context) =>
          MobileDeviceController(context.read<ChameleonGUIState>()),
      // The existing dialogs are shared with desktop; give them more of the
      // narrow screen than the default 40 px side margins.
      child: Theme(
        data: theme.copyWith(
          dialogTheme: theme.dialogTheme.copyWith(
            insetPadding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 24,
            ),
          ),
        ),
        child: child,
      ),
    );
  }
}

enum MobileTab { device, read, cards, more }

typedef _ConnectionState = ({bool connected, bool pending, bool dfu});

/// Bottom-navigation shell for phones.
///
/// Device and Read adapt to the connection state: disconnected shows the
/// connection list, connecting a progress view, DFU a flashing screen without
/// navigation, and connected the dashboard.
class MobileShell extends StatefulWidget {
  const MobileShell({super.key});

  @override
  State<MobileShell> createState() => _MobileShellState();
}

class _MobileShellState extends State<MobileShell> {
  MobileTab _tab = MobileTab.device;
  final Set<MobileTab> _visited = {MobileTab.device};

  void _select(MobileTab tab) {
    if (tab == _tab) {
      return;
    }

    final previous = _tab;
    setState(() {
      _tab = tab;
      _visited.add(tab);
    });

    // Reading and writing cards switches the device to reader mode.
    if (tab == MobileTab.device &&
        (previous == MobileTab.read || previous == MobileTab.cards)) {
      context.read<MobileDeviceController>().refreshReaderMode();
    }
  }

  Widget _buildTab(MobileTab tab, _ConnectionState connection) {
    switch (tab) {
      case MobileTab.device:
        if (connection.connected) {
          return MobileDevicePage(
            key: const ValueKey('device'),
            onOpenReader: () => _select(MobileTab.read),
          );
        }
        if (connection.pending) {
          return const MobileConnectingView(key: ValueKey('connecting'));
        }
        return const MobileConnectionPage(key: ValueKey('connection'));
      case MobileTab.read:
        if (connection.connected) {
          return const MobileReaderPage(key: ValueKey('reader'));
        }
        return _DeviceRequiredPage(
          key: const ValueKey('read-disconnected'),
          title: AppLocalizations.of(context)!.read_card,
          onGoToDevice: () => _select(MobileTab.device),
        );
      case MobileTab.cards:
        return const MobileLibraryPage();
      case MobileTab.more:
        return const MobileToolsPage();
    }
  }

  @override
  Widget build(BuildContext context) {
    // The connector is briefly null while it is swapped (emulated device
    // toggle), and selectors run before the app rebuilds it.
    final connection = context.select<ChameleonGUIState, _ConnectionState>(
      (state) => (
        connected: state.connector?.connected ?? false,
        pending: state.connector?.pendingConnection ?? false,
        dfu:
            (state.connector?.connected ?? false) &&
            (state.connector?.isDFU ?? false),
      ),
    );

    if (connection.dfu) {
      return const PopScope(canPop: false, child: MobileDfuPage());
    }

    final localizations = AppLocalizations.of(context)!;

    return PopScope(
      canPop: _tab == MobileTab.device,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) {
          _select(MobileTab.device);
        }
      },
      child: Scaffold(
        body: IndexedStack(
          index: _tab.index,
          children: [
            for (final tab in MobileTab.values)
              if (_visited.contains(tab))
                TickerMode(
                  enabled: tab == _tab,
                  child: _buildTab(tab, connection),
                )
              else
                const SizedBox.shrink(),
          ],
        ),
        bottomNavigationBar: NavigationBar(
          selectedIndex: _tab.index,
          onDestinationSelected: (index) => _select(MobileTab.values[index]),
          destinations: [
            NavigationDestination(
              icon: const Icon(Icons.nfc),
              label: localizations.mobile_nav_device,
            ),
            NavigationDestination(
              icon: const Icon(Icons.sensors),
              label: localizations.read,
            ),
            NavigationDestination(
              icon: const Icon(Icons.auto_awesome_motion),
              label: localizations.cards,
            ),
            NavigationDestination(
              icon: const Icon(Icons.more_horiz),
              label: localizations.mobile_nav_more,
            ),
          ],
        ),
      ),
    );
  }
}

class _DeviceRequiredPage extends StatelessWidget {
  const _DeviceRequiredPage({
    super.key,
    required this.title,
    required this.onGoToDevice,
  });

  final String title;
  final VoidCallback onGoToDevice;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context)!;

    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: MessageView(
        icon: Icons.usb_off,
        title: localizations.connect_device_to_use,
        actions: [
          FilledButton(
            onPressed: onGoToDevice,
            child: Text(localizations.go_to_device),
          ),
        ],
      ),
    );
  }
}
