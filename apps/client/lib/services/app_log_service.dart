import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum AppLogLevel {
  debug(10, 'DEBUG'),
  info(20, 'INFO'),
  warning(30, 'WARN'),
  error(40, 'ERROR');

  const AppLogLevel(this.priority, this.label);

  final int priority;
  final String label;
}

class AppLogEntry {
  const AppLogEntry({
    required this.id,
    required this.timestamp,
    required this.level,
    required this.source,
    required this.message,
    this.error,
    this.stackTrace,
  });

  final String id;
  final DateTime timestamp;
  final AppLogLevel level;
  final String source;
  final String message;
  final String? error;
  final String? stackTrace;

  Map<String, dynamic> toJson() => {
    'id': id,
    'timestamp': timestamp.toIso8601String(),
    'level': level.name,
    'source': source,
    'message': message,
    if (error != null) 'error': error,
    if (stackTrace != null) 'stackTrace': stackTrace,
  };

  factory AppLogEntry.fromJson(Map<String, dynamic> json) {
    return AppLogEntry(
      id: json['id'] as String? ?? '',
      timestamp:
          DateTime.tryParse(json['timestamp'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
      level: AppLogLevel.values.firstWhere(
        (level) => level.name == json['level'],
        orElse: () => AppLogLevel.info,
      ),
      source: json['source'] as String? ?? 'app',
      message: json['message'] as String? ?? '',
      error: json['error'] as String?,
      stackTrace: json['stackTrace'] as String?,
    );
  }
}

class AppLogService extends ChangeNotifier {
  AppLogService._();

  static final AppLogService instance = AppLogService._();

  static const _storageKey = 'app_logs';
  static const _maxEntries = 1000;
  static const _maxAge = Duration(days: 14);
  static const _maxFieldLength = 4000;

  final List<AppLogEntry> _entries = [];
  Future<void> _writeQueue = Future.value();
  bool _initialized = false;

  List<AppLogEntry> get entries => List.unmodifiable(_entries.reversed);

  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_storageKey);
    if (raw != null && raw.isNotEmpty) {
      try {
        final decoded = json.decode(raw) as List<dynamic>;
        _entries
          ..clear()
          ..addAll(
            decoded.whereType<Map<String, dynamic>>().map(AppLogEntry.fromJson),
          );
      } catch (_) {
        await prefs.remove(_storageKey);
      }
    }
    await _pruneAndPersist();
  }

  Future<void> log(
    AppLogLevel level,
    String message, {
    String source = 'app',
    Object? error,
    StackTrace? stackTrace,
  }) async {
    final now = DateTime.now();
    _entries.add(
      AppLogEntry(
        id: '${now.microsecondsSinceEpoch}_${_entries.length}',
        timestamp: now,
        level: level,
        source: _sanitize(source, maxLength: 120),
        message: _sanitize(message),
        error: error == null ? null : _sanitize('$error'),
        stackTrace: stackTrace == null ? null : _sanitize('$stackTrace'),
      ),
    );
    _pruneInMemory();
    notifyListeners();
    _writeQueue = _writeQueue.then((_) => _persist());
    await _writeQueue;
  }

  Future<void> debug(String message, {String source = 'app'}) =>
      log(AppLogLevel.debug, message, source: source);

  Future<void> info(String message, {String source = 'app'}) =>
      log(AppLogLevel.info, message, source: source);

  Future<void> warning(
    String message, {
    String source = 'app',
    Object? error,
    StackTrace? stackTrace,
  }) => log(
    AppLogLevel.warning,
    message,
    source: source,
    error: error,
    stackTrace: stackTrace,
  );

  Future<void> error(
    String message, {
    String source = 'app',
    Object? error,
    StackTrace? stackTrace,
  }) => log(
    AppLogLevel.error,
    message,
    source: source,
    error: error,
    stackTrace: stackTrace,
  );

  List<AppLogEntry> filter(AppLogLevel minimumLevel) {
    return entries
        .where((entry) => entry.level.priority >= minimumLevel.priority)
        .toList(growable: false);
  }

  String formatEntries(List<AppLogEntry> logs) {
    return logs
        .map((entry) {
          final buffer = StringBuffer()
            ..write(entry.timestamp.toIso8601String())
            ..write(' [${entry.level.label}]')
            ..write(' ${entry.source}: ')
            ..write(entry.message);
          if (entry.error != null && entry.error!.isNotEmpty) {
            buffer.write('\n  error: ${entry.error}');
          }
          if (entry.stackTrace != null && entry.stackTrace!.isNotEmpty) {
            buffer.write('\n  stack: ${entry.stackTrace}');
          }
          return buffer.toString();
        })
        .join('\n\n');
  }

  Future<void> clear({AppLogLevel? belowLevel}) async {
    if (belowLevel == null) {
      _entries.clear();
    } else {
      _entries.removeWhere(
        (entry) => entry.level.priority < belowLevel.priority,
      );
    }
    notifyListeners();
    await _persist();
  }

  Future<void> _pruneAndPersist() async {
    _pruneInMemory();
    notifyListeners();
    await _persist();
  }

  void _pruneInMemory() {
    final cutoff = DateTime.now().subtract(_maxAge);
    _entries.removeWhere((entry) => entry.timestamp.isBefore(cutoff));
    if (_entries.length > _maxEntries) {
      _entries.removeRange(0, _entries.length - _maxEntries);
    }
  }

  Future<void> _persist() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _storageKey,
        json.encode(_entries.map((entry) => entry.toJson()).toList()),
      );
    } catch (_) {
      // Logging must never break the app path that produced the log.
    }
  }

  String _sanitize(String value, {int maxLength = _maxFieldLength}) {
    final redacted = value
        .replaceAll(
          RegExp(r'sk-[A-Za-z0-9_\-]{8,}'),
          'sk-***',
        )
        .replaceAll(
          RegExp(r'AIza[A-Za-z0-9_\-]{30,}'),
          'AIza***',
        )
        .replaceAll(
          RegExp(r'Bearer\s+[A-Za-z0-9._~+/=\-]{8,}'),
          'Bearer [redacted]',
        )
        .replaceAll(
          RegExp(r'(api[_\-]?key["\s:=]+)[^,\s"]{8,}', caseSensitive: false),
          r'$1[redacted]',
        )
        .replaceAll(
          RegExp(r'(authorization["\s:=]+)[^,\s"]+', caseSensitive: false),
          r'$1[redacted]',
        )
        .replaceAll(
          RegExp(r'(/Users/)[^/]+'),
          r'$1[redacted]',
        )
        .replaceAll(
          RegExp(r'(/home/)[^/]+'),
          r'$1[redacted]',
        );
    if (redacted.length <= maxLength) return redacted;
    return '${redacted.substring(0, maxLength)}...';
  }
}

class AppLog {
  static Future<void> debug(String message, {String source = 'app'}) =>
      AppLogService.instance.debug(message, source: source);

  static Future<void> info(String message, {String source = 'app'}) =>
      AppLogService.instance.info(message, source: source);

  static Future<void> warning(
    String message, {
    String source = 'app',
    Object? error,
    StackTrace? stackTrace,
  }) => AppLogService.instance.warning(
    message,
    source: source,
    error: error,
    stackTrace: stackTrace,
  );

  static Future<void> error(
    String message, {
    String source = 'app',
    Object? error,
    StackTrace? stackTrace,
  }) => AppLogService.instance.error(
    message,
    source: source,
    error: error,
    stackTrace: stackTrace,
  );
}
