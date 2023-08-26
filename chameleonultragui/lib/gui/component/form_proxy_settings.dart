
import 'package:chameleonultragui/helpers/general.dart';
import 'package:chameleonultragui/helpers/http.dart';
import 'package:flutter/material.dart';

class FormConfirmProxySettingResult {
  final String proxyUrl;

  FormConfirmProxySettingResult(this.proxyUrl);
}

class FormConfirmProxySetting extends StatefulWidget {
  final String proxyUrl;
  
  const FormConfirmProxySetting({
    super.key,
    required this.proxyUrl,
  });

  @override
  State<FormConfirmProxySetting> createState() => FormConfirmProxySettingState();
}

class FormConfirmProxySettingState extends State<FormConfirmProxySetting> {
  String proxyUrl = '';

  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();

  @override
  Widget build(BuildContext context) {
    proxyUrl = widget.proxyUrl;

    TextEditingController textController = TextEditingController(
      text: proxyUrl
    );

    return Form(
      key: _formKey,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'To download firmware assets on web this application needs to use a proxy to circumvent CORS restrictions. '
            'This project provides a default CORS proxy but you can customize it if you wish. This modal will only be shown once on updating the firmware, go to Settings to change it afterwards.'
          ),
          TextFormField(
            autocorrect: false,
            controller: textController,
            validator: (value) {
              if (value!.isEmpty) {
                return 'An empty value will use the default proxy';
              }

              if (!isUrl(value, more: (uri) => value.contains('{url}') || uri.path.endsWith('/'))) {
                return 'Enter a valid url (path segments needs to have a trailing slash if no {url} is present)';
              }

              return null;
            },
            onSaved: (value) {
              if (value == null) {
                return;
              } else if (value == '') {
                proxyUrl = widget.proxyUrl;
              } else {
                proxyUrl = value;
              }
            },
            decoration: const InputDecoration( 
              labelText: 'Proxy url',
              hintText: defaultProxyUrl,
            )
          ),
          const SizedBox(height: 12),
          const Text(
            'Use {url} as a replace needle for the url. Example: https://proxy.net/?url={url}&redirect=true Without the url will be appended',
            style: TextStyle(fontSize: 12)
          ),
        ],
      )
    );
  }

  FormConfirmProxySettingResult? toMapIfValid() {
    final formState = _formKey.currentState!;
    if (!formState.validate()) {
      return null;
    }

    formState.save();

    return FormConfirmProxySettingResult(proxyUrl);
  }
}