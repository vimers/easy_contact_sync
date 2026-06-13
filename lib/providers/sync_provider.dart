import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/account.dart';
import '../models/conflict_item.dart';
import '../models/sync_record.dart';
import '../services/sync/sync_engine.dart';
import 'accounts_provider.dart';
import 'contacts_provider.dart';

/// Provider for SyncEngine.
final syncEngineProvider = Provider<SyncEngine>((ref) {
  final db = ref.watch(databaseServiceProvider);
  final secureStorage = ref.watch(secureStorageProvider);
  final localContacts = ref.watch(localContactServiceProvider);
  return SyncEngine(db: db, secureStorage: secureStorage, localContacts: localContacts);
});

/// State for the current sync operation.
class SyncState {
  final bool isSyncing;
  final String? statusMessage;
  final SyncResult? lastResult;
  final List<ConflictItem> pendingConflicts;

  const SyncState({
    this.isSyncing = false,
    this.statusMessage,
    this.lastResult,
    this.pendingConflicts = const [],
  });

  SyncState copyWith({
    bool? isSyncing,
    String? statusMessage,
    SyncResult? lastResult,
    List<ConflictItem>? pendingConflicts,
  }) {
    return SyncState(
      isSyncing: isSyncing ?? this.isSyncing,
      statusMessage: statusMessage ?? this.statusMessage,
      lastResult: lastResult ?? this.lastResult,
      pendingConflicts: pendingConflicts ?? this.pendingConflicts,
    );
  }
}

/// Notifier for sync operations.
class SyncNotifier extends StateNotifier<SyncState> {
  final SyncEngine _syncEngine;
  final Ref _ref;

  SyncNotifier(this._syncEngine, this._ref) : super(const SyncState());

  /// Trigger a manual sync for all accounts.
  Future<void> syncAll() async {
    state = state.copyWith(isSyncing: true, statusMessage: 'Syncing...');

    try {
      final accounts = await _ref.read(accountsProvider.future);
      final allConflicts = <ConflictItem>[];

      for (final account in accounts) {
        state = state.copyWith(statusMessage: 'Syncing ${account.username}...');
        final result = await _syncEngine.sync(account);
        allConflicts.addAll(result.conflicts);
      }

      state = state.copyWith(
        isSyncing: false,
        statusMessage: 'Sync complete',
        pendingConflicts: allConflicts,
      );

      // Refresh contacts list after sync
      _ref.invalidate(contactsProvider);
    } catch (e) {
      state = state.copyWith(
        isSyncing: false,
        statusMessage: 'Sync failed: $e',
      );
    }
  }

  /// Resolve conflicts with user choices.
  Future<void> resolveConflicts(Account account, List<ConflictItem> resolutions) async {
    state = state.copyWith(isSyncing: true, statusMessage: 'Applying resolutions...');
    try {
      await _syncEngine.applyResolutions(account, resolutions);
      state = state.copyWith(
        isSyncing: false,
        statusMessage: 'Conflicts resolved',
        pendingConflicts: [],
      );
      _ref.invalidate(contactsProvider);
    } catch (e) {
      state = state.copyWith(
        isSyncing: false,
        statusMessage: 'Resolution failed: $e',
      );
    }
  }
}

/// Provider for sync state.
final syncNotifierProvider =
    StateNotifierProvider<SyncNotifier, SyncState>((ref) {
  final syncEngine = ref.watch(syncEngineProvider);
  return SyncNotifier(syncEngine, ref);
});

/// Provider for sync logs.
final syncLogsProvider = FutureProvider.family<List<SyncLog>, int>((ref, accountId) async {
  final db = ref.watch(databaseServiceProvider);
  final rows = await db.getSyncLogs(accountId);
  return rows.map((r) => SyncLog.fromMap(r)).toList();
});

/// Provider for latest sync log.
final latestSyncLogProvider = FutureProvider.family<SyncLog?, int>((ref, accountId) async {
  final db = ref.watch(databaseServiceProvider);
  final row = await db.getLatestSyncLog(accountId);
  return row != null ? SyncLog.fromMap(row) : null;
});
