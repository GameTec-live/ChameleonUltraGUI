import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

// Localizations
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

class QrCodeScanner extends StatefulWidget {
  const QrCodeScanner({super.key});

  @override
  State<StatefulWidget> createState() => QrCodeScannerState();
}

class QrCodeScannerState extends State<QrCodeScanner> {
  MobileScannerController cameraController = MobileScannerController();
  bool isFlashOn = false;
  bool successfulScan = false;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(AppLocalizations.of(context)!.qrCodeScanner),
      content: successfulScan
          ? SizedBox(
              width: MediaQuery.of(context).size.width >
                      MediaQuery.of(context).size.height
                  ? MediaQuery.of(context).size.height * 0.8
                  : MediaQuery.of(context).size.width * 0.8,
              height: MediaQuery.of(context).size.width >
                      MediaQuery.of(context).size.height
                  ? MediaQuery.of(context).size.height * 0.8
                  : MediaQuery.of(context).size.width * 0.8,
              child: const Icon(Icons.check))
          : SizedBox(
              width: MediaQuery.of(context).size.width >
                      MediaQuery.of(context).size.height
                  ? MediaQuery.of(context).size.height * 0.8
                  : MediaQuery.of(context).size.width * 0.8,
              height: MediaQuery.of(context).size.width >
                      MediaQuery.of(context).size.height
                  ? MediaQuery.of(context).size.height * 0.8
                  : MediaQuery.of(context).size.width * 0.8,
              child: MobileScanner(
                controller: cameraController,
                onDetect: (capture) async {
                  final List<Barcode> barcodes = capture.barcodes;
                  for (final Barcode barcode in barcodes) {
                    if (barcode.format == BarcodeFormat.qrCode &&
                        barcode.rawValue != null) {
                      setState(() {
                        successfulScan = true;
                      });
                      if (context.mounted) {
                        Navigator.pop(context, barcode.rawValue);
                      }
                      return;
                    }
                  }
                },
              ),
            ),
      actions: <Widget>[
        IconButton(
          icon: isFlashOn
              ? const Icon(Icons.flash_on)
              : const Icon(Icons.flash_off),
          onPressed: () {
            setState(() {
              isFlashOn = !isFlashOn;
              cameraController.toggleTorch();
            });
          },
        ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(AppLocalizations.of(context)!.cancel),
        ),
      ],
    );
  }
}
