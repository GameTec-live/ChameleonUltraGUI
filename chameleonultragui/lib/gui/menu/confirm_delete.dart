import 'package:flutter/material.dart';

// Localizations
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

class ConfirmDeletionMenu extends StatefulWidget {
  final String thingBeingDeleted;

  const ConfirmDeletionMenu({super.key, required this.thingBeingDeleted});

  @override
  ConfirmDeletionMenuState createState() => ConfirmDeletionMenuState();
}

class ConfirmDeletionMenuState extends State<ConfirmDeletionMenu> {
  @override
  Widget build(BuildContext context) {
    var localizations = AppLocalizations.of(context)!;

    return AlertDialog(
      title: Text(localizations.confirm_deletion),
      content: SingleChildScrollView(
          child: Column(
        mainAxisAlignment: MainAxisAlignment.start,
        children: [
          Text(localizations.confirm_deletion_text("\"${widget.thingBeingDeleted}\"")),
        ],
      )),
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
          child: Text(localizations.delete),
        ),
      ],
    );
  }
}