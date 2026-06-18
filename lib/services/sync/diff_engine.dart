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
  /// [localToRemoteUid] maps a local contact id to its remote UID. Contacts
  /// pulled from the server get a fresh device id, so without this map they
  /// could never be matched back to their remote counterpart — which caused the
  /// duplicate-creation spiral.
  /// [excludeUids] remote uids to skip entirely (tombstones — in-app deletions
  /// the sync engine handles separately). Applied on the remote side only: a
  /// tombstoned contact has no local counterpart, so Phase 2 (which iterates
  /// existing locals) can never encounter one.
  Future<List<DiffResult>> computeDiff({
    required List<Contact> localContacts,
    required List<Contact> remoteContacts,
    required int accountId,
    Map<String, String>? localToRemoteUid,
    Set<String>? excludeUids,
  }) async {
    final results = <DiffResult>[];
    final l2r = localToRemoteUid ?? <String, String>{};

    // Load previous sync metadata (keyed by remote uid).
    final syncMetaMap = <String, SyncMeta>{};
    if (_db != null) {
      for (final row in await _db!.getSyncMetaForAccount(accountId)) {
        final meta = SyncMeta.fromMap(row);
        syncMetaMap[meta.uid] = meta;
      }
    }

    // Index local contacts by their *remote* uid. For pushed contacts the
    // remote uid equals the local id (the engine writes it that way); for
    // pulled contacts it comes from the uid map.
    final localByRuid = <String, Contact>{};
    for (final c in localContacts) {
      final cuid = c.uid;
      if (cuid == null || cuid.isEmpty) continue;
      final ruid = l2r[cuid] ?? cuid;
      localByRuid.putIfAbsent(ruid, () => c);
    }

    final remoteByUid = <String, Contact>{};
    for (final c in remoteContacts) {
      if (c.uid != null && c.uid!.isNotEmpty) {
        remoteByUid.putIfAbsent(c.uid!, () => c);
      }
    }

    final matchedRemoteUids = <String>{};

    // Phase 1 — uid-linked pairs.
    for (final ruid in localByRuid.keys.toList()) {
      final remote = remoteByUid[ruid];
      if (remote == null) continue;
      matchedRemoteUids.add(ruid);
      results.add(_classifyPair(ruid, localByRuid[ruid]!, remote, syncMetaMap[ruid]));
    }

    // Phase 2 — normalized match fallback: pair uid-unmatched locals with
    // unmatched remotes that represent the same person (same name + phone
    // digits + emails), tolerating the formatting drift the vCard/address-book
    // round-trip introduces. A matched pair ⇒ identical (no push, no pull),
    // which is what stops the duplicate spiral; the engine records the uid
    // linkage so later syncs match directly.
    final unmatchedRemote = remoteByUid.entries
        .where((e) => !matchedRemoteUids.contains(e.key))
        .toList();
    final remoteUidByMatch = <String, String>{}; // matchKey → remote uid
    for (final e in unmatchedRemote) {
      remoteUidByMatch.putIfAbsent(e.value.matchKey, () => e.key);
    }
    final takenMatch = <String>{};
    for (final entry in localByRuid.entries) {
      if (remoteByUid.containsKey(entry.key)) continue; // phase 1 handled it
      final local = entry.value;
      final matchRuid = remoteUidByMatch[local.matchKey];
      if (matchRuid != null && !takenMatch.contains(local.matchKey)) {
        takenMatch.add(local.matchKey);
        matchedRemoteUids.add(matchRuid);
        results.add(DiffResult(
          uid: matchRuid,
          type: DiffType.identical,
          localContact: local,
          remoteContact: remoteByUid[matchRuid],
        ));
      } else {
        // No remote counterpart by uid or content. If we previously synced this
        // uid, the server deleted it (remoteDeleted) — otherwise it is a
        // genuinely new local contact (localOnly → push).
        final type = syncMetaMap.containsKey(entry.key)
            ? DiffType.remoteDeleted
            : DiffType.localOnly;
        results.add(DiffResult(uid: entry.key, type: type, localContact: local));
      }
    }

    // Phase 3 — remaining remotes with no local counterpart. A remote uid that
    // was previously synced (in sync_meta) but now has no local contact was
    // deleted locally ⇒ localDeleted. Otherwise it is a new remote contact ⇒
    // remoteOnly (pull). Tombstoned uids (excludeUids) are handled by the sync
    // engine and skipped here so they are not also queued as inferred deletions.
    final exclude = excludeUids ?? const <String>{};
    for (final e in remoteByUid.entries) {
      if (matchedRemoteUids.contains(e.key)) continue;
      if (exclude.contains(e.key)) continue;
      final type = syncMetaMap.containsKey(e.key)
          ? DiffType.localDeleted
          : DiffType.remoteOnly;
      results.add(DiffResult(uid: e.key, type: type, remoteContact: e.value));
    }

    return results;
  }

  /// Classify a uid-linked pair. Content equality is the primary "in sync"
  /// signal; sync_meta history only decides direction when content diverged.
  DiffResult _classifyPair(String ruid, Contact local, Contact remote, SyncMeta? prev) {
    if (local.contentHash == remote.contentHash) {
      return DiffResult(uid: ruid, type: DiffType.identical, localContact: local, remoteContact: remote);
    }
    if (prev == null) {
      // Diverged with no history → let the user decide.
      return DiffResult(uid: ruid, type: DiffType.conflict, localContact: local, remoteContact: remote);
    }
    final localChanged = local.contentHash != prev.lastSyncHash;
    final remoteChanged = remote.etag != prev.etag;
    final type = (localChanged && remoteChanged)
        ? DiffType.conflict
        : localChanged
            ? DiffType.localOnly
            : remoteChanged
                ? DiffType.remoteOnly
                : DiffType.identical;
    return DiffResult(uid: ruid, type: type, localContact: local, remoteContact: remote);
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
