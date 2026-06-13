import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/database_service.dart';
import '../services/background_sync_service.dart';
import 'accounts_provider.dart';

/// Provider for BackgroundSyncService.
final backgroundSyncServiceProvider = Provider<BackgroundSyncService>((ref) {
  final db = ref.watch(databaseServiceProvider);
  return BackgroundSyncService(db);
});

/// Sync interval options in minutes.
const syncIntervalOptions = [15, 30, 60, 360, 0]; // 0 = manual only

/// Provider for current sync interval setting.
final syncIntervalProvider = FutureProvider<int>((ref) async {
  final db = ref.watch(databaseServiceProvider);
  final value = await db.getSetting('sync_interval_minutes');
  if (value == null) return 30;
  return int.tryParse(value) ?? 30;
});

/// Notifier for settings changes.
class SettingsNotifier extends StateNotifier<AsyncValue<void>> {
  final DatabaseService _db;
  final BackgroundSyncService _backgroundSync;
  final Ref _ref;

  SettingsNotifier(this._db, this._backgroundSync, this._ref)
      : super(const AsyncValue.data(null));

  Future<void> updateSyncInterval(int minutes) async {
    await _db.setSetting('sync_interval_minutes', minutes.toString());
    await _backgroundSync.updateSyncInterval(minutes);
    _ref.invalidate(syncIntervalProvider);
  }

  Future<void> updateLanguage(String languageCode) async {
    await _db.setSetting('language', languageCode);
  }

  Future<String?> getLanguage() async {
    return await _db.getSetting('language');
  }
}

final settingsNotifierProvider =
    StateNotifierProvider<SettingsNotifier, AsyncValue<void>>((ref) {
  final db = ref.watch(databaseServiceProvider);
  final bgSync = ref.watch(backgroundSyncServiceProvider);
  return SettingsNotifier(db, bgSync, ref);
});
