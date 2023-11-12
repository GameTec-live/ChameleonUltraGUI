import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:chameleonultragui/gui/component/qrcode_scanner.dart';
import 'package:crypto/crypto.dart';

// Localizations
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

class QrCodeImport extends StatefulWidget {
  const QrCodeImport({Key? key}) : super(key: key);

  @override
  State<StatefulWidget> createState() => QrCodeImportState();
}

class QrCodeImportState extends State<QrCodeImport> {
  String? shasum;
  int? qrCodeChuncks;
  String resultingJson = "";
  int currentChunk = 0;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text("QR Code Import"),
      actions: [
        TextButton(
          onPressed: () {
            Navigator.of(context).pop();
          },
          child: Text(AppLocalizations.of(context)!.cancel),
        ),
        TextButton(
          onPressed: () async {
            if (qrCodeChuncks == currentChunk) {
              Navigator.pop(context, resultingJson);
              return;
            }

            String qrCodeData = await showDialog(
                context: context,
                builder: (BuildContext context) {
                  return const QrCodeScanner();
                });
            if (qrCodeData
                .contains("\"Info\":\"Chameleon Ultra GUI Settings\"")) {
              Map<String, dynamic>? data = jsonDecode(qrCodeData);
              if (data == null) {
                return;
              }
              setState(() {
                shasum = data["sha256"];
                qrCodeChuncks = data["chunks"];
              });
              currentChunk = 0;
              resultingJson = "";
            } else {
              resultingJson += qrCodeData;
              setState(() {
                currentChunk++;
              });
            }
          },
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              qrCodeChuncks == null
                  ? Text("Start Scanning")
                  : qrCodeChuncks == currentChunk
                      ? Text("Finish Import")
                      : Text(
                          "Scan next QR Code (${currentChunk + 1}/${qrCodeChuncks! + 1})"),
              const SizedBox(width: 5),
              if (sha256
                      .convert(const Utf8Encoder().convert(resultingJson))
                      .toString() ==
                  shasum)
                Tooltip(
                  message: "Checksum OK",
                  child: Icon(Icons.check),
                ),
            ],
          ),
        ),
      ],
    );
  }
}
