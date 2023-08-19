import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:chameleonultragui/main.dart';
import 'package:file_picker/file_picker.dart';
import 'package:file_saver/file_saver.dart';
import 'package:path/path.dart' show basenameWithoutExtension, extension;

class FileResult {
  String name;
  String extension;
  Uint8List bytes;

  FileResult({
    required this.name,
    required this.extension,
    required this.bytes
  });

  String asText() {
    return const Utf8Decoder().convert(bytes);
  }
}

Future<FileResult?> pickFile(MyAppState appState, { bool asText = false }) async {
  FilePickerResult? result = await FilePicker.platform.pickFiles();

  if (result == null) {
    return null;
  }

  final file = result.files.single;
  Uint8List bytes = Uint8List(0);

  if (appState.onWeb) {
    if (file.bytes != null) {
      bytes = file.bytes as Uint8List;
    }
  } else {
    File filePath = File(file.path!);
    bytes = await filePath.readAsBytes();
  }

  return FileResult(
    name: basenameWithoutExtension(result.files.single.name),
    extension: extension(result.files.single.name),
    bytes: bytes,
  );
}

Future<void> saveFile({
  required MyAppState appState,
  required String fileName,
  required String fileExtension,
  required Uint8List bytes,
  MimeType mimeType = MimeType.other,
  String dialogTitle = 'Please select an output file:',
}) async {
  try {
    if (appState.onWeb) {
      await FileSaver.instance.saveFile(
          name: fileName,
          bytes: bytes,
          ext: fileExtension,
          mimeType: mimeType,
      );
    } else {
      await FileSaver.instance.saveAs(
          name: fileName,
          bytes: bytes,
          ext: fileExtension,
          mimeType: mimeType);
    }
  } on UnimplementedError catch (_) {
    String? outputFile = await FilePicker.platform.saveFile(
      dialogTitle: dialogTitle,
      fileName: '$fileName.$fileExtension',
    );

    if (outputFile != null) {
      var file = File(outputFile);
      await file.writeAsBytes(bytes);
    }
  }
}
