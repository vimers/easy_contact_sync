import 'dart:async';

import '../models/error_log.dart';
import 'database_service.dart';

/// Captures errors from anywhere — including before `runApp` and outside
/// Riverpod's [ProviderScope] — persists them to the database, and notifies
/// live listeners.
///
/// It must be a plain singleton (not a Riverpod provider) because the global
/// Flutter error handlers (`FlutterError.onError`, `PlatformDispatcher.onError`,
/// `runZonedGuarded`) are wired up before the [ProviderScope] exists.
///
/// Why this exists: in release builds Flutter's red error screen is stripped,
/// so uncaught errors used to silently blank the app. Logging them here lets the
/// UI surface a real error screen and keeps a history the user can read in
/// Settings → Error Log even after a restart.
class ErrorLoggerService {
  ErrorLoggerService._();
  static final ErrorLoggerService instance = ErrorLoggerService._();

  final DatabaseService _db = DatabaseService();

  final StreamController<List<ErrorLog>> _controller =
      StreamController<List<ErrorLog>>.broadcast();

  /// Emits the current in-memory error list whenever it changes.
  Stream<List<ErrorLog>> get stream => _controller.stream;

  List<ErrorLog> _cache = const [];

  /// Current list of captured errors (newest first), unmodifiable.
  List<ErrorLog> get current => List.unmodifiable(_cache);

  /// Load recent errors from the DB into the cache and emit them.
  /// Called by the provider on startup so history survives a relaunch.
  Future<List<ErrorLog>> loadRecent({int limit = 200}) async {
    try {
      final rows = await _db.getErrorLogs(limit: limit);
      _cache = rows.map(ErrorLog.fromMap).toList();
    } catch (_) {
      // If the DB isn't available yet, keep whatever we have.
    }
    _controller.add(_cache);
    return _cache;
  }

  /// Record an error from [source]. Fire-and-forget on the DB side so logging
  /// can never itself throw and re-enter the error handler.
  void log({
    required String source,
    required Object error,
    StackTrace? stackTrace,
  }) {
    final message = error.toString();
    final stack = stackTrace?.toString();

    // Also echo to the console so it shows up in `adb logcat` under `flutter`.
    // ignore: avoid_print
    print('[$source] $message');
    if (stack != null) {
      // ignore: avoid_print
      print(stack);
    }

    final entry = ErrorLog(
      timestamp: DateTime.now(),
      source: source,
      message: message,
      stackTrace: stack,
    );

    // Optimistically update the cache + notify listeners before the async write
    // lands, so the UI reacts immediately.
    _cache = [entry, ..._cache];
    _controller.add(_cache);

    _db.insertErrorLog(entry.toMap()).catchError((_) => 0);
  }

  /// Mark every cached entry as read (drives the Settings badge).
  Future<void> markAllRead() async {
    await _db.markAllErrorsRead();
    _cache = _cache.map((e) => e.copyWith(isRead: true)).toList();
    _controller.add(_cache);
  }

  /// Delete all persisted + cached errors.
  Future<void> clearAll() async {
    await _db.clearAllErrors();
    _cache = const [];
    _controller.add(_cache);
  }

  int get unreadCount => _cache.where((e) => !e.isRead).length;
}
