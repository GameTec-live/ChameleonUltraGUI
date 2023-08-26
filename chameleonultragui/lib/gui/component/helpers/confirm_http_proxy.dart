
import 'dart:math';

import 'package:chameleonultragui/gui/component/dialog_confirm.dart';
import 'package:chameleonultragui/gui/component/form_proxy_settings.dart';
import 'package:chameleonultragui/helpers/http.dart';
import 'package:chameleonultragui/sharedprefsprovider.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:sizer_pro/sizer.dart';

Future<bool?> confirmHttpProxy(
  BuildContext context,
  SharedPreferencesProvider sharedPreferences,
  { bool onlyWhenNotSet = true }
) async {
  if (!kIsWeb) {
    // We dont need to use a CORS proxy on devices other then web
    return null;
  }

  final GlobalKey<FormConfirmProxySettingState> key = GlobalKey<FormConfirmProxySettingState>();
  final httpCorsProxy = sharedPreferences.httpCorsProxy;

  if (onlyWhenNotSet && httpCorsProxy != null) {
    return null;
  }

  return showDialog<bool>(
    context: context,
    barrierDismissible: !onlyWhenNotSet,
    builder: (BuildContext _) => DialogConfirm(
      title: 'Confirm CORS proxy',
      cancelTitle: 'Cancel',
      content: SizedBox(
        width: min(500, SizerUtil.width),
        child: FormConfirmProxySetting(
          key: key,
          proxyUrl: httpCorsProxy ?? defaultProxyUrl,
        ),
      ),
      okTitle: 'Set proxy',
      onOk: () {
        var state = key.currentState!.toMapIfValid();
        if (state == null) {
          throw ('Form validation error');
        }

        sharedPreferences.httpCorsProxy = state.proxyUrl;
      }
    )
  );
}
