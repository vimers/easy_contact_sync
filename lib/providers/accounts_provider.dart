import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/account.dart';
import '../services/database_service.dart';
import '../services/secure_storage_service.dart';

/// Provider for the DatabaseService singleton.
final databaseServiceProvider = Provider<DatabaseService>((ref) {
  return DatabaseService();
});

/// Provider for all CardDAV accounts.
final accountsProvider = FutureProvider<List<Account>>((ref) async {
  final db = ref.watch(databaseServiceProvider);
  final rows = await db.getAllAccounts();
  return rows.map((r) => Account.fromMap(r)).toList();
});

/// Provider for a single account by ID.
final accountProvider = FutureProvider.family<Account?, int>((ref, id) async {
  final db = ref.watch(databaseServiceProvider);
  final row = await db.getAccount(id);
  return row != null ? Account.fromMap(row) : null;
});

/// Notifier for account CRUD operations.
class AccountNotifier extends StateNotifier<AsyncValue<List<Account>>> {
  final DatabaseService _db;
  final Ref _ref;

  AccountNotifier(this._db, this._ref) : super(const AsyncValue.loading()) {
    _loadAccounts();
  }

  Future<void> _loadAccounts() async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() async {
      final rows = await _db.getAllAccounts();
      return rows.map((r) => Account.fromMap(r)).toList();
    });
  }

  Future<Account> addAccount({
    required String serverUrl,
    required String username,
    required String password,
  }) async {
    try {
      final account = Account(
        serverUrl: serverUrl,
        username: username,
        createdAt: DateTime.now(),
      );
      debugPrint('DEBUG addAccount: inserting into DB...');
      final id = await _db.insertAccount(account.toMap(excludeId: true));
      debugPrint('DEBUG addAccount: got id=$id');
      final created = account.copyWith(id: id);

      // Store password securely
      debugPrint('DEBUG addAccount: saving password...');
      final secureStorage = _ref.read(secureStorageProvider);
      await secureStorage.savePassword(id, password);
      debugPrint('DEBUG addAccount: password saved');

      _ref.invalidate(accountsProvider);
      await _loadAccounts();
      return created;
    } catch (e, st) {
      debugPrint('DEBUG addAccount ERROR: $e');
      debugPrint('DEBUG addAccount STACK: $st');
      rethrow;
    }
  }

  Future<void> deleteAccount(int id) async {
    await _db.deleteAccount(id);
    await _db.deleteSyncMetaForAccount(id);
    final secureStorage = _ref.read(secureStorageProvider);
    await secureStorage.deleteAllForAccount(id);
    _ref.invalidate(accountsProvider);
    await _loadAccounts();
  }
}

final accountNotifierProvider =
    StateNotifierProvider<AccountNotifier, AsyncValue<List<Account>>>((ref) {
  final db = ref.watch(databaseServiceProvider);
  return AccountNotifier(db, ref);
});

/// Provider for SecureStorageService.
final secureStorageProvider = Provider<SecureStorageService>((ref) {
  return SecureStorageService();
});
