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
      return const SyncResult(status: SyncStatus.failure, errorMessage: 'No stored password for account');
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
          return const SyncResult(status: SyncStatus.failure, errorMessage: 'No addressbooks found');
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

      // Counters declared here (not further down) because tombstone processing
      // below increments deletedRemote before the diff loop runs.
      int pushed = 0, pulled = 0, deletedLocal = 0, deletedRemote = 0;

      // 3a. Process tombstones: contacts the user deleted in-app. These are
      // definite deletions — remove from the server (retry on failure), then
      // clean metadata. Failed deletes leave everything intact for next sync.
      final tombRows = await _db.getTombstonesForAccount(account.id!);
      final tombstoneUids = tombRows.map((r) => r['uid'] as String).toSet();
      for (final uid in tombstoneUids.toList()) {
        final idx = remoteContacts.indexWhere((c) => c.uid == uid);
        final remote = idx >= 0 ? remoteContacts[idx] : null;
        if (remote != null && remote.href != null) {
          try {
            await operations.deleteContact(remote);
            deletedRemote++;
          } catch (_) {
            // Server delete failed — leave tombstone + meta for next sync.
            continue;
          }
        }
        // Success or already gone remotely: drop from the diff set + clean up.
        remoteContacts.removeWhere((c) => c.uid == uid);
        await _db.deleteTombstone(account.id!, uid);
        await _db.deleteSyncMeta(account.id!, uid);
        await _db.deleteUidMapForRemote(account.id!, uid);
      }

      // Cache the remote snapshot for the Contacts/Sync UI.
      await _cacheRemoteContacts(account.id!, remoteContacts);

      // 4. Compute diff using the uid map so pulled contacts (which get a
      // fresh device id) still match their remote counterpart.
      final diffs = await _diffEngine.computeDiff(
        localContacts: localContacts,
        remoteContacts: remoteContacts,
        accountId: account.id!,
        localToRemoteUid: uidMap,
        excludeUids: tombstoneUids,
      );

      // 5. Process diffs
      final conflicts = <ConflictItem>[];
      final deletionProposals = <DeletionProposal>[];

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
            // Inferred local deletion — do NOT auto-delete from the server. A
            // partial remote listing must never trigger silent deletion; route
            // to the confirmation queue.
            if (diff.remoteContact != null) {
              deletionProposals.add(DeletionProposal(
                uid: diff.uid,
                side: DeletionSide.localDeleted,
                remoteContact: diff.remoteContact,
              ));
            }
            break;

          case DiffType.remoteDeleted:
            // Inferred remote deletion — same reasoning; confirm before acting.
            if (diff.localContact != null) {
              deletionProposals.add(DeletionProposal(
                uid: diff.uid,
                side: DeletionSide.remoteDeleted,
                localContact: diff.localContact,
              ));
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
        deletionProposals: deletionProposals,
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

  /// Apply the user's choices for inferred deletions (propagate the deletion to
  /// the other side, or restore the contact there). Mirrors [applyResolutions].
  Future<void> applyDeletionResolutions(
    Account account,
    List<DeletionProposal> resolved,
  ) async {
    final password = await _secureStorage.getPassword(account.id!);
    if (password == null) return;

    final client = CardDavHttpClient(
      serverUrl: account.serverUrl,
      username: account.username,
      password: password,
    );
    final operations = CardDavOperations(client);
    final discovery = CardDavDiscovery(client);

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

    for (final p in resolved) {
      if (p.choice == DeletionChoice.unresolved) continue;

      if (p.choice == DeletionChoice.propagate) {
        if (p.side == DeletionSide.localDeleted) {
          // Finish the deletion on the server.
          final remote = p.remoteContact!;
          final freshEtag =
              remote.href != null ? await operations.fetchEtag(remote.href!) : null;
          await operations.deleteContact(remote.copyWith(etag: freshEtag));
          await _db.deleteSyncMeta(account.id!, p.uid);
          await _db.deleteUidMapForRemote(account.id!, p.uid);
        } else {
          // Delete the local copy.
          final localUid = p.localContact!.uid;
          if (localUid != null) {
            await _localContacts.deleteContact(localUid);
            await _db.deleteUidMapForLocal(account.id!, localUid);
          }
          await _db.deleteSyncMeta(account.id!, p.uid);
        }
      } else {
        // Restore: undo the inferred deletion on the missing side.
        if (p.side == DeletionSide.localDeleted) {
          // Pull the remote contact back to the device.
          final remote = p.remoteContact!;
          final created = await _localContacts.createContact(remote);
          if (created.uid != null) {
            await _db.upsertUidMap(account.id!, created.uid!, p.uid);
          }
          await _db.upsertSyncMeta(account.id!, p.uid, remote.etag, created.contentHash);
        } else {
          // Re-push the local contact to the server.
          final local = p.localContact!;
          final created = await operations.createContact(addressbookUrl, local);
          if (local.uid != null) {
            await _db.upsertUidMap(account.id!, local.uid!, created.uid ?? p.uid);
          }
          await _db.upsertSyncMeta(account.id!, p.uid, created.etag, local.contentHash);
        }
      }
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
  final List<DeletionProposal> deletionProposals;

  const SyncResult({
    required this.status,
    this.errorMessage,
    this.pushed = 0,
    this.pulled = 0,
    this.deletedLocal = 0,
    this.deletedRemote = 0,
    this.conflicts = const [],
    this.deletionProposals = const [],
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
