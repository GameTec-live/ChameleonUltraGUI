import 'package:flutter/material.dart';

class DialogConfirm extends StatefulWidget {
  final String title;
  final Widget? content;
  final String? cancelTitle;
  final String? okTitle;
  final Function? onCancel;
  final Function? onOk;

  const DialogConfirm({
    super.key,
    this.title = 'Are you sure?',
    this.content,
    this.cancelTitle = 'Cancel',
    this.okTitle = 'Ok',
    this.onCancel,
    this.onOk,
  });

  @override
  State<DialogConfirm> createState() => DialogConfirmState();
}

class DialogConfirmState extends State<DialogConfirm> {
  bool isBusy = false;
  Exception? error;

  @override
  Widget build(BuildContext context) {
    final navigator = Navigator.of(context);

    return AlertDialog(
      title: Text(widget.title),
      contentPadding: EdgeInsets.fromLTRB(24, 20, 24, error == null ? 20 : 4),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (widget.content != null)
            widget.content!,
          if (error != null)
            Text(error.toString(), style: TextStyle(fontSize: 14, color: Theme.of(context).colorScheme.error))
        ]
      ),
      actions: [
        if (widget.cancelTitle != null)
          ElevatedButton(
              onPressed: isBusy ? null : () async {
                if (isBusy) {
                  return;
                }

                error = null;

                setState(() { isBusy = false; });

                if (widget.onCancel != null) {
                  await widget.onCancel!();
                }

                navigator.pop(false);
              },
              child: Text(widget.cancelTitle!)
          ),
        if (widget.okTitle != null)
          ElevatedButton(
              onPressed: isBusy ? null : () async {
                error = null;

                setState(() { isBusy = true; });
                try {
                  if (widget.onOk != null) {
                    await widget.onOk!();
                  }

                  navigator.pop(true);
                } catch (err) {
                  if (err is Exception) {
                    error = err;
                  } else {
                    error = Exception(err);
                  }
                } finally {
                  setState(() { isBusy = false; });
                }
              },
              child: Row(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  if (isBusy)
                    const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                      ),
                    ),
                  if (isBusy)
                    const SizedBox(width: 8),
                  Text(widget.okTitle!)
                ]
              ),
         ),
      ]
      );
  }
}

Future<bool?> showConfirmDialog(
  BuildContext context,
  {
    required String title,
    Widget? content,
    String? cancelTitle,
    String? okTitle,
    Function? onCancel,
    Function? onOk,
  }
) {
  return showDialog<bool>(
    context: context,
    builder: (_) => DialogConfirm(
      title: title,
      content: content,
      cancelTitle: cancelTitle,
      okTitle: okTitle,
      onCancel: onCancel,
      onOk: onOk,
    )
  );
}
