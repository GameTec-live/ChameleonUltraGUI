import 'package:chameleonultragui/generated/i18n/app_localizations.dart';
import 'package:flutter/material.dart';

class ErrorPage extends StatelessWidget {
  final String errorMessage;

  const ErrorPage({
    super.key,
    required this.errorMessage,
  });

  @override
  Widget build(BuildContext context) {
    var localizations = AppLocalizations.of(context)!;

    return Center(
      child: Padding(
        padding: EdgeInsets.all(24.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.error_outline,
              size: 80,
              color: Theme.of(context).colorScheme.error,
            ),
            SizedBox(height: 16),
            Text(
              '${localizations.error}:',
              textAlign: TextAlign.center,
            ),
            SizedBox(height: 8),
            Text(
              errorMessage,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
