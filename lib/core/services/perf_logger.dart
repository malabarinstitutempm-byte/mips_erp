// lib/core/services/perf_logger.dart
// Development-only Supabase Performance & Network Instrumentation for Flutter Admin App

import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

class PerfEntry {
  final String id;
  final DateTime timestamp;
  final String screen;
  final String action;
  final String method;
  final String url;
  final String endpoint;
  final String? columns;
  final int requestBytes;
  final int responseBytes;
  final int rowCount;
  final double durationMs;
  final int statusCode;

  PerfEntry({
    required this.id,
    required this.timestamp,
    required this.screen,
    required this.action,
    required this.method,
    required this.url,
    required this.endpoint,
    this.columns,
    required this.requestBytes,
    required this.responseBytes,
    required this.rowCount,
    required this.durationMs,
    required this.statusCode,
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'timestamp': timestamp.toIso8601String(),
        'screen': screen,
        'action': action,
        'method': method,
        'endpoint': endpoint,
        'columns': columns,
        'requestBytes': requestBytes,
        'responseBytes': responseBytes,
        'rowCount': rowCount,
        'durationMs': durationMs,
        'statusCode': statusCode,
      };
}

class PerfLogger {
  static final PerfLogger instance = PerfLogger._();
  PerfLogger._();

  String currentScreen = 'AdminInit';
  String currentAction = 'InitialLoad';
  final List<PerfEntry> entries = [];

  void setScreen(String screen, [String action = 'ScreenLoad']) {
    currentScreen = screen;
    currentAction = action;
  }

  void setAction(String action) {
    currentAction = action;
  }

  void record(PerfEntry entry) {
    entries.add(entry);
    if (kDebugMode) {
      final kb = (entry.responseBytes / 1024).toStringAsFixed(2);
      final colStr = entry.columns != null ? ' [cols: ${entry.columns}]' : '';
      debugPrint(
        '⚡ [PERF][${entry.screen}] ${entry.method} ${entry.endpoint} -> '
        '${entry.rowCount} rows, ${kb} KB, ${entry.durationMs.toStringAsFixed(1)}ms$colStr',
      );
    }
  }

  void clear() {
    entries.clear();
  }

  Map<String, dynamic> getSummary() {
    final Map<String, dynamic> summary = {};
    for (final e in entries) {
      if (!summary.containsKey(e.screen)) {
        summary[e.screen] = {
          'requestCount': 0,
          'totalBytes': 0,
          'totalDurationMs': 0.0,
          'endpoints': <String, int>{},
        };
      }
      final s = summary[e.screen] as Map<String, dynamic>;
      s['requestCount'] = (s['requestCount'] as int) + 1;
      s['totalBytes'] = (s['totalBytes'] as int) + e.responseBytes;
      s['totalDurationMs'] = (s['totalDurationMs'] as double) + e.durationMs;
      final epMap = s['endpoints'] as Map<String, int>;
      epMap[e.endpoint] = (epMap[e.endpoint] ?? 0) + 1;
    }
    return summary;
  }
}

class PerfLoggingHttpClient extends http.BaseClient {
  final http.Client _inner;

  PerfLoggingHttpClient([http.Client? client]) : _inner = client ?? http.Client();

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final stopwatch = Stopwatch().start();
    final url = request.url;
    final method = request.method;

    int reqBytes = request.contentLength ?? 0;

    http.StreamedResponse streamedResponse;
    try {
      streamedResponse = await _inner.send(request);
    } catch (e) {
      final duration = stopwatch.elapsedMicroseconds / 1000.0;
      PerfLogger.instance.record(PerfEntry(
        id: DateTime.now().microsecondsSinceEpoch.toString(),
        timestamp: DateTime.now(),
        screen: PerfLogger.instance.currentScreen,
        action: PerfLogger.instance.currentAction,
        method: method,
        url: url.toString(),
        endpoint: _parseEndpoint(url),
        columns: url.queryParameters['select'],
        requestBytes: reqBytes,
        responseBytes: 0,
        rowCount: 0,
        durationMs: duration,
        statusCode: 0,
      ));
      rethrow;
    }

    final duration = stopwatch.elapsedMicroseconds / 1000.0;

    // Buffer response bytes to measure payload and rows count
    final responseBytes = await streamedResponse.stream.toBytes();
    final resLen = responseBytes.length;
    int rowCount = 0;

    try {
      final bodyStr = utf8.decode(responseBytes);
      if (bodyStr.trim().startsWith('[') || bodyStr.trim().startsWith('{')) {
        final decoded = jsonDecode(bodyStr);
        if (decoded is List) {
          rowCount = decoded.length;
        } else if (decoded is Map) {
          rowCount = 1;
        }
      }
    } catch (_) {}

    PerfLogger.instance.record(PerfEntry(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      timestamp: DateTime.now(),
      screen: PerfLogger.instance.currentScreen,
      action: PerfLogger.instance.currentAction,
      method: method,
      url: url.toString(),
      endpoint: _parseEndpoint(url),
      columns: url.queryParameters['select'],
      requestBytes: reqBytes,
      responseBytes: resLen,
      rowCount: rowCount,
      durationMs: duration,
      statusCode: streamedResponse.statusCode,
    ));

    return http.StreamedResponse(
      Stream.value(responseBytes),
      streamedResponse.statusCode,
      contentLength: resLen,
      request: streamedResponse.request,
      headers: streamedResponse.headers,
      isRedirect: streamedResponse.isRedirect,
      persistentConnection: streamedResponse.persistentConnection,
      reasonPhrase: streamedResponse.reasonPhrase,
    );
  }

  String _parseEndpoint(Uri url) {
    final path = url.path;
    if (path.contains('/rest/v1/rpc/')) {
      return 'rpc:${path.split('/rest/v1/rpc/').last.split('/').first}';
    }
    if (path.contains('/rest/v1/')) {
      return 'table:${path.split('/rest/v1/').last.split('/').first}';
    }
    if (path.contains('/auth/v1/')) {
      return 'auth:${path.split('/auth/v1/').last.split('/').first}';
    }
    return path;
  }
}
