// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use
import 'dart:html' as html;

Future<void> viewBytesImpl(
  List<int> bytes,
  String fileName, {
  String? mimeType,
}) async {
  final effectiveMime = mimeType ?? (fileName.endsWith('.pdf') ? 'application/pdf' : 'application/octet-stream');
  final blob = html.Blob([bytes], effectiveMime);
  final url = html.Url.createObjectUrlFromBlob(blob);
  html.window.open(url, '_blank');
}
