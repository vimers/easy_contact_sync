import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/account.dart';
import '../models/conflict_item.dart';
import '../models/sync_record.dart';
import '../services/error_logger_service.dart';
import '../services/sync/sync_engine.dart';
import 'accounts_provider.dart';
import 'contact_sync_status_provider.dart';
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
      if (accounts.isEmpty) {
        state = state.copyWith(
          isSyncing: false,
          statusMessage: 'No accounts configured',
        );
        return;
      }

      final allConflicts = <ConflictItem>[];
      SyncResult? lastResult;
      int totalPushed = 0, totalPulled = 0, totalDeletedLocal = 0, totalDeletedRemote = 0;

      for (final account in accounts) {
        state = state.copyWith(statusMessage: 'Syncing ${account.username}...');
        final result = await _syncEngine.sync(account);
        lastResult = result;
        allConflicts.addAll(result.conflicts);
        totalPushed += result.pushed;
        totalPulled += result.pulled;
        totalDeletedLocal += result.deletedLocal;
        totalDeletedRemote += result.deletedRemote;
      }

      // Create a summary result
      final summaryResult = SyncResult(
        status: allConflicts.isNotEmpty ? SyncStatus.conflicts : (lastResult?.status ?? SyncStatus.success),
        pushed: totalPushed,
        pulled: totalPulled,
        deletedLocal: totalDeletedLocal,
        deletedRemote: totalDeletedRemote,
        conflicts: allConflicts,
        errorMessage: lastResult?.errorMessage,
      );

      final msg = allConflicts.isNotEmpty
          ? 'Sync complete with ${allConflicts.length} conflicts'
          : lastResult?.errorMessage != null
              ? 'Sync failed'
              : 'Sync complete';

      state = state.copyWith(
        isSyncing: false,
        statusMessage: msg,
        lastResult: summaryResult,
        pendingConflicts: allConflicts,
      );

      // Refresh contacts list and logs after sync
      _ref.invalidate(contactsProvider);
      // Bump the remote-cache version so per-contact status + Sync summary
      // recompute against the freshly cached snapshot.
      _ref.read(remoteCacheVersionProvider.notifier).state++;
      for (final account in accounts) {
        _ref.invalidate(syncLogsProvider(account.id!));
      }
    } catch (e, st) {
      // Record in the unified error log (badge only — sync failures are
      // expected, so they never trigger the full crash screen).
      ErrorLoggerService.instance.log(
        source: 'sync',
        error: e,
        stackTrace: st,
      );
      state = state.copyWith(
        isSyncing: false,
        statusMessage: 'Sync failed: $e',
        lastResult: SyncResult(status: SyncStatus.failure, errorMessage: e.toString()),
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
      _ref.read(remoteCacheVersionProvider.notifier).state++;
    } catch (e, st) {
      ErrorLoggerService.instance.log(
        source: 'sync',
        error: e,
        stackTrace: st,
      );
      state = state.copyWith(
        isSyncing: false,
        statusMessage: 'Resolution failed: $e',
      );
    }
  }

  /// Remove exact-duplicate contacts from the remote addressbook(s).
  Future<void> dedupRemote() async {
    state = state.copyWith(isSyncing: true, statusMessage: 'Removing duplicates...');
    try {
      final accounts = await _ref.read(accountsProvider.future);
      var removed = 0;
      for (final account in accounts) {
        final res = await _syncEngine.dedupRemoteContacts(account);
        removed += res.duplicatesRemoved;
      }
      _ref.read(remoteCacheVersionProvider.notifier).state++;
      state = state.copyWith(
        isSyncing: false,
        statusMessage: removed > 0 ? 'Removed $removed duplicate(s)' : 'No duplicates found',
      );
    } catch (e, st) {
      ErrorLoggerService.instance.log(source: 'sync', error: e, stackTrace: st);
      state = state.copyWith(
        isSyncing: false,
        statusMessage: 'Dedup failed: $e',
      );
    }
  }

  /// Remove exact duplicates from BOTH the device address book and the remote
  /// server. Local first (so local dups don't get re-pushed), then remote.
  /// Run this before syncing a previously-broken account.
  Future<void> dedupAll() async {
    state = state.copyWith(isSyncing: true, statusMessage: 'Removing duplicates...');
    try {
      final localService = _ref.read(localContactServiceProvider);
      final localRemoved = await localService.dedupLocalContacts();

      final accounts = await _ref.read(accountsProvider.future);
      var remoteRemoved = 0;
      for (final account in accounts) {
        remoteRemoved += (await _syncEngine.dedupRemoteContacts(account)).duplicatesRemoved;
      }

      _ref.invalidate(contactsProvider);
      _ref.read(remoteCacheVersionProvider.notifier).state++;
      state = state.copyWith(
        isSyncing: false,
        statusMessage:
            'Removed $localRemoved local + $remoteRemoved remote duplicate(s)',
      );
    } catch (e, st) {
      ErrorLoggerService.instance.log(source: 'sync', error: e, stackTrace: st);
      state = state.copyWith(
        isSyncing: false,
        statusMessage: 'Dedup failed: $e',
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
