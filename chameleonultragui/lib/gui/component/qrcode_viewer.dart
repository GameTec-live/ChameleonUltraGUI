import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

// Localizations
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

List<String> splitStringIntoQrChunks(String str, int chunkSize) {
  List<String> chunks = [];
  for (int i = 0; i < str.length; i += chunkSize) {
    int endIndex = i + chunkSize < str.length ? i + chunkSize : str.length;
    chunks.add(str.substring(i, endIndex));
  }
  return chunks;
}

class QrCodeViewer extends StatefulWidget {
  final List<String> qrChunks;
  final int errorCorrection;

  const QrCodeViewer(
      {required this.qrChunks, this.errorCorrection = 0, super.key});

  @override
  QrCodeViewerState createState() => QrCodeViewerState();
}

class QrCodeViewerState extends State<QrCodeViewer> {
  int currentQrIndex = 0;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(AppLocalizations.of(context)!.qrCodeViewer),
      content: SizedBox(
        width: MediaQuery.of(context).size.width >
                MediaQuery.of(context).size.height
            ? MediaQuery.of(context).size.height * 0.8
            : MediaQuery.of(context).size.width * 0.8,
        height: MediaQuery.of(context).size.width >
                MediaQuery.of(context).size.height
            ? MediaQuery.of(context).size.height * 0.8
            : MediaQuery.of(context).size.width * 0.8,
        child: QrImageView(
          data: widget.qrChunks[currentQrIndex],
          version: QrVersions.auto,
          size: 200.0,
          backgroundColor: Colors.white,
          padding: const EdgeInsets.all(20.0),
          errorCorrectionLevel: widget.errorCorrection,
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: currentQrIndex < widget.qrChunks.length - 1
              ? Text(AppLocalizations.of(context)!.cancel)
              : Text(AppLocalizations.of(context)!.done),
        ),
        if (currentQrIndex < widget.qrChunks.length - 1)
          TextButton(
            onPressed: () {
              setState(() {
                currentQrIndex++;
              });
            },
            child: Text(AppLocalizations.of(context)!.next_qr_code(
                "${currentQrIndex + 1}",
                "${widget.qrChunks.length}")), //"Next QR Code (${currentQrIndex + 1}/${widget.qrChunks.length})"
          ),
      ],
    );
  }
}
