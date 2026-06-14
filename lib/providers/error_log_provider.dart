import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/error_log.dart';
import '../services/error_logger_service.dart';

/// Reactive view over the persisted error log.
///
/// Subscribes to [ErrorLoggerService] (the singleton written to by the global
/// error handlers, which run before the [ProviderScope] exists) and exposes the
/// current list of errors. UI uses [showCrashScreen] to decide whether to
/// overlay the full crash screen for uncaught errors.
class ErrorLogNotifier extends StateNotifier<List<ErrorLog>> {
  StreamSubscription<List<ErrorLog>>? _sub;

  ErrorLogNotifier() : super(const []) {
    // Re-sync whenever the logger emits (new error, mark-read, clear).
    _sub = ErrorLoggerService.instance.stream.listen((errors) {
      state = errors;
    });
    // Load persisted history so errors survive a relaunch; this also emits.
    ErrorLoggerService.instance.loadRecent();
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  /// True when there is at least one un-viewed *uncaught* error.
  /// Drives the full crash screen. Sync failures never set this.
  bool get showCrashScreen =>
      state.any((e) => !e.isRead && e.isUncaught);

  /// Count of entries the user hasn't seen yet (drives the Settings badge).
  int get unreadCount => state.where((e) => !e.isRead).length;

  /// Acknowledge the current errors: marks everything read, which dismisses the
  /// crash screen and clears the badge.
  Future<void> markAllRead() => ErrorLoggerService.instance.markAllRead();

  Future<void> clearAll() => ErrorLoggerService.instance.clearAll();
}

final errorLogProvider =
    StateNotifierProvider<ErrorLogNotifier, List<ErrorLog>>((ref) {
  return ErrorLogNotifier();
});
