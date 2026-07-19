import 'package:flutter_test/flutter_test.dart';
import 'package:easy_contact_sync/models/conflict_item.dart';
import 'package:easy_contact_sync/models/contact.dart';
import 'package:easy_contact_sync/services/database_service.dart';
import 'package:easy_contact_sync/services/sync/diff_engine.dart';

// 1x1 red PNG, base64-encoded — small enough to inline in a content hash.
const _photoBase64 =
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==';

/// A DatabaseService that returns canned sync_meta rows without opening a real
/// DB. DiffEngine only calls getSyncMetaForAccount, so overriding it is enough.
class _FakeDb extends DatabaseService {
  final List<Map<String, dynamic>> meta;
  _FakeDb(this.meta);
  @override
  Future<List<Map<String, dynamic>>> getSyncMetaForAccount(int accountId) async => meta;
}

Contact _contact({String? uid, String name = 'Alice', String phone = '111'}) {
  return Contact(
    uid: uid,
    displayName: name,
    phones: [ContactPhone(number: phone)],
    etag: 'etag-$uid',
    href: uid == null ? null : '/ab/$uid.vcf',
  );
}

Map<String, dynamic> _meta(String uid) => {
      'id': 1,
      'account_id': 1,
      'uid': uid,
      'etag': 'etag-$uid',
      'last_sync_hash': 'some-hash',
      'updated_at': '2026-01-01T00:00:00.000',
    };

void main() {
  test('remote contact previously synced, no local counterpart ⇒ localDeleted', () async {
    final db = _FakeDb([_meta('R1')]);
    final diffs = await DiffEngine(db).computeDiff(
      localContacts: const [],
      remoteContacts: [_contact(uid: 'R1')],
      accountId: 1,
    );
    expect(diffs, contains(predicate<DiffResult>((d) => d.type == DiffType.localDeleted)));
  });

  test('remote contact NOT in sync_meta ⇒ remoteOnly (pull, not a deletion)', () async {
    final db = _FakeDb(const []);
    final diffs = await DiffEngine(db).computeDiff(
      localContacts: const [],
      remoteContacts: [_contact(uid: 'R1')],
      accountId: 1,
    );
    expect(diffs, contains(predicate<DiffResult>((d) => d.type == DiffType.remoteOnly)));
    expect(diffs, isNot(contains(predicate<DiffResult>((d) => d.type == DiffType.localDeleted))));
  });

  test('local contact previously synced, no remote counterpart ⇒ remoteDeleted', () async {
    final db = _FakeDb([_meta('L1')]);
    final diffs = await DiffEngine(db).computeDiff(
      localContacts: [_contact(uid: 'L1')],
      remoteContacts: const [],
      accountId: 1,
    );
    expect(diffs, contains(predicate<DiffResult>((d) => d.type == DiffType.remoteDeleted)));
  });

  test('local contact NOT in sync_meta ⇒ localOnly (push, not a deletion)', () async {
    final db = _FakeDb(const []);
    final diffs = await DiffEngine(db).computeDiff(
      localContacts: [_contact(uid: 'L1')],
      remoteContacts: const [],
      accountId: 1,
    );
    expect(diffs, contains(predicate<DiffResult>((d) => d.type == DiffType.localOnly)));
    expect(diffs, isNot(contains(predicate<DiffResult>((d) => d.type == DiffType.remoteDeleted))));
  });

  test('first sync (empty sync_meta): nothing is flagged as a deletion', () async {
    final db = _FakeDb(const []);
    final diffs = await DiffEngine(db).computeDiff(
      localContacts: [_contact(uid: 'L1')],
      remoteContacts: [_contact(uid: 'R1')],
      accountId: 1,
    );
    final types = diffs.map((d) => d.type).toSet();
    expect(types, isNot(contains(DiffType.localDeleted)));
    expect(types, isNot(contains(DiffType.remoteDeleted)));
  });

  test('tombstoned uid in excludeUids is not flagged localDeleted', () async {
    final db = _FakeDb([_meta('R1')]);
    final diffs = await DiffEngine(db).computeDiff(
      localContacts: const [],
      remoteContacts: [_contact(uid: 'R1')],
      accountId: 1,
      excludeUids: const {'R1'},
    );
    expect(diffs, isNot(contains(predicate<DiffResult>((d) => d.type == DiffType.localDeleted))));
    expect(diffs, isNot(contains(predicate<DiffResult>((d) => d.type == DiffType.remoteOnly))));
  });

  // Regression for the "still no avatar after sync" bug: a contact pulled
  // before the photo fix (#12) has a photo-less local copy. The anchor was
  // recorded from that photo-less copy, and the server etag is stable, so on a
  // re-sync neither side looks "changed" — yet local and remote genuinely
  // differ (remote has the photo). This must NOT be classified `identical` or
  // the photo is never re-written; it must refresh the local copy from remote.
  group('photo / stale-anchor divergence', () {
    Contact photoContact({String? uid, String? photo}) => Contact(
          uid: uid,
          displayName: 'Ada',
          etag: 'etag-R1',
          href: uid == null ? null : '/ab/$uid.vcf',
          photo: photo,
        );

    Map<String, dynamic> anchoredMeta({
      required String uid,
      required String etag,
      required String lastSyncHash,
    }) =>
        {
          'id': 1,
          'account_id': 1,
          'uid': uid,
          'etag': etag,
          'last_sync_hash': lastSyncHash,
          'updated_at': '2026-01-01T00:00:00.000',
        };

    test('stale-anchor photo divergence (neither side changed) => remoteNewer', () async {
      final local = photoContact(uid: 'L1', photo: null);
      final remote = photoContact(uid: 'R1', photo: _photoBase64);
      final db = _FakeDb([anchoredMeta(
        uid: 'R1',
        etag: remote.etag!, // unchanged
        lastSyncHash: local.contentHash, // anchored on the photo-less local copy
      )]);
      final diffs = await DiffEngine(db).computeDiff(
        localContacts: [local],
        remoteContacts: [remote],
        accountId: 1,
        localToRemoteUid: const {'L1': 'R1'},
      );
      // Sanity: contents really do differ.
      expect(local.contentHash, isNot(equals(remote.contentHash)));
      expect(
          diffs, contains(predicate<DiffResult>((d) => d.type == DiffType.remoteNewer)));
      expect(diffs,
          isNot(contains(predicate<DiffResult>((d) => d.type == DiffType.identical))));
    });

    test('genuine remote edit (remote changed, local untouched) => remoteNewer', () async {
      final local = photoContact(uid: 'L1', photo: null);
      final remote = photoContact(uid: 'R1', photo: _photoBase64);
      final db = _FakeDb([anchoredMeta(
        uid: 'R1',
        etag: 'etag-OLD', // remote etag moved since last sync
        lastSyncHash: local.contentHash,
      )]);
      final diffs = await DiffEngine(db).computeDiff(
        localContacts: [local],
        remoteContacts: [remote],
        accountId: 1,
        localToRemoteUid: const {'L1': 'R1'},
      );
      expect(
          diffs, contains(predicate<DiffResult>((d) => d.type == DiffType.remoteNewer)));
    });

    test('user edited local (local changed, remote unchanged) => localOnly, not remoteNewer',
        () async {
      final local = photoContact(uid: 'L1', photo: null);
      final remote = photoContact(uid: 'R1', photo: _photoBase64);
      final db = _FakeDb([anchoredMeta(
        uid: 'R1',
        etag: remote.etag!, // remote unchanged
        lastSyncHash: 'something-else', // local drifted from its anchor
      )]);
      final diffs = await DiffEngine(db).computeDiff(
        localContacts: [local],
        remoteContacts: [remote],
        accountId: 1,
        localToRemoteUid: const {'L1': 'R1'},
      );
      expect(
          diffs, contains(predicate<DiffResult>((d) => d.type == DiffType.localOnly)));
      expect(diffs,
          isNot(contains(predicate<DiffResult>((d) => d.type == DiffType.remoteNewer))));
    });

    test('both sides changed => conflict (remoteNewer never clobbers a local edit)', () async {
      final local = photoContact(uid: 'L1', photo: null);
      final remote = photoContact(uid: 'R1', photo: _photoBase64);
      final db = _FakeDb([anchoredMeta(
        uid: 'R1',
        etag: 'etag-OLD',
        lastSyncHash: 'something-else',
      )]);
      final diffs = await DiffEngine(db).computeDiff(
        localContacts: [local],
        remoteContacts: [remote],
        accountId: 1,
        localToRemoteUid: const {'L1': 'R1'},
      );
      expect(diffs, contains(predicate<DiffResult>((d) => d.type == DiffType.conflict)));
      expect(diffs,
          isNot(contains(predicate<DiffResult>((d) => d.type == DiffType.remoteNewer))));
    });
  });
}
