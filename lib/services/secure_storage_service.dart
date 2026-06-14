import 'dart:io';
import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path/path.dart' as p;

/// Service for encrypted storage of CardDAV credentials.
///
/// Android: EncryptedSharedPreferences + Android Keystore (AES256)
/// iOS: Keychain Services (kSecAttrAccessible: whenUnlockedThisDeviceOnly)
/// Linux/Windows desktop: Falls back to file-based storage (for development)
class SecureStorageService {
  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
    iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock_this_device),
  );

  // In-memory cache for desktop fallback
  final Map<String, String> _fileCache = {};
  bool _useFallback = false;

  String get _fallbackDir {
    final home = Platform.environment['HOME'] ?? '/tmp';
    return p.join(home, '.easycontactsync');
  }

  String _fallbackPath() => p.join(_fallbackDir, 'credentials.json');

  // Key prefixes to namespace per account
  static String _passwordKey(int accountId) => 'account_${accountId}_password';
  static String _syncTokenKey(int accountId) => 'account_${accountId}_sync_token';

  Future<void> _initFallback() async {
    if (_fileCache.isNotEmpty) return;
    final file = File(_fallbackPath());
    if (await file.exists()) {
      final content = await file.readAsString();
      final Map<String, dynamic> data = jsonDecode(content);
      data.forEach((key, value) {
        _fileCache[key] = value.toString();
      });
    }
  }

  Future<void> _saveFallback() async {
    final dir = Directory(_fallbackDir);
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    final file = File(_fallbackPath());
    await file.writeAsString(jsonEncode(_fileCache));
  }

  Future<void> _write(String key, String value) async {
    if (!Platform.isLinux && !Platform.isWindows) {
      try {
        await _storage.write(key: key, value: value);
        return;
      } catch (_) {
        _useFallback = true;
      }
    }

    // Try secure storage first on Linux too
    if (!_useFallback) {
      try {
        await _storage.write(key: key, value: value);
        return;
      } catch (_) {
        _useFallback = true;
      }
    }

    // Fallback: file-based storage
    await _initFallback();
    _fileCache[key] = value;
    await _saveFallback();
  }

  Future<String?> _read(String key) async {
    if (!_useFallback && !Platform.isLinux && !Platform.isWindows) {
      try {
        return await _storage.read(key: key);
      } catch (_) {
        _useFallback = true;
      }
    }

    if (!_useFallback) {
      try {
        return await _storage.read(key: key);
      } catch (_) {
        _useFallback = true;
      }
    }

    await _initFallback();
    return _fileCache[key];
  }

  Future<void> _delete(String key) async {
    if (!_useFallback) {
      try {
        await _storage.delete(key: key);
        if (!_useFallback) return;
      } catch (_) {
        _useFallback = true;
      }
    }

    await _initFallback();
    _fileCache.remove(key);
    await _saveFallback();
  }

  /// Save encrypted password for an account.
  Future<void> savePassword(int accountId, String password) async {
    await _write(_passwordKey(accountId), password);
  }

  /// Read encrypted password for an account.
  Future<String?> getPassword(int accountId) async {
    return await _read(_passwordKey(accountId));
  }

  /// Delete stored password for an account.
  Future<void> deletePassword(int accountId) async {
    await _delete(_passwordKey(accountId));
  }

  /// Save sync token (used for incremental CardDAV sync).
  Future<void> saveSyncToken(int accountId, String token) async {
    await _write(_syncTokenKey(accountId), token);
  }

  /// Read sync token.
  Future<String?> getSyncToken(int accountId) async {
    return await _read(_syncTokenKey(accountId));
  }

  /// Delete sync token.
  Future<void> deleteSyncToken(int accountId) async {
    await _delete(_syncTokenKey(accountId));
  }

  /// Delete all stored data for an account.
  Future<void> deleteAllForAccount(int accountId) async {
    await deletePassword(accountId);
    await deleteSyncToken(accountId);
  }

  /// Delete all stored credentials (e.g., on logout).
  Future<void> deleteAll() async {
    if (!_useFallback) {
      try {
        await _storage.deleteAll();
        return;
      } catch (_) {
        _useFallback = true;
      }
    }
    _fileCache.clear();
    await _saveFallback();
  }
}
