import 'package:flutter_test/flutter_test.dart';
import 'package:easy_contact_sync/models/conflict_item.dart';
import 'package:easy_contact_sync/models/contact.dart';
import 'package:easy_contact_sync/services/database_service.dart';
import 'package:easy_contact_sync/services/sync/diff_engine.dart';

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
}
