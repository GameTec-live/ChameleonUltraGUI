import 'package:chameleonultragui/gui/page/read_card.dart';
import 'package:chameleonultragui/helpers/general.dart';
import 'package:chameleonultragui/helpers/write.dart';
import 'package:chameleonultragui/sharedprefsprovider.dart';
import 'package:flutter/material.dart';

// Localizations
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

class BaseT55XXCardHelper extends AbstractWriteHelper {
  LFCardInfo? lfInfo;

  @override
  bool get autoDetect => true;

  @override
  String get name => "T55XX";

  static String get staticName => "T55XX";
  TextEditingController keyController = TextEditingController();
  String key = "";

  BaseT55XXCardHelper(super.communicator);

  @override
  List<AbstractWriteHelper> getAvailableMethods() {
    return [
      BaseT55XXCardHelper(communicator),
    ];
  }

  @override
  List<AbstractWriteHelper> getAvailableMethodsByPriority() {
    return [BaseT55XXCardHelper(communicator)];
  }

  @override
  Widget getWriteWidget(BuildContext context, setState) {
    var localizations = AppLocalizations.of(context)!;
    final GlobalKey<FormState> formKey = GlobalKey<FormState>();

    return Row(children: [
      Form(
          key: formKey,
          autovalidateMode: AutovalidateMode.onUserInteraction,
          child: Expanded(
              child: TextFormField(
            controller: keyController,
            decoration: InputDecoration(
                labelText: localizations.key,
                hintText: localizations
                    .enter_something(localizations.t55xx_key_prompt)),
            validator: (String? value) {
              if (value!.isNotEmpty && !isValidHexString(value)) {
                return localizations.must_be_valid_hex;
              }

              if (value.length != 8) {
                return localizations.must_be(4, localizations.key);
              }

              return null;
            },
          ))),
      TextButton(
        onPressed: () => {
          if (keyController.text.isNotEmpty)
            {
              setState(() {
                key = keyController.text;
              })
            }
          else
            {
              setState(() {
                key = "20206666";
              })
            }
        },
        child: Text(localizations.next),
      )
    ]);
  }

  @override
  Future<bool> isCompatible(CardSave card) async {
    return true;
  }

  @override
  Future<bool> isMagic(data) async {
    return false;
  }

  @override
  bool isReady() {
    return key.length == 8;
  }

  @override
  bool writeWidgetSupported() {
    return true;
  }

  @override
  Future<void> reset() async {
    key = "";
  }

  @override
  Future<bool> writeData(CardSave card, update) async {
    await communicator
        .writeEM410XtoT55XX(hexToBytes(card.uid), hexToBytes(key), []);
    var newCard = await communicator.readEM410X();
    return newCard == card.uid;
  }
}
