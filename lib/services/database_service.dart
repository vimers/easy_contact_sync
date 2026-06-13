import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as p;

/// Database helper for sync metadata.
class DatabaseService {
  static const _dbName = 'easycontactsync.db';
  static const _dbVersion = 1;

  Database? _db;

  Future<Database> get database async {
    _db ??= await _initDb();
    return _db!;
  }

  Future<Database> _initDb() async {
    final dbPath = await getDatabasesPath();
    final path = p.join(dbPath, _dbName);
    return openDatabase(
      path,
      version: _dbVersion,
      onCreate: _onCreate,
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
}
