import 'package:chameleonultragui/bridge/chameleon.dart';
import 'package:chameleonultragui/gui/page/read_card.dart';
import 'package:chameleonultragui/helpers/general.dart';
import 'package:chameleonultragui/helpers/write.dart';
import 'package:chameleonultragui/sharedprefsprovider.dart';
import 'package:flutter/material.dart';

// Localizations
import 'package:chameleonultragui/generated/i18n/app_localizations.dart';
import 'package:flutter/services.dart';

class BaseT55XXCardHelper extends AbstractWriteHelper {
  LFCardInfo? lfInfo;

  @override
  bool get autoDetect => true;

  @override
  String get name => "t55xx";

  static String get staticName => "t55xx";
  TextEditingController newKeyController = TextEditingController();
  TextEditingController currentKeyController = TextEditingController();
  String currentKey = "";
  String newKey = "";

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
      Expanded(
          child: Form(
              key: formKey,
              autovalidateMode: AutovalidateMode.onUserInteraction,
              child: Column(
                children: [
                  TextFormField(
                    controller: currentKeyController,
                    decoration: InputDecoration(
                        labelText: localizations.key,
                        hintMaxLines: 4,
                        hintText: localizations
                            .enter_something(localizations.t55xx_key_prompt)),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(
                          RegExp(r'[0-9A-Fa-f: ]'))
                    ],
                    validator: (String? value) {
                      if (value!.isNotEmpty && !isValidHexString(value)) {
                        return localizations.must_be_valid_hex;
                      }

                      if (value.length != 8) {
                        return localizations.must_be(4, localizations.key);
                      }

                      return null;
                    },
                  ),
                  TextFormField(
                    controller: newKeyController,
                    decoration: InputDecoration(
                        labelText: localizations.new_key,
                        hintMaxLines: 4,
                        hintText: localizations.enter_something(
                            localizations.t55xx_new_key_prompt)),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(
                          RegExp(r'[0-9A-Fa-f: ]'))
                    ],
                    validator: (String? value) {
                      if (value!.isNotEmpty && !isValidHexString(value)) {
                        return localizations.must_be_valid_hex;
                      }

                      if (value.length != 8) {
                        return localizations.must_be(4, localizations.key);
                      }

                      return null;
                    },
                  )
                ],
              ))),
      TextButton(
        onPressed: () => {
          if (newKeyController.text.isNotEmpty)
            {
              if (currentKeyController.text.isNotEmpty)
                {
                  setState(() {
                    currentKey = currentKeyController.text;
                    newKey = newKeyController.text;
                  })
                }
              else
                {
                  setState(() {
                    currentKey = "20206666";
                    newKey = "20206666";
                  })
                }
            }
          else
            {
              if (currentKeyController.text.isNotEmpty)
                {
                  setState(() {
                    currentKey = currentKeyController.text;
                    newKey = currentKeyController.text;
                  })
                }
              else
                {
                  setState(() {
                    currentKey = "20206666";
                    newKey = "20206666";
                  })
                }
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
    return currentKey.length == 8 && newKey.length == 8;
  }

  @override
  bool writeWidgetSupported() {
    return true;
  }

  @override
  Future<void> reset() async {
    currentKey = "";
    newKey = "";
  }

  @override
  Future<bool> writeData(
      CardSave card, Function(int writeProgress) update) async {
    if (isEM410X(card.tag)) {
      await communicator.writeEM410XtoT55XX(
          hexToBytes(card.uid), hexToBytes(newKey), [hexToBytes(currentKey)]);
      var newCard = await communicator.readEM410X();
      return newCard.toString() == card.uid;
    } else if (card.tag == TagType.hidProx) {
      await communicator.writeHIDProxToT55XX(
          hexToBytes(card.uid), hexToBytes(newKey), [hexToBytes(currentKey)]);
      var newCard = await communicator.readHIDProx();
      return newCard.toString() == card.uid;
    } else if (card.tag == TagType.viking) {
      await communicator.writeVikingToT55XX(
          hexToBytes(card.uid), hexToBytes(newKey), [hexToBytes(currentKey)]);
      var newCard = await communicator.readViking();
      return newCard.toString() == card.uid;
    }

    return false;
  }
}
