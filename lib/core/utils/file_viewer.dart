import 'file_viewer_stub.dart'
    if (dart.library.html) 'file_viewer_web.dart'
    if (dart.library.io) 'file_viewer_io.dart';

abstract class FileViewer {
  /// Opens [bytes] in the system / browser viewer.
  /// On Web, opens in a new browser tab with native browser viewing.
  /// On Desktop, opens via the default system viewer application.
  static Future<void> viewBytes(
    List<int> bytes,
    String fileName, {
    String? mimeType,
  }) =>
      viewBytesImpl(bytes, fileName, mimeType: mimeType);
}
