import 'package:chameleonultragui/connector/serial_abstract.dart';
import 'package:chameleonultragui/generated/i18n/app_localizations.dart';
import 'package:chameleonultragui/gui/menu/dialogs/firmware_picker.dart';
import 'package:chameleonultragui/helpers/github.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const v230 = "4e1a5b267b9ed33559e0e2c9dad61d61eaf64ba1";
const dev = "23507c2887472ef86c0727a85e2e445f2be83e75";

Map<String, dynamic> release(String tag, String uploaded,
    {bool prerelease = false,
    String commitish = v230,
    List<String> assets = const ["lite-dfu-app.zip", "ultra-dfu-app.zip"]}) {
  return {
    "tag_name": tag,
    "prerelease": prerelease,
    "target_commitish": commitish,
    "published_at": "2023-08-19T00:14:20Z",
    "assets": [
      for (var name in assets)
        {
          "name": name,
          "updated_at": uploaded,
          "browser_download_url": "https://example.com/$tag/$name",
        },
    ],
  };
}

Map<String, dynamic> artifact(int id, int runId, String sha,
    {String branch = "main", String created = "2026-10-24T10:06:21Z"}) {
  return {
    "id": id,
    "name": "ultra-dfu-app",
    "expired": false,
    "created_at": created,
    "workflow_run": {
      "id": runId,
      "head_branch": branch,
      "head_repository_id": 581338100,
      "head_sha": sha,
    },
  };
}

FirmwareBuild firmwareBuild(String name, FirmwareChannel channel,
    {String? commit}) {
  return FirmwareBuild(
      name: name,
      channel: channel,
      date: DateTime.utc(2026, 10, 24),
      url: Uri.parse("https://example.com/$name"),
      commit: commit);
}

void main() {
  group('firmwareBuildsFromReleases', () {
    final releases = [
      release("v2.3.0", "2026-10-24T09:49:02Z"),
      release("dev", "2026-10-24T10:07:26Z", prerelease: true, commitish: dev),
      release("v1.0", "2023-06-21T11:51:51Z", commitish: "main", assets: []),
    ];

    test('lists releases and pre-releases that have firmware for the device',
        () {
      final builds =
          firmwareBuildsFromReleases(releases, ChameleonDevice.ultra);

      expect(builds.map((build) => build.name), ["v2.3.0", "dev"]);
      expect(builds.map((build) => build.channel),
          [FirmwareChannel.release, FirmwareChannel.prerelease]);
      expect(builds[0].url.toString(),
          "https://example.com/v2.3.0/ultra-dfu-app.zip");
      expect(
          firmwareBuildsFromReleases(releases, ChameleonDevice.lite)[0]
              .url
              .toString(),
          "https://example.com/v2.3.0/lite-dfu-app.zip");
    });

    test('dates builds by firmware upload, not release publication', () {
      final builds =
          firmwareBuildsFromReleases(releases, ChameleonDevice.ultra);

      expect(builds[1].date, DateTime.utc(2026, 10, 24, 10, 7, 26));
    });

    test('keeps the commit only when it is a full hash', () {
      final builds = firmwareBuildsFromReleases([
        release("v2.3.0", "2026-10-24T09:49:02Z"),
        release("v1.0", "2023-06-21T11:51:51Z", commitish: "main"),
      ], ChameleonDevice.ultra);

      expect(builds.map((build) => build.commit), [v230, null]);
    });
  });

  test('firmwareBuildsFromArtifacts lists main builds newest first, once each',
      () {
    final builds = firmwareBuildsFromArtifacts([
      artifact(5, 40082843368, "4ffb657475000000000000000000000000000000"),
      artifact(4, 40083994172, "6b8abbc63d000000000000000000000000000000",
          branch: "gtl-ruff"),
      artifact(3, 40084496773, dev),
      artifact(2, 40083294055, v230),
      // A second artifact for the same commit, e.g. from a re-run
      artifact(1, 40083294055, v230),
    ], ChameleonDevice.ultra);

    expect(builds.map((build) => build.name),
        ["23507c2", "4e1a5b2", "4ffb657"]);
    expect(builds.every((build) => build.channel == FirmwareChannel.dev),
        isTrue);
    expect(builds[0].commit, dev);
    expect(builds[0].url.toString(),
        "https://nightly.link/RfidResearchGroup/ChameleonUltra/suites/40084496773/artifacts/3");
  });

  group('FirmwareBuild.isInstalled', () {
    test('matches a release by its tag', () {
      final stable =
          firmwareBuild("v2.3.0", FirmwareChannel.release, commit: v230);

      expect(stable.isInstalled("v2.3.0"), isTrue);
      expect(stable.isInstalled("v2.2.0"), isFalse);
    });

    test('matches a dev build by the commit in the git version', () {
      final head =
          firmwareBuild("23507c2", FirmwareChannel.dev, commit: dev);

      expect(head.isInstalled("v2.3.0-2-g23507c2"), isTrue);
      expect(head.isInstalled("v2.3.0-2-g23507c2-dirty"), isTrue);
      expect(head.isInstalled("v2.2.0-89-g4ffb657"), isFalse);
      expect(head.isInstalled(""), isFalse);
    });

    test('never matches a build without a commit by commit', () {
      expect(
          firmwareBuild("v1.0", FirmwareChannel.release)
              .isInstalled("v2.3.0-2-g23507c2"),
          isFalse);
    });
  });

  group('FirmwarePicker', () {
    final l10n = lookupAppLocalizations(const Locale('en'));
    final builds = [
      firmwareBuild("v2.3.0", FirmwareChannel.release, commit: v230),
      firmwareBuild("v2.2.0", FirmwareChannel.release),
      firmwareBuild("23507c2", FirmwareChannel.dev, commit: dev),
    ];

    Future<void> openPicker(WidgetTester tester,
        Future<List<FirmwareBuild>> Function() builds,
        {void Function(FirmwareBuild?)? onPicked}) async {
      await tester.pumpWidget(MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                final picked = await showDialog<FirmwareBuild>(
                    context: context,
                    builder: (_) => FirmwarePicker(
                        builds: builds(),
                        installedVersion: "v2.3.0-2-g23507c2"));
                onPicked?.call(picked);
              },
              child: const Text("open"),
            ),
          ),
        ),
      ));

      await tester.tap(find.text("open"));
      await tester.pumpAndSettle();
    }

    testWidgets('groups builds by channel and marks the installed one',
        (tester) async {
      await openPicker(tester, () => Future.value(builds));

      expect(find.text(l10n.firmware_releases), findsOneWidget);
      expect(find.text(l10n.firmware_prereleases), findsNothing);
      expect(find.text(l10n.firmware_dev_builds), findsOneWidget);
      expect(
          find.descendant(
              of: find.widgetWithText(ListTile, "23507c2"),
              matching: find.text(l10n.installed)),
          findsOneWidget);
      expect(find.text(l10n.installed), findsOneWidget);
    });

    testWidgets('returns a build only after the user confirms it',
        (tester) async {
      var closed = false;
      FirmwareBuild? picked;
      await openPicker(tester, () => Future.value(builds), onPicked: (build) {
        closed = true;
        picked = build;
      });

      await tester.tap(find.text("v2.2.0"));
      await tester.pumpAndSettle();
      expect(find.text(l10n.older_firmware_warning), findsOneWidget);

      await tester.tap(find.text(l10n.cancel).last);
      await tester.pumpAndSettle();
      expect(closed, isFalse);

      await tester.tap(find.text("v2.2.0"));
      await tester.pumpAndSettle();
      await tester.tap(find.text(l10n.flash));
      await tester.pumpAndSettle();

      expect(closed, isTrue);
      expect(picked?.name, "v2.2.0");
      expect(find.byType(FirmwarePicker), findsNothing);
    });

    testWidgets('shows the error when the builds cannot be fetched',
        (tester) async {
      await openPicker(
          tester, () => Future.error("API rate limit exceeded"));

      expect(find.textContaining("API rate limit exceeded"), findsOneWidget);
    });
  });
}
