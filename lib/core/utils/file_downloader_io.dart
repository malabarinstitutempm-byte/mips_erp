import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;

Future<void> downloadBytesImpl(
  List<int> bytes,
  String fileName, {
  String? mimeType,
}) async {
  final ext = p.extension(fileName).replaceAll('.', '');
  final destination = await FilePicker.saveFile(
    dialogTitle: 'Save File',
    fileName: fileName,
    type: ext.isNotEmpty ? FileType.custom : FileType.any,
    allowedExtensions: ext.isNotEmpty ? [ext] : null,
  );

  if (destination != null) {
    final file = File(destination);
    await file.writeAsBytes(bytes);
  }
}
