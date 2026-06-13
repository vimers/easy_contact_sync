import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Service for encrypted storage of CardDAV credentials.
///
/// Android: EncryptedSharedPreferences + Android Keystore (AES256)
/// iOS: Keychain Services (kSecAttrAccessible: whenUnlockedThisDeviceOnly)
class SecureStorageService {
  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
    iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock_this_device),
  );

  // Key prefixes to namespace per account
  static String _passwordKey(int accountId) => 'account_${accountId}_password';
  static String _syncTokenKey(int accountId) => 'account_${accountId}_sync_token';

  /// Save encrypted password for an account.
  Future<void> savePassword(int accountId, String password) async {
    await _storage.write(key: _passwordKey(accountId), value: password);
  }

  /// Read encrypted password for an account.
  Future<String?> getPassword(int accountId) async {
    return await _storage.read(key: _passwordKey(accountId));
  }

  /// Delete stored password for an account.
  Future<void> deletePassword(int accountId) async {
    await _storage.delete(key: _passwordKey(accountId));
  }

  /// Save sync token (used for incremental CardDAV sync).
  Future<void> saveSyncToken(int accountId, String token) async {
    await _storage.write(key: _syncTokenKey(accountId), value: token);
  }

  /// Read sync token.
  Future<String?> getSyncToken(int accountId) async {
    return await _storage.read(key: _syncTokenKey(accountId));
  }

  /// Delete sync token.
  Future<void> deleteSyncToken(int accountId) async {
    await _storage.delete(key: _syncTokenKey(accountId));
  }

  /// Delete all stored data for an account.
  Future<void> deleteAllForAccount(int accountId) async {
    await deletePassword(accountId);
    await deleteSyncToken(accountId);
  }

  /// Delete all stored credentials (e.g., on logout).
  Future<void> deleteAll() async {
    await _storage.deleteAll();
  }
}
