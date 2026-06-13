import '../../models/account.dart';
import '../../models/conflict_item.dart';
import '../../models/contact.dart';
import '../../models/sync_record.dart';
import '../database_service.dart';
import '../secure_storage_service.dart';
import '../carddav/carddav_client.dart';
import '../carddav/discovery.dart';
import '../carddav/operations.dart';
import '../local_contact_service.dart';
import 'diff_engine.dart';
import 'conflict_resolver.dart';

/// Core sync engine that orchestrates the full sync process.
class SyncEngine {
  final DatabaseService _db;
  final SecureStorageService _secureStorage;
  final LocalContactService _localContacts;
  final DiffEngine _diffEngine;
  final ConflictResolver _conflictResolver;

  SyncEngine({
    required DatabaseService db,
    required SecureStorageService secureStorage,
    required LocalContactService localContacts,
  })  : _db = db,
        _secureStorage = secureStorage,
        _localContacts = localContacts,
        _diffEngine = DiffEngine(db),
        _conflictResolver = ConflictResolver();

  /// Run a full sync for an account.
  /// Returns a SyncResult with stats and any conflicts.
  Future<SyncResult> sync(Account account) async {
    final password = await _secureStorage.getPassword(account.id!);
    if (password == null) {
      return SyncResult(status: SyncStatus.failure, errorMessage: 'No stored password for account');
    }

    try {
      final client = CardDavHttpClient(
        serverUrl: account.serverUrl,
        username: account.username,
        password: password,
      );

      final discovery = CardDavDiscovery(client);
      final operations = CardDavOperations(client);

      // 1. Discover addressbook URL
      String addressbookUrl;
      try {
        final principalUrl = await discovery.discoverPrincipalUrl();
        final abHome = await discovery.discoverAddressbookHome(principalUrl);
        final addressbooks = await discovery.discoverAddressbooks(abHome);
        if (addressbooks.isEmpty) {
          return SyncResult(status: SyncStatus.failure, errorMessage: 'No addressbooks found');
        }
        addressbookUrl = addressbooks.first.href;
      } catch (_) {
        // Fallback: use server URL directly as addressbook
        addressbookUrl = account.serverUrl;
      }

      // 2. Try incremental sync first
      List<Contact> remoteContacts;
      final syncToken = await _secureStorage.getSyncToken(account.id!);

      try {
        final syncResult = await operations.syncCollection(addressbookUrl, syncToken: syncToken);
        remoteContacts = syncResult.contacts;
        if (syncResult.syncToken != null) {
          await _secureStorage.saveSyncToken(account.id!, syncResult.syncToken!);
        }
      } on SyncTokenInvalidException {
        // Fall back to full sync
        remoteContacts = await operations.listContacts(addressbookUrl);
        await _secureStorage.deleteSyncToken(account.id!);
      }

      // 3. Get local contacts
      final localContacts = await _localContacts.getAllContacts();

      // 4. Compute diff
      final diffs = await _diffEngine.computeDiff(
        localContacts: localContacts,
        remoteContacts: remoteContacts,
        accountId: account.id!,
      );

      // 5. Process diffs
      int pushed = 0, pulled = 0, deletedLocal = 0, deletedRemote = 0;
      final conflicts = <ConflictItem>[];

      for (final diff in diffs) {
        switch (diff.type) {
          case DiffType.localOnly:
            // Push local to remote
            if (diff.localContact != null) {
              await operations.createContact(addressbookUrl, diff.localContact!);
              pushed++;
            }
            break;

          case DiffType.remoteOnly:
            // Pull remote to local
            if (diff.remoteContact != null) {
              await _localContacts.createContact(diff.remoteContact!);
              pulled++;
            }
            break;

          case DiffType.localDeleted:
            // Delete from remote
            if (diff.remoteContact != null) {
              await operations.deleteContact(diff.remoteContact!);
              deletedRemote++;
            }
            break;

          case DiffType.remoteDeleted:
            // Delete from local
            if (diff.localContact != null && diff.localContact!.uid != null) {
              await _localContacts.deleteContact(diff.localContact!.uid!);
              deletedLocal++;
            }
            break;

          case DiffType.conflict:
            // Record conflict for user resolution
            conflicts.add(ConflictItem(
              uid: diff.uid,
              localContact: diff.localContact!,
              remoteContact: diff.remoteContact!,
            ));
            break;

          case DiffType.identical:
            // Update sync metadata
            final contact = diff.localContact ?? diff.remoteContact;
            if (contact != null) {
              await _db.upsertSyncMeta(
                account.id!,
                diff.uid,
                contact.etag,
                contact.contentHash,
              );
            }
            break;
        }
      }

      // 6. Log the sync
      final status = conflicts.isNotEmpty ? SyncStatus.conflicts : SyncStatus.success;
      await _db.insertSyncLog(SyncLog(
        accountId: account.id!,
        timestamp: DateTime.now(),
        status: status,
        conflictsCount: conflicts.length,
      ).toMap());

      client.dispose();

      return SyncResult(
        status: status,
        pushed: pushed,
        pulled: pulled,
        deletedLocal: deletedLocal,
        deletedRemote: deletedRemote,
        conflicts: conflicts,
      );
    } catch (e) {
      await _db.insertSyncLog(SyncLog(
        accountId: account.id!,
        timestamp: DateTime.now(),
        status: SyncStatus.failure,
        errorMessage: e.toString(),
      ).toMap());

      return SyncResult(
        status: SyncStatus.failure,
        errorMessage: e.toString(),
      );
    }
  }

  /// Apply conflict resolutions after user makes choices.
  Future<void> applyResolutions(
    Account account,
    List<ConflictItem> resolvedConflicts,
  ) async {
    if (!_conflictResolver.allResolved(resolvedConflicts)) {
      throw Exception('Not all conflicts are resolved');
    }

    final password = await _secureStorage.getPassword(account.id!);
    if (password == null) return;

    final client = CardDavHttpClient(
      serverUrl: account.serverUrl,
      username: account.username,
      password: password,
    );
    final operations = CardDavOperations(client);

    for (final conflict in resolvedConflicts) {
      final resolved = _conflictResolver.getChosenContact(conflict);
      if (resolved.source == Source.local) {
        // Push local version to remote
        final contact = resolved.contact as Contact;
        await operations.updateContact(contact);
      } else {
        // Pull remote version to local
        final contact = resolved.contact as Contact;
        if (conflict.localContact.uid != null) {
          await _localContacts.updateContact(contact.copyWith(uid: conflict.localContact.uid));
        } else {
          await _localContacts.createContact(contact);
        }
      }

      // Update sync metadata
      final contact = resolved.contact as Contact;
      await _db.upsertSyncMeta(
        account.id!,
        conflict.uid,
        contact.etag,
        contact.contentHash,
      );
    }

    client.dispose();
  }
}

/// Result of a sync run.
class SyncResult {
  final SyncStatus status;
  final String? errorMessage;
  final int pushed;
  final int pulled;
  final int deletedLocal;
  final int deletedRemote;
  final List<ConflictItem> conflicts;

  const SyncResult({
    required this.status,
    this.errorMessage,
    this.pushed = 0,
    this.pulled = 0,
    this.deletedLocal = 0,
    this.deletedRemote = 0,
    this.conflicts = const [],
  });
}
