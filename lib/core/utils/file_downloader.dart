import 'file_downloader_stub.dart'
    if (dart.library.html) 'file_downloader_web.dart'
    if (dart.library.io) 'file_downloader_io.dart';

abstract class FileDownloader {
  /// Initiates a download of raw [bytes] with the given [fileName]
  /// On Web, this triggers a native browser download.
  /// On Desktop, this opens a Save File dialog or saves to disk.
  static Future<void> downloadBytes(
    List<int> bytes,
    String fileName, {
    String? mimeType,
  }) =>
      downloadBytesImpl(bytes, fileName, mimeType: mimeType);
}
