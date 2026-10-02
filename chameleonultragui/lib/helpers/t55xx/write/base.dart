import 'package:chameleonultragui/gui/page/read_card.dart';
import 'package:chameleonultragui/helpers/definitions.dart';
import 'package:chameleonultragui/helpers/general.dart';
import 'package:chameleonultragui/helpers/t55xx/keys.dart';
import 'package:chameleonultragui/helpers/validators.dart';
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

  /// Whether the firmware leaves tags without a password unless asked; null until known.
  bool? passwordOptIn;
  bool _loadingPasswordOptIn = false;
  bool _passwordOptInFailed = false;
  bool setPassword = false;
  bool confirmed = false;

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
    if (passwordOptIn == null) {
      // A failed check must not fall back to the old form: on new firmware that would send
      // no flags byte, and a password the user typed would silently not be set.
      if (_passwordOptInFailed) {
        var localizations = AppLocalizations.of(context)!;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(localizations.t55xx_feature_check_failed),
            Wrap(
              alignment: WrapAlignment.end,
              children: [
                TextButton(
                  onPressed: () => setState(() => _passwordOptInFailed = false),
                  child: Text(localizations.retry),
                ),
              ],
            ),
          ],
        );
      }
      if (!_loadingPasswordOptIn) {
        _loadingPasswordOptIn = true;
        communicator.isT55xxPasswordOptIn().then((value) {
          passwordOptIn = value;
          if (context.mounted) setState(() {});
        }, onError: (_) {
          _passwordOptInFailed = true;
          _loadingPasswordOptIn = false;
          if (context.mounted) setState(() {});
        });
      }
      return const Center(child: CircularProgressIndicator());
    }
    return passwordOptIn!
        ? _optInWriteWidget(context, setState)
        : _legacyWriteWidget(context, setState);
  }

  /// Firmware that understands the flags byte: no password unless the user asks for one.
  Widget _optInWriteWidget(BuildContext context, setState) {
    var localizations = AppLocalizations.of(context)!;
    final GlobalKey<FormState> formKey = GlobalKey<FormState>();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Form(
          key: formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextFormField(
                controller: currentKeyController,
                autovalidateMode: AutovalidateMode.onUserInteraction,
                decoration: InputDecoration(
                  labelText: localizations.t55xx_current_password,
                  hintMaxLines: 4,
                  hintText: localizations.enter_something(
                    localizations.t55xx_current_password_prompt,
                  ),
                ),
                inputFormatters: hexFormatter,
                validator: (value) => validateHex(
                  value,
                  localizations,
                  exactBytes: 4,
                  fieldName: localizations.t55xx_current_password,
                ),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(localizations.t55xx_set_password),
                value: setPassword,
                onChanged: (value) => setState(() => setPassword = value),
              ),
              if (setPassword)
                TextFormField(
                  controller: newKeyController,
                  autovalidateMode: AutovalidateMode.onUserInteraction,
                  decoration: InputDecoration(
                    labelText: localizations.t55xx_password,
                    hintMaxLines: 4,
                    hintText: localizations.enter_something(
                      localizations.t55xx_password_prompt,
                    ),
                  ),
                  inputFormatters: hexFormatter,
                  validator: (value) => validateHex(
                    value,
                    localizations,
                    exactBytes: 4,
                    fieldName: localizations.t55xx_password,
                    required: true,
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          alignment: WrapAlignment.end,
          children: [
            TextButton(
              onPressed: () {
                // Shows the field errors when Next is pressed without a valid password
                if (!formKey.currentState!.validate()) return;
                var current = currentKeyController.text.replaceAll(" ", "");
                var password = newKeyController.text.replaceAll(" ", "");
                if ((current.isNotEmpty && current.length != 8) ||
                    (setPassword && password.length != 8)) {
                  return;
                }
                setState(() {
                  currentKey = current;
                  // Block 7 is written either way; blank unless it holds a password.
                  newKey = setPassword ? password : t55xxNoPasswordKey;
                  confirmed = true;
                });
              },
              child: Text(localizations.next),
            ),
          ],
        ),
      ],
    );
  }

  /// Firmware without the flags byte: every write enables password mode, as before.
  Widget _legacyWriteWidget(BuildContext context, setState) {
    var localizations = AppLocalizations.of(context)!;
    final GlobalKey<FormState> formKey = GlobalKey<FormState>();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(localizations.t55xx_password_always_set_warning),
        Form(
          key: formKey,
          autovalidateMode: AutovalidateMode.onUserInteraction,
          child: Column(
            children: [
              TextFormField(
                controller: currentKeyController,
                decoration: InputDecoration(
                  labelText: localizations.key,
                  hintMaxLines: 4,
                  hintText: localizations.enter_something(
                    localizations.t55xx_key_prompt,
                  ),
                ),
                inputFormatters: hexFormatter,
                validator: (value) => validateHex(
                  value,
                  localizations,
                  exactBytes: 4,
                  fieldName: localizations.key,
                ),
              ),
              TextFormField(
                controller: newKeyController,
                decoration: InputDecoration(
                  labelText: localizations.new_key,
                  hintMaxLines: 4,
                  hintText: localizations.enter_something(
                    localizations.t55xx_new_key_prompt,
                  ),
                ),
                inputFormatters: hexFormatter,
                validator: (value) => validateHex(
                  value,
                  localizations,
                  exactBytes: 4,
                  fieldName: localizations.key,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          alignment: WrapAlignment.end,
          children: [
            TextButton(
              onPressed: () {
                // Keys must be valid hex before they go into the request
                if (!formKey.currentState!.validate()) return;
                var current = currentKeyController.text.replaceAll(" ", "");
                var typed = newKeyController.text.replaceAll(" ", "");
                setState(() {
                  // Without a key, try the default; without a new key, keep the current one
                  currentKey = current.isNotEmpty ? current : "20206666";
                  newKey = typed.isNotEmpty ? typed : currentKey;
                  confirmed = true;
                });
              },
              child: Text(localizations.next),
            ),
          ],
        ),
      ],
    );
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
    return confirmed &&
        newKey.length == 8 &&
        (currentKey.isEmpty || currentKey.length == 8);
  }

  @override
  bool writeWidgetSupported() {
    return true;
  }

  @override
  Future<void> reset() async {
    currentKey = "";
    newKey = "";
    confirmed = false;
  }

  @override
  void clearInputs() {
    currentKeyController.clear();
    newKeyController.clear();
    setPassword = false;
  }

  List<Uint8List> get _oldKeys =>
      t55xxOldKeys(currentKey, passwordOptIn: passwordOptIn == true);

  /// Null on older firmware, which takes no flags byte.
  bool? get _setPasswordFlag => passwordOptIn == true ? setPassword : null;

  @override
  Future<bool> writeData(
      CardSave card, Function(int writeProgress) update) async {
    if (isEM410X(card.tag)) {
      await communicator.writeEM410XtoT55XX(hexToBytes(card.uid),
          hexToBytes(newKey), _oldKeys,
          setPassword: _setPasswordFlag);
      await Future.delayed(const Duration(milliseconds: 500));
      var newCard = await communicator.readEM410X();
      return newCard.toString() == card.uid;
    } else if (card.tag == TagType.hidProx) {
      await communicator.writeHIDProxToT55XX(hexToBytes(card.uid),
          hexToBytes(newKey), _oldKeys,
          setPassword: _setPasswordFlag);
      await Future.delayed(const Duration(milliseconds: 500));
      var newCard = await communicator.readHIDProx();
      return newCard.toString() == card.uid;
    } else if (card.tag == TagType.viking) {
      await communicator.writeVikingToT55XX(hexToBytes(card.uid),
          hexToBytes(newKey), _oldKeys,
          setPassword: _setPasswordFlag);
      await Future.delayed(const Duration(milliseconds: 500));
      var newCard = await communicator.readViking();
      return newCard.toString() == card.uid;
    } else if (card.tag == TagType.pac) {
      await communicator.writePacToT55XX(hexToBytes(card.uid),
          hexToBytes(newKey), _oldKeys,
          setPassword: _setPasswordFlag);
      var newCard = await communicator.readPac();
      return newCard.toString() == card.uid;
    } else if (card.tag == TagType.ioProx) {
      await communicator.writeIoProxToT55XX(hexToBytes(card.uid),
          hexToBytes(newKey), _oldKeys,
          setPassword: _setPasswordFlag);
      await Future.delayed(const Duration(milliseconds: 500));
      var newCard = await communicator.readIoProx();
      return newCard.toString() == card.uid;
    } else if (card.tag == TagType.idteck) {
      await communicator.writeIdteckToT55XX(hexToBytes(card.uid),
          hexToBytes(newKey), _oldKeys,
          setPassword: _setPasswordFlag);
      // IDTECK read is not implemented in the firmware (PSK demodulation
      // on the envelope-only tag-emulation ADC path is a follow-up), so we
      // cannot read back the tag for verification. Assume the T55xx write
      // succeeded if the firmware did not raise an error.
      return true;
    }

    return false;
  }
}
