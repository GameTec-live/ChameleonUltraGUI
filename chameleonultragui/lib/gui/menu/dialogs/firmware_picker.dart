import 'package:chameleonultragui/helpers/github.dart';
import 'package:flutter/material.dart';

// Localizations
import 'package:chameleonultragui/generated/i18n/app_localizations.dart';

/// Lists the firmware builds available for the connected device and pops the
/// one the user confirmed, or null if they cancelled.
class FirmwarePicker extends StatelessWidget {
  final Future<List<FirmwareBuild>> builds;
  final String installedVersion;

  const FirmwarePicker(
      {super.key, required this.builds, required this.installedVersion});

  @override
  Widget build(BuildContext context) {
    var localizations = AppLocalizations.of(context)!;

    return FutureBuilder(
        future: builds,
        builder: (BuildContext context,
            AsyncSnapshot<List<FirmwareBuild>> snapshot) {
          Widget content;
          if (snapshot.connectionState == ConnectionState.waiting) {
            content = const Column(
                mainAxisSize: MainAxisSize.min,
                children: [CircularProgressIndicator()]);
          } else if (snapshot.hasError) {
            content = Text(
                '${localizations.update_error}: ${snapshot.error.toString()}');
          } else if (snapshot.data!.isEmpty) {
            content = Text(localizations.no_firmware_available);
          } else {
            content = SizedBox(
                width: double.maxFinite,
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    for (var channel in FirmwareChannel.values)
                      ...buildChannel(context, channel, snapshot.data!),
                  ],
                ));
          }

          return AlertDialog(
            title: Text(localizations.firmware_version),
            content: content,
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.of(context).pop();
                },
                child: Text(localizations.cancel),
              ),
            ],
          );
        });
  }

  List<Widget> buildChannel(BuildContext context, FirmwareChannel channel,
      List<FirmwareBuild> builds) {
    var localizations = AppLocalizations.of(context)!;
    var materialLocalizations = MaterialLocalizations.of(context);
    final channelBuilds =
        builds.where((firmware) => firmware.channel == channel).toList();
    if (channelBuilds.isEmpty) {
      return [];
    }

    return [
      ListTile(
        title: Text(
          switch (channel) {
            FirmwareChannel.release => localizations.firmware_releases,
            FirmwareChannel.prerelease => localizations.firmware_prereleases,
            FirmwareChannel.dev => localizations.firmware_dev_builds,
          },
          style: Theme.of(context).textTheme.titleSmall,
        ),
      ),
      for (var firmware in channelBuilds)
        ListTile(
          title: Text(firmware.name),
          subtitle: Text([
            materialLocalizations.formatShortDate(firmware.date.toLocal()),
            materialLocalizations.formatTimeOfDay(
                TimeOfDay.fromDateTime(firmware.date.toLocal())),
            if (firmware.channel != FirmwareChannel.dev &&
                firmware.commit != null)
              firmware.commit!.substring(0, 7),
          ].join(' · ')),
          trailing: firmware.isInstalled(installedVersion)
              ? Chip(label: Text(localizations.installed))
              : null,
          onTap: () async {
            final confirmed = await confirmFlash(context, firmware);
            if (!confirmed || !context.mounted) {
              return;
            }

            Navigator.of(context).pop(firmware);
          },
        ),
    ];
  }

  Future<bool> confirmFlash(
      BuildContext context, FirmwareBuild firmware) async {
    var localizations = AppLocalizations.of(context)!;

    return await showDialog<bool>(
          context: context,
          builder: (BuildContext context) => AlertDialog(
            title: Text(firmware.name),
            content: Text(localizations.older_firmware_warning),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.of(context).pop(false);
                },
                child: Text(localizations.cancel),
              ),
              TextButton(
                onPressed: () {
                  Navigator.of(context).pop(true);
                },
                child: Text(localizations.flash),
              ),
            ],
          ),
        ) ??
        false;
  }
}
