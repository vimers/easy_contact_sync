import 'package:workmanager/workmanager.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../models/account.dart';
import '../models/sync_record.dart';
import 'database_service.dart';
import 'secure_storage_service.dart';
import 'local_contact_service.dart';
import 'sync/sync_engine.dart';

/// Background sync service using WorkManager.
class BackgroundSyncService {
  static const String _taskName = 'easycontactsync_background_sync';

  final DatabaseService _db;

  BackgroundSyncService(this._db);

  /// Initialize background sync. Call once at app startup.
  Future<void> initialize() async {
    await Workmanager().initialize(_callbackDispatcher, isInDebugMode: false);
    await _setupNotifications();
  }

  /// Schedule periodic background sync with given interval in minutes.
  Future<void> schedulePeriodicSync(int intervalMinutes) async {
    if (intervalMinutes <= 0) {
      await cancelPeriodicSync();
      return;
    }

    await Workmanager().registerPeriodicTask(
      _taskName,
      _taskName,
      frequency: Duration(minutes: intervalMinutes),
      constraints: Constraints(
        networkType: NetworkType.connected,
      ),
      existingWorkPolicy: ExistingWorkPolicy.replace,
      backoffPolicy: BackoffPolicy.linear,
      backoffPolicyDelay: const Duration(minutes: 5),
    );
  }

  /// Cancel the periodic background sync.
  Future<void> cancelPeriodicSync() async {
    await Workmanager().cancelByUniqueName(_taskName);
  }

  /// Get the configured sync interval from settings.
  Future<int> getConfiguredInterval() async {
    final value = await _db.getSetting('sync_interval_minutes');
    if (value == null) return 30; // default: 30 minutes
    return int.tryParse(value) ?? 30;
  }

  /// Update the sync interval setting and reschedule.
  Future<void> updateSyncInterval(int minutes) async {
    await _db.setSetting('sync_interval_minutes', minutes.toString());
    await schedulePeriodicSync(minutes);
  }

  // ── Notifications ──

  FlutterLocalNotificationsPlugin? _notifications;

  Future<void> _setupNotifications() async {
    _notifications = FlutterLocalNotificationsPlugin();
    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosSettings = DarwinInitializationSettings();
    await _notifications!.initialize(
      const InitializationSettings(android: androidSettings, iOS: iosSettings),
    );
  }

  Future<void> showNotification({
    required String title,
    required String body,
    int id = 0,
  }) async {
    if (_notifications == null) return;
    const androidDetails = AndroidNotificationDetails(
      'sync_channel',
      'Sync Notifications',
      importance: Importance.defaultImportance,
      priority: Priority.defaultPriority,
    );
    const iosDetails = DarwinNotificationDetails();
    await _notifications!.show(
      id,
      title,
      body,
      const NotificationDetails(android: androidDetails, iOS: iosDetails),
    );
  }
}

/// Top-level callback for WorkManager. Must be top-level.
@pragma('vm:entry-point')
void _callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    if (task != BackgroundSyncService._taskName) return true;

    try {
      final db = DatabaseService();
      final secureStorage = SecureStorageService();
      final localContacts = LocalContactService();
      final syncEngine = SyncEngine(
        db: db,
        secureStorage: secureStorage,
        localContacts: localContacts,
      );

      // Sync all accounts
      final accountRows = await db.getAllAccounts();
      for (final row in accountRows) {
        final account = Account.fromMap(row);
        final result = await syncEngine.sync(account);

        if (result.status == SyncStatus.failure) {
          // Show error notification (via isolate port or similar)
          // Note: notifications from background are platform-specific
        }
      }

      return true;
    } catch (_) {
      return false;
    }
  });
}
