/// A captured error/warning persisted to the `error_log` table.
///
/// Used to surface crashes and sync failures that would otherwise be silent
/// (especially in release builds, where Flutter's red error screen is stripped).
class ErrorLog {
  final int? id;
  final DateTime timestamp;

  /// Where the error originated.
  /// 'flutter'  — FlutterError.onError (framework build/layout errors)
  /// 'platform' — PlatformDispatcher.instance.onError
  /// 'zone'     — runZonedGuarded (uncaught async errors)
  /// 'sync'     — caught failure during a sync operation
  /// 'background' — failure in the background sync isolate
  final String source;

  /// Short human-readable message, e.g. the exception.toString().
  final String message;

  /// Optional stack trace text.
  final String? stackTrace;

  /// Whether the user has opened/viewed this entry (drives the settings badge).
  final bool isRead;

  /// True if this came from an uncaught exception rather than an expected,
  /// already-handled sync failure. Uncaught entries trigger the full crash
  /// screen; sync failures only update the Settings badge.
  bool get isUncaught =>
      source == 'flutter' || source == 'platform' || source == 'zone';

  const ErrorLog({
    this.id,
    required this.timestamp,
    required this.source,
    required this.message,
    this.stackTrace,
    this.isRead = false,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'timestamp': timestamp.toIso8601String(),
      'source': source,
      'message': message,
      'stack_trace': stackTrace,
      'is_read': isRead ? 1 : 0,
    };
  }

  factory ErrorLog.fromMap(Map<String, dynamic> map) {
    return ErrorLog(
      id: map['id'] as int?,
      timestamp: DateTime.parse(map['timestamp'] as String),
      source: map['source'] as String,
      message: map['message'] as String,
      stackTrace: map['stack_trace'] as String?,
      isRead: (map['is_read'] as int?) == 1,
    );
  }

  ErrorLog copyWith({bool? isRead}) {
    return ErrorLog(
      id: id,
      timestamp: timestamp,
      source: source,
      message: message,
      stackTrace: stackTrace,
      isRead: isRead ?? this.isRead,
    );
  }
}
