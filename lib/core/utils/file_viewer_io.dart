import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

Future<void> viewBytesImpl(
  List<int> bytes,
  String fileName, {
  String? mimeType,
}) async {
  final tempDir = await getTemporaryDirectory();
  final tempFile = File(p.join(tempDir.path, fileName));
  await tempFile.writeAsBytes(bytes);
  if (Platform.isWindows) {
    await Process.run('explorer.exe', [tempFile.path]);
  }
}
