import '../../models/contact.dart';
import '../../models/conflict_item.dart';
import '../../models/sync_record.dart';
import '../database_service.dart';

/// Compares local and remote contacts to produce diffs.
class DiffEngine {
  final DatabaseService? _db;

  DiffEngine([this._db]);

  /// Compute the diff between local and remote contacts for an account.
  ///
  /// [localContacts] are from the device address book.
  /// [remoteContacts] are from the CardDAV server.
  /// [accountId] is the CardDAV account ID for looking up sync history.
  Future<List<DiffResult>> computeDiff({
    required List<Contact> localContacts,
    required List<Contact> remoteContacts,
    required int accountId,
  }) async {
    final results = <DiffResult>[];

    // Load previous sync metadata to know what was synced before
    final syncMetaRows = _db != null
        ? await _db!.getSyncMetaForAccount(accountId)
        : <Map<String, dynamic>>[];
    final syncMetaMap = <String, SyncMeta>{};
    for (final row in syncMetaRows) {
      final meta = SyncMeta.fromMap(row);
      syncMetaMap[meta.uid] = meta;
    }

    // Build lookup maps
    final localByUid = <String, Contact>{};
    for (final c in localContacts) {
      if (c.uid != null) localByUid[c.uid!] = c;
    }

    final remoteByUid = <String, Contact>{};
    for (final c in remoteContacts) {
      if (c.uid != null) remoteByUid[c.uid!] = c;
    }

    // All UIDs we need to check
    final allUids = <String>{}
      ..addAll(localByUid.keys)
      ..addAll(remoteByUid.keys)
      ..addAll(syncMetaMap.keys);

    for (final uid in allUids) {
      final local = localByUid[uid];
      final remote = remoteByUid[uid];
      final prevMeta = syncMetaMap[uid];

      final wasSyncedBefore = prevMeta != null;

      if (local != null && remote != null) {
        // Both exist - check if both changed since last sync
        final localChanged = !_hashMatches(local.contentHash, prevMeta?.lastSyncHash);
        final remoteChanged = remote.etag != prevMeta?.etag;

        if (localChanged && remoteChanged) {
          results.add(DiffResult(uid: uid, type: DiffType.conflict, localContact: local, remoteContact: remote));
        } else if (localChanged) {
          // Local changed, remote didn't → push to remote
          results.add(DiffResult(uid: uid, type: DiffType.localOnly, localContact: local, remoteContact: remote));
        } else if (remoteChanged) {
          // Remote changed, local didn't → pull to local
          results.add(DiffResult(uid: uid, type: DiffType.remoteOnly, localContact: local, remoteContact: remote));
        } else {
          results.add(DiffResult(uid: uid, type: DiffType.identical, localContact: local, remoteContact: remote));
        }
      } else if (local != null && remote == null) {
        if (wasSyncedBefore) {
          // Was synced before, remote deleted → delete locally
          results.add(DiffResult(uid: uid, type: DiffType.remoteDeleted, localContact: local));
        } else {
          // New locally, not on remote → push
          results.add(DiffResult(uid: uid, type: DiffType.localOnly, localContact: local));
        }
      } else if (local == null && remote != null) {
        if (wasSyncedBefore) {
          // Was synced before, local deleted → delete from remote
          results.add(DiffResult(uid: uid, type: DiffType.localDeleted, remoteContact: remote));
        } else {
          // New remotely, not local → pull
          results.add(DiffResult(uid: uid, type: DiffType.remoteOnly, remoteContact: remote));
        }
      }
    }

    return results;
  }

  bool _hashMatches(String hash, String? previousHash) {
    if (previousHash == null) return false;
    return hash == previousHash;
  }

  /// Compute field-level diff between two contacts.
  List<FieldDiff> computeFieldDiff(Contact local, Contact remote) {
    return [
      FieldDiff(fieldName: 'displayName', localValue: local.displayName, remoteValue: remote.displayName),
      FieldDiff(fieldName: 'firstName', localValue: local.firstName, remoteValue: remote.firstName),
      FieldDiff(fieldName: 'lastName', localValue: local.lastName, remoteValue: remote.lastName),
      FieldDiff(fieldName: 'organization', localValue: local.organization, remoteValue: remote.organization),
      FieldDiff(fieldName: 'title', localValue: local.title, remoteValue: remote.title),
      FieldDiff(fieldName: 'note', localValue: local.note, remoteValue: remote.note),
      FieldDiff(
        fieldName: 'phones',
        localValue: local.phones.map((p) => '${p.label}: ${p.number}').join(', '),
        remoteValue: remote.phones.map((p) => '${p.label}: ${p.number}').join(', '),
      ),
      FieldDiff(
        fieldName: 'emails',
        localValue: local.emails.map((e) => '${e.label}: ${e.address}').join(', '),
        remoteValue: remote.emails.map((e) => '${e.label}: ${e.address}').join(', '),
      ),
      FieldDiff(
        fieldName: 'birthday',
        localValue: local.birthday?.toIso8601String(),
        remoteValue: remote.birthday?.toIso8601String(),
      ),
    ];
  }
}
