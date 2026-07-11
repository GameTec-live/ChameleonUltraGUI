import 'package:chameleonultragui/gui/page/debug.dart';
import 'package:chameleonultragui/gui/page/read_card.dart';
import 'package:chameleonultragui/gui/page/saved_cards.dart';
import 'package:chameleonultragui/gui/page/settings.dart';
import 'package:chameleonultragui/gui/page/slot_manager.dart';
import 'package:chameleonultragui/gui/page/tools.dart';
import 'package:chameleonultragui/gui/page/write_card.dart';
import 'package:chameleonultragui/gui/menu/pages/logs_viewer.dart';
import 'package:chameleonultragui/gui/menu/pages/mfkey32.dart';
import 'package:chameleonultragui/main.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

enum AppRoute {
  home('/'),
  slots('/slots'),
  savedCards('/saved-cards'),
  readCard('/read-card'),
  writeCard('/write-card'),
  tools('/tools'),
  settings('/settings'),
  debug('/debug');

  const AppRoute(this.path);
  final String path;
}

final class AppRouter {
  AppRouter._();

  static const logsRouteName = 'logs';
  static const mfkey32RouteName = 'mfkey32';

  static GoRouter create(ChameleonGUIState appState) => GoRouter(
        initialLocation: AppRoute.home.path,
        refreshListenable: appState,
        redirect: (context, state) {
          final route = AppRoute.values.where((route) {
            if (route == AppRoute.home) return state.matchedLocation == '/';
            return state.matchedLocation == route.path ||
                state.matchedLocation.startsWith('${route.path}/');
          });
          if (route.isEmpty) return AppRoute.home.path;

          final destination = route.first;
          if (!appState.connector!.connected &&
              const {AppRoute.slots, AppRoute.readCard, AppRoute.writeCard}
                  .contains(destination)) {
            return AppRoute.home.path;
          }
          if (destination == AppRoute.debug && !appState.devMode) {
            return AppRoute.home.path;
          }
          return null;
        },
        routes: [
          StatefulShellRoute.indexedStack(
            builder: (context, state, navigationShell) =>
                AppNavigationShell(navigationShell: navigationShell),
            branches: [
              _branch(AppRoute.home, const HomeRouterPage()),
              _branch(AppRoute.slots, const SlotManagerPage()),
              _branch(AppRoute.savedCards, const SavedCardsPage()),
              _branch(AppRoute.readCard, const ReadCardPage()),
              _branch(AppRoute.writeCard, const WriteCardPage()),
              _branch(
                AppRoute.tools,
                const ToolsPage(),
                routes: [
                  GoRoute(
                    path: 'mfkey32',
                    name: mfkey32RouteName,
                    builder: (context, state) => const Mfkey32Menu(),
                  ),
                ],
              ),
              _branch(AppRoute.settings, const SettingsMainPage()),
              _branch(
                AppRoute.debug,
                const DebugPage(),
                routes: [
                  GoRoute(
                    path: 'logs',
                    name: logsRouteName,
                    builder: (context, state) => const LogsViewerPage(),
                  ),
                ],
              ),
            ],
          ),
        ],
      );

  static StatefulShellBranch _branch(
    AppRoute route,
    Widget page, {
    List<RouteBase> routes = const [],
  }) =>
      StatefulShellBranch(
        routes: [
          GoRoute(
            path: route.path,
            name: route.name,
            pageBuilder: (context, state) => NoTransitionPage(
              key: state.pageKey,
              child: page,
            ),
            routes: routes,
          ),
        ],
      );
}
