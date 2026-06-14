import 'dart:io';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:path/path.dart' as p;

/// Database helper for sync metadata.
class DatabaseService {
  static const _dbName = 'easycontactsync.db';
  static const _dbVersion = 4;

  Database? _db;

  Future<Database> get database async {
    _db ??= await _initDb();
    return _db!;
  }

  Future<Database> _initDb() async {
    // Initialize sqflite_ffi for Linux/Windows desktop
    if (Platform.isLinux || Platform.isWindows) {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    }

    final dbPath = await getDatabasesPath();
    final path = p.join(dbPath, _dbName);
    return openDatabase(
      path,
      version: _dbVersion,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
  }

  void _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE accounts (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        server_url TEXT NOT NULL,
        username TEXT NOT NULL,
        addressbook_name TEXT NOT NULL DEFAULT 'default',
        created_at TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE sync_meta (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        account_id INTEGER NOT NULL,
        uid TEXT NOT NULL,
        etag TEXT,
        last_sync_hash TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        FOREIGN KEY (account_id) REFERENCES accounts(id) ON DELETE CASCADE,
        UNIQUE(account_id, uid)
      )
    ''');

    await db.execute('''
      CREATE TABLE sync_log (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        account_id INTEGER NOT NULL,
        timestamp TEXT NOT NULL,
        status TEXT NOT NULL,
        conflicts_count INTEGER NOT NULL DEFAULT 0,
        error_message TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE settings (
        key TEXT PRIMARY KEY,
        value TEXT NOT NULL
      )
    ''');

    await _createErrorLogTable(db);

    await _createRemoteContactCacheTable(db);

    await _createContactUidMapTable(db);
  }

  /// Create the error_log table. Shared by [onCreate] and [onUpgrade] so the
  /// schema is identical for fresh and pre-existing installs.
  Future<void> _createErrorLogTable(Database db) async {
    await db.execute('''
      CREATE TABLE error_log (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        timestamp TEXT NOT NULL,
        source TEXT NOT NULL,
        message TEXT NOT NULL,
        stack_trace TEXT,
        is_read INTEGER NOT NULL DEFAULT 0
      )
    ''');
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    // Apply migrations incrementally so any older version reaches the current one.
    if (oldVersion < 2) {
      await _createErrorLogTable(db);
    }
    if (oldVersion < 3) {
      await _createRemoteContactCacheTable(db);
    }
    if (oldVersion < 4) {
      await _createContactUidMapTable(db);
    }
  }

  /// Maps a local (device) contact id to the remote (CardDAV) UID, so contacts
  /// pulled from the server (which get a fresh device id) can still be matched
  /// to their remote counterpart on later syncs. Without this, every pull
  /// breaks the local↔remote linkage and the sync re-pushes/re-pulls forever.
  Future<void> _createContactUidMapTable(Database db) async {
    await db.execute('''
      CREATE TABLE contact_uid_map (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        account_id INTEGER NOT NULL,
        local_id TEXT NOT NULL,
        remote_uid TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        UNIQUE(account_id, local_id),
        UNIQUE(account_id, remote_uid)
      )
    ''');
  }

  /// Snapshot of remote (CardDAV) contacts per account, used to compute
  /// per-contact sync status and the sync summary without re-fetching.
  Future<void> _createRemoteContactCacheTable(Database db) async {
    await db.execute('''
      CREATE TABLE remote_contact_cache (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        account_id INTEGER NOT NULL,
        uid TEXT NOT NULL,
        etag TEXT,
        content_hash TEXT NOT NULL,
        contact_json TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        UNIQUE(account_id, uid)
      )
    ''');
  }

  // ── Accounts ──

  Future<int> insertAccount(Map<String, dynamic> account) async {
    final db = await database;
    return db.insert('accounts', account);
  }

  Future<List<Map<String, dynamic>>> getAllAccounts() async {
    final db = await database;
    return db.query('accounts', orderBy: 'created_at DESC');
  }

  Future<Map<String, dynamic>?> getAccount(int id) async {
    final db = await database;
    final results = await db.query('accounts', where: 'id = ?', whereArgs: [id]);
    return results.isNotEmpty ? results.first : null;
  }

  Future<int> deleteAccount(int id) async {
    final db = await database;
    return db.delete('accounts', where: 'id = ?', whereArgs: [id]);
  }

  // ── Sync Meta ──

  Future<void> upsertSyncMeta(int accountId, String uid, String? etag, String hash) async {
    final db = await database;
    await db.insert(
      'sync_meta',
      {
        'account_id': accountId,
        'uid': uid,
        'etag': etag,
        'last_sync_hash': hash,
        'updated_at': DateTime.now().toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<Map<String, dynamic>>> getSyncMetaForAccount(int accountId) async {
    final db = await database;
    return db.query('sync_meta', where: 'account_id = ?', whereArgs: [accountId]);
  }

  Future<int> deleteSyncMeta(int accountId, String uid) async {
    final db = await database;
    return db.delete('sync_meta', where: 'account_id = ? AND uid = ?', whereArgs: [accountId, uid]);
  }

  Future<int> deleteSyncMetaForAccount(int accountId) async {
    final db = await database;
    return db.delete('sync_meta', where: 'account_id = ?', whereArgs: [accountId]);
  }

  // ── Sync Log ──

  Future<int> insertSyncLog(Map<String, dynamic> log) async {
    final db = await database;
    return db.insert('sync_log', log);
  }

  Future<List<Map<String, dynamic>>> getSyncLogs(int accountId, {int limit = 50}) async {
    final db = await database;
    return db.query(
      'sync_log',
      where: 'account_id = ?',
      whereArgs: [accountId],
      orderBy: 'timestamp DESC',
      limit: limit,
    );
  }

  Future<Map<String, dynamic>?> getLatestSyncLog(int accountId) async {
    final db = await database;
    final results = await db.query(
      'sync_log',
      where: 'account_id = ?',
      whereArgs: [accountId],
      orderBy: 'timestamp DESC',
      limit: 1,
    );
    return results.isNotEmpty ? results.first : null;
  }

  // ── Settings ──

  Future<String?> getSetting(String key) async {
    final db = await database;
    final results = await db.query('settings', where: 'key = ?', whereArgs: [key]);
    return results.isNotEmpty ? results.first['value'] as String : null;
  }

  Future<void> setSetting(String key, String value) async {
    final db = await database;
    await db.insert(
      'settings',
      {'key': key, 'value': value},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  // ── Error Log ──

  Future<int> insertErrorLog(Map<String, dynamic> log) async {
    final db = await database;
    return db.insert('error_log', log);
  }

  Future<List<Map<String, dynamic>>> getErrorLogs({int limit = 200}) async {
    final db = await database;
    return db.query('error_log', orderBy: 'timestamp DESC', limit: limit);
  }

  Future<int> getUnreadErrorCount() async {
    final db = await database;
    final rows = await db.rawQuery(
      'SELECT COUNT(*) AS c FROM error_log WHERE is_read = 0',
    );
    return Sqflite.firstIntValue(rows) ?? 0;
  }

  Future<void> markAllErrorsRead() async {
    final db = await database;
    await db.update('error_log', {'is_read': 1}, where: 'is_read = 0');
  }

  Future<int> clearAllErrors() async {
    final db = await database;
    return db.delete('error_log');
  }

  // ── Remote Contact Cache ──

  /// Replace the entire remote snapshot for an account (called after each sync).
  Future<void> replaceRemoteCacheForAccount(
      int accountId, List<Map<String, dynamic>> rows) async {
    final db = await database;
    await db.transaction((txn) async {
      await txn.delete('remote_contact_cache',
          where: 'account_id = ?', whereArgs: [accountId]);
      for (final row in rows) {
        await txn.insert('remote_contact_cache', {
          'account_id': accountId,
          'uid': row['uid'],
          'etag': row['etag'],
          'content_hash': row['content_hash'],
          'contact_json': row['contact_json'],
          'updated_at': row['updated_at'] ?? DateTime.now().toIso8601String(),
        },
            conflictAlgorithm:
                ConflictAlgorithm.replace);
      }
    });
  }

  /// Upsert a single cached remote contact (used after resolving a conflict).
  Future<void> upsertRemoteCache(
      int accountId, Map<String, dynamic> row) async {
    final db = await database;
    await db.insert('remote_contact_cache', {
      'account_id': accountId,
      'uid': row['uid'],
      'etag': row['etag'],
      'content_hash': row['content_hash'],
      'contact_json': row['contact_json'],
      'updated_at': row['updated_at'] ?? DateTime.now().toIso8601String(),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<List<Map<String, dynamic>>> getRemoteCacheForAccount(int accountId) async {
    final db = await database;
    return db.query('remote_contact_cache',
        where: 'account_id = ?', whereArgs: [accountId]);
  }

  Future<List<Map<String, dynamic>>> getAllRemoteCache() async {
    final db = await database;
    return db.query('remote_contact_cache');
  }

  Future<int> getRemoteCacheCountForAccount(int accountId) async {
    final db = await database;
    final rows = await db.rawQuery(
        'SELECT COUNT(*) AS c FROM remote_contact_cache WHERE account_id = ?',
        [accountId]);
    return Sqflite.firstIntValue(rows) ?? 0;
  }

  // ── Contact UID Map (local id ↔ remote uid) ──

  /// Record (or update) the link between a local contact id and a remote uid.
  Future<void> upsertUidMap(int accountId, String localId, String remoteUid) async {
    final db = await database;
    await db.transaction((txn) async {
      // Remove any prior rows for this local_id or this remote_uid so neither
      // UNIQUE constraint can fire on insert.
      await txn.delete('contact_uid_map',
          where: 'account_id = ? AND (local_id = ? OR remote_uid = ?)',
          whereArgs: [accountId, localId, remoteUid]);
      await txn.insert('contact_uid_map', {
        'account_id': accountId,
        'local_id': localId,
        'remote_uid': remoteUid,
        'updated_at': DateTime.now().toIso8601String(),
      });
    });
  }

  /// All local_id → remote_uid mappings for an account.
  Future<Map<String, String>> getUidMapForAccount(int accountId) async {
    final db = await database;
    final rows = await db.query('contact_uid_map',
        where: 'account_id = ?', whereArgs: [accountId]);
    return {
      for (final r in rows) r['local_id'] as String: r['remote_uid'] as String,
    };
  }

  /// Reverse lookup: remote_uid → local_id.
  Future<Map<String, String>> getRemoteToLocalUidMap(int accountId) async {
    final db = await database;
    final rows = await db.query('contact_uid_map',
        where: 'account_id = ?', whereArgs: [accountId]);
    return {
      for (final r in rows) r['remote_uid'] as String: r['local_id'] as String,
    };
  }

  Future<void> deleteUidMapForLocal(int accountId, String localId) async {
    final db = await database;
    await db.delete('contact_uid_map',
        where: 'account_id = ? AND local_id = ?',
        whereArgs: [accountId, localId]);
  }
}
