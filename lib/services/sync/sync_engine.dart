import 'dart:convert';

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

      // 2. Fetch the FULL remote contact list. (A sync-token REPORT returns
      // only the delta since the last token; previously that delta was diffed
      // as if it were the full set, so unchanged contacts looked missing and
      // got re-pushed every sync. Diff against the true full state instead.)
      final remoteContacts = await operations.listContacts(addressbookUrl);

      // 3. Get local contacts + the local↔remote uid map.
      final localContacts = await _localContacts.getAllContacts();
      final uidMap = await _db.getUidMapForAccount(account.id!);

      // Cache the remote snapshot for the Contacts/Sync UI.
      await _cacheRemoteContacts(account.id!, remoteContacts);

      // 4. Compute diff using the uid map so pulled contacts (which get a
      // fresh device id) still match their remote counterpart.
      final diffs = await _diffEngine.computeDiff(
        localContacts: localContacts,
        remoteContacts: remoteContacts,
        accountId: account.id!,
        localToRemoteUid: uidMap,
      );

      // 5. Process diffs
      int pushed = 0, pulled = 0, deletedLocal = 0, deletedRemote = 0;
      final conflicts = <ConflictItem>[];

      for (final diff in diffs) {
        switch (diff.type) {
          case DiffType.localOnly:
            // Push local to remote.
            if (diff.localContact != null) {
              final created =
                  await operations.createContact(addressbookUrl, diff.localContact!);
              pushed++;
              // Record linkage + sync state so the next sync treats it as
              // identical instead of re-pushing (the duplicate-spiral fix).
              if (diff.localContact!.uid != null) {
                await _db.upsertUidMap(account.id!, diff.localContact!.uid!, diff.uid);
              }
              await _db.upsertSyncMeta(
                  account.id!, diff.uid, created.etag, diff.localContact!.contentHash);
            }
            break;

          case DiffType.remoteOnly:
            // Pull remote to local.
            if (diff.remoteContact != null) {
              final created = await _localContacts.createContact(diff.remoteContact!);
              pulled++;
              // The new local contact has a fresh device id; map it to the
              // remote uid so it matches next time. Without this, the pull
              // breaks the linkage and the contact is re-pulled + re-pushed
              // every sync (the duplicate spiral).
              if (created.uid != null) {
                await _db.upsertUidMap(account.id!, created.uid!, diff.uid);
              }
              // Anchor sync state on the *created local* hash (not the remote
              // hash): the address book may reformat fields on insert, so the
              // local copy's hash is what future syncs must compare against.
              await _db.upsertSyncMeta(
                  account.id!, diff.uid, diff.remoteContact!.etag, created.contentHash);
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
            // Record conflict for user resolution.
            conflicts.add(ConflictItem(
              uid: diff.uid,
              localContact: diff.localContact!,
              remoteContact: diff.remoteContact!,
            ));
            // Keep the uid linkage even for conflicts.
            if (diff.localContact?.uid != null) {
              await _db.upsertUidMap(account.id!, diff.localContact!.uid!, diff.uid);
            }
            break;

          case DiffType.identical:
            final local = diff.localContact;
            final remote = diff.remoteContact;
            final contact = local ?? remote;
            if (contact != null) {
              await _db.upsertSyncMeta(
                account.id!,
                diff.uid,
                remote?.etag ?? contact.etag,
                contact.contentHash,
              );
            }
            // Keep the uid map in step — covers content-matched pairs from the
            // diff's fallback phase, where the local uid differs from the
            // remote uid and the link needs establishing.
            if (local != null && local.uid != null && local.uid != diff.uid) {
              await _db.upsertUidMap(account.id!, local.uid!, diff.uid);
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
    final discovery = CardDavDiscovery(client);

    // Discover the addressbook URL (needed to re-create contacts).
    String addressbookUrl;
    try {
      final principalUrl = await discovery.discoverPrincipalUrl();
      final abHome = await discovery.discoverAddressbookHome(principalUrl);
      final addressbooks = await discovery.discoverAddressbooks(abHome);
      addressbookUrl =
          addressbooks.isEmpty ? account.serverUrl : addressbooks.first.href;
    } catch (_) {
      addressbookUrl = account.serverUrl;
    }

    for (final conflict in resolvedConflicts) {
      final resolved = _conflictResolver.getChosenContact(conflict);
      if (resolved.source == Source.local) {
        // This server rejects PUT-to-update with 409, so replace the remote
        // contact via delete + create, writing the local field values with the
        // remote uid (the server enforces UID == filename). Fetch a fresh etag
        // for the delete so it isn't rejected; let failures propagate (avoids a
        // silent duplicate if the delete fails).
        final local = resolved.contact as Contact;
        final remote = conflict.remoteContact;
        final freshEtag =
            remote.href != null ? await operations.fetchEtag(remote.href!) : null;
        await operations.deleteContact(remote.copyWith(etag: freshEtag));
        await operations.createContact(addressbookUrl, local.copyWith(uid: remote.uid));
      } else {
        // Pull remote version to the local contact (keep the local id).
        final remote = resolved.contact as Contact;
        if (conflict.localContact.uid != null) {
          await _localContacts.updateContact(remote.copyWith(uid: conflict.localContact.uid));
        } else {
          await _localContacts.createContact(remote);
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

      // Maintain the local↔remote uid linkage so this pair stops re-conflicting.
      final localUid = conflict.localContact.uid;
      if (localUid != null) {
        await _db.upsertUidMap(account.id!, localUid, conflict.uid);
      }

      // Keep the remote cache in step with the resolution.
      await _db.upsertRemoteCache(account.id!, {
        'uid': conflict.uid,
        'etag': contact.etag,
        'content_hash': contact.contentHash,
        'contact_json': jsonEncode(contact.toJson()),
      });
    }

    client.dispose();
  }

  /// Remove exact-duplicate contacts from the remote addressbook. Contacts
  /// with identical content (same contentHash) are grouped; one per group is
  /// kept and the rest are deleted. Returns counts. Used to clean up the
  /// duplicates created by the earlier sync bug.
  Future<DedupResult> dedupRemoteContacts(Account account) async {
    final password = await _secureStorage.getPassword(account.id!);
    if (password == null) {
      return const DedupResult(remoteTotal: 0, duplicatesRemoved: 0, remaining: 0);
    }

    final client = CardDavHttpClient(
      serverUrl: account.serverUrl,
      username: account.username,
      password: password,
    );
    try {
      final discovery = CardDavDiscovery(client);
      final operations = CardDavOperations(client);

      String addressbookUrl;
      try {
        final principalUrl = await discovery.discoverPrincipalUrl();
        final abHome = await discovery.discoverAddressbookHome(principalUrl);
        final addressbooks = await discovery.discoverAddressbooks(abHome);
        addressbookUrl =
            addressbooks.isEmpty ? account.serverUrl : addressbooks.first.href;
      } catch (_) {
        addressbookUrl = account.serverUrl;
      }

      final remote = await operations.listContacts(addressbookUrl);

      // Group by normalized matchKey (tolerates drift); keep one per group,
      // delete the rest.
      final byMatch = <String, List<Contact>>{};
      for (final c in remote) {
        byMatch.putIfAbsent(c.matchKey, () => []).add(c);
      }

      var removed = 0;
      final survivors = <Contact>[];
      for (final group in byMatch.values) {
        survivors.add(group.first);
        for (final dup in group.skip(1)) {
          await operations.deleteContact(dup);
          removed++;
        }
      }

      // Refresh the cache with the deduped set.
      await _cacheRemoteContacts(account.id!, survivors);

      return DedupResult(
        remoteTotal: remote.length,
        duplicatesRemoved: removed,
        remaining: survivors.length,
      );
    } finally {
      client.dispose();
    }
  }

  /// Replace the cached remote snapshot for an account.
  Future<void> _cacheRemoteContacts(
      int accountId, List<Contact> remoteContacts) async {
    final now = DateTime.now().toIso8601String();
    final rows = remoteContacts
        .where((c) => c.uid != null && c.uid!.isNotEmpty)
        .map((c) => {
              'uid': c.uid,
              'etag': c.etag,
              'content_hash': c.contentHash,
              'contact_json': jsonEncode(c.toJson()),
              'updated_at': now,
            })
        .toList();
    await _db.replaceRemoteCacheForAccount(accountId, rows);
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

/// Result of a remote dedup run.
class DedupResult {
  final int remoteTotal;
  final int duplicatesRemoved;
  final int remaining;

  const DedupResult({
    required this.remoteTotal,
    required this.duplicatesRemoved,
    required this.remaining,
  });
}
