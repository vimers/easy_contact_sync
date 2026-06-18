# Contact Deletion Sync Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make contact deletions propagate (deleted contacts stop coming back) and add an in-app delete action.

**Architecture:** Distinguish *known* deletions (in-app delete → a tombstone row, propagated reliably on next sync) from *inferred* deletions (deleted outside the app, or deleted on the server → detected via `sync_meta` history and routed through a confirmation queue, never auto-deleted, because a partial `listContacts` response must not silently destroy data). The diff engine already loads `sync_meta` history; it will now emit the previously-dead `localDeleted`/`remoteDeleted` types.

**Tech Stack:** Flutter, flutter_riverpod, sqflite (+ sqflite_common_ffi on desktop), flutter_contacts, flutter_test.

**Spec:** `docs/superpowers/specs/2026-06-18-contact-deletion-sync-design.md`

**Testing strategy:** `DiffEngine` is pure Dart and is the logic risk, so it gets real TDD unit tests (Task 3). `DatabaseService` is thin CRUD over SQL and is not currently injectable (lazy file-backed DB); refactoring it is out of scope, so its new methods are verified via `flutter analyze` + the DiffEngine tests exercising the same contract + manual on-device verification (Task 9). Sync-engine orchestration and UI are verified via `flutter analyze`, the full `flutter test` suite staying green, a release build, and the manual scenarios in Task 9. Match existing style: single quotes, `const` constructors, declared return types, no `print`.

---

## File Structure

- `lib/models/conflict_item.dart` — add `DeletionSide`, `DeletionProposal`, `DeletionChoice` (alongside `DiffType`).
- `lib/services/database_service.dart` — bump to v5; add `deleted_uids` table + migration + `insertTombstone` / `getTombstonesForAccount` / `deleteTombstone` / `deleteUidMapForRemote`.
- `lib/services/sync/diff_engine.dart` — `computeDiff` gains `excludeUids`; emits `localDeleted` / `remoteDeleted` using `syncMetaMap`.
- `lib/services/sync/sync_engine.dart` — tombstone processing before diff; collect inferred deletions as `DeletionProposal` (no execution); new `applyDeletionResolutions`.
- `lib/providers/sync_provider.dart` — `SyncResult.deletionProposals` plumbing; `resolveDeletions`; `deleteLocalContact`.
- `lib/providers/contact_sync_status_provider.dart` — `pendingDeletionsProvider`.
- `lib/pages/contact_detail_page.dart` — accept `DisplayContact`; delete AppBar action.
- `lib/pages/contacts_page.dart` — swipe-to-delete; pass `DisplayContact` to detail page.
- `lib/pages/deletion_review_page.dart` — new, mirrors `ConflictPage`.
- `lib/pages/sync_status_page.dart` — "Review N deletions" entry.
- `test/services/sync/diff_engine_test.dart` — new TDD unit tests.

---

### Task 1: DeletionProposal model

**Files:**
- Modify: `lib/models/conflict_item.dart`

- [ ] **Step 1: Add the model**

Append to `lib/models/conflict_item.dart` (after the `FieldDiff` class):

```dart
/// Which side a detected deletion happened on (the side that is now missing).
enum DeletionSide { localDeleted, remoteDeleted }

/// User's choice for a deletion detected by inference (not a tombstone).
enum DeletionChoice { unresolved, propagate, restore }

/// A deletion inferred from sync history (deleted outside the app, or deleted
/// on the server). Surfaced for confirmation — never auto-applied, because a
/// partial remote listing must not trigger silent data deletion.
class DeletionProposal {
  final String uid;
  final DeletionSide side;
  final Contact? localContact; // present for remoteDeleted
  final Contact? remoteContact; // present for localDeleted
  DeletionChoice choice;

  DeletionProposal({
    required this.uid,
    required this.side,
    this.localContact,
    this.remoteContact,
    this.choice = DeletionChoice.unresolved,
  });
}
```

- [ ] **Step 2: Verify it analyzes**

Run: `flutter analyze lib/models/conflict_item.dart`
Expected: "No issues found"

- [ ] **Step 3: Commit**

```bash
git add lib/models/conflict_item.dart
git commit -m "feat: add DeletionProposal model for inferred-deletion review"
```

---

### Task 2: Tombstone table + DB methods

**Files:**
- Modify: `lib/services/database_service.dart`

- [ ] **Step 1: Bump DB version**

In `lib/services/database_service.dart`, change:

```dart
  static const _dbVersion = 4;
```

to:

```dart
  static const _dbVersion = 5;
```

- [ ] **Step 2: Create the table on fresh installs**

In `_onCreate`, after the `await _createContactUidMapTable(db);` line, add:

```dart
    await _createDeletedUidsTable(db);
```

- [ ] **Step 3: Add the migration**

In `_onUpgrade`, after the `if (oldVersion < 4) { ... }` block, add:

```dart
    if (oldVersion < 5) {
      await _createDeletedUidsTable(db);
    }
```

- [ ] **Step 4: Add the DDL method**

Add this method (next to `_createContactUidMapTable`):

```dart
  /// Tombstones: remote uids the user deleted in-app. The sync engine consumes
  /// (and removes) these to propagate the deletion to the server, then cleans
  /// the related sync_meta / uid_map rows.
  Future<void> _createDeletedUidsTable(Database db) async {
    await db.execute('''
      CREATE TABLE deleted_uids (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        account_id INTEGER NOT NULL,
        uid TEXT NOT NULL,
        deleted_at TEXT NOT NULL,
        UNIQUE(account_id, uid)
      )
    ''');
  }
```

- [ ] **Step 5: Add CRUD methods**

Add to the "Contact UID Map" section:

```dart
  // ── Tombstones (in-app deletions pending server propagation) ──

  Future<void> insertTombstone(int accountId, String uid) async {
    final db = await database;
    await db.insert(
      'deleted_uids',
      {
        'account_id': accountId,
        'uid': uid,
        'deleted_at': DateTime.now().toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<Map<String, dynamic>>> getTombstonesForAccount(int accountId) async {
    final db = await database;
    return db.query('deleted_uids',
        where: 'account_id = ?', whereArgs: [accountId]);
  }

  Future<void> deleteTombstone(int accountId, String uid) async {
    final db = await database;
    await db.delete('deleted_uids',
        where: 'account_id = ? AND uid = ?', whereArgs: [accountId, uid]);
  }

  /// Remove the uid_map row for a remote uid (used when the local side is
  /// already gone and only the remote uid is known). Mirrors
  /// [deleteUidMapForLocal].
  Future<void> deleteUidMapForRemote(int accountId, String remoteUid) async {
    final db = await database;
    await db.delete('contact_uid_map',
        where: 'account_id = ? AND remote_uid = ?',
        whereArgs: [accountId, remoteUid]);
  }
```

- [ ] **Step 6: Verify it analyzes**

Run: `flutter analyze lib/services/database_service.dart`
Expected: "No issues found"

- [ ] **Step 7: Commit**

```bash
git add lib/services/database_service.dart
git commit -m "feat: tombstone table + DB methods for deletion propagation"
```

---

### Task 3: DiffEngine — detect inferred deletions (TDD)

This is the core logic fix. Write failing tests first, then implement.

**Files:**
- Create: `test/services/sync/diff_engine_test.dart`
- Modify: `lib/services/sync/diff_engine.dart`

- [ ] **Step 1: Write the failing tests**

Create `test/services/sync/diff_engine_test.dart`:

```dart
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
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `flutter test test/services/sync/diff_engine_test.dart`
Expected: FAIL — `localDeleted`/`remoteDeleted` are never emitted; the `excludeUids` parameter does not exist (compile error). This confirms the tests target the unfixed behavior.

- [ ] **Step 3: Add `excludeUids` to the signature**

In `lib/services/sync/diff_engine.dart`, change the `computeDiff` signature from:

```dart
  Future<List<DiffResult>> computeDiff({
    required List<Contact> localContacts,
    required List<Contact> remoteContacts,
    required int accountId,
    Map<String, String>? localToRemoteUid,
  }) async {
```

to:

```dart
  Future<List<DiffResult>> computeDiff({
    required List<Contact> localContacts,
    required List<Contact> remoteContacts,
    required int accountId,
    Map<String, String>? localToRemoteUid,
    Set<String>? excludeUids,
  }) async {
```

- [ ] **Step 4: Classify missing-remote locals as remoteDeleted**

In Phase 2's `else` branch, replace:

```dart
      } else {
        // Genuinely local-only → push.
        results.add(DiffResult(uid: entry.key, type: DiffType.localOnly, localContact: local));
      }
```

with:

```dart
      } else {
        // No remote counterpart by uid or content. If we previously synced this
        // uid, the server deleted it (remoteDeleted) — otherwise it is a
        // genuinely new local contact (localOnly → push).
        final type = syncMetaMap.containsKey(entry.key)
            ? DiffType.remoteDeleted
            : DiffType.localOnly;
        results.add(DiffResult(uid: entry.key, type: type, localContact: local));
      }
```

- [ ] **Step 5: Classify missing-local remotes as localDeleted**

Replace Phase 3:

```dart
    // Phase 3 — remaining remotes with no local counterpart → pull.
    for (final e in remoteByUid.entries) {
      if (!matchedRemoteUids.contains(e.key)) {
        results.add(DiffResult(uid: e.key, type: DiffType.remoteOnly, remoteContact: e.value));
      }
    }
```

with:

```dart
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
```

- [ ] **Step 6: Run tests to verify they pass**

Run: `flutter test test/services/sync/diff_engine_test.dart`
Expected: PASS — all 6 tests green.

- [ ] **Step 7: Run the full suite**

Run: `flutter test`
Expected: all tests pass (existing placeholder + new diff tests).

- [ ] **Step 8: Commit**

```bash
git add test/services/sync/diff_engine_test.dart lib/services/sync/diff_engine.dart
git commit -m "fix: diff engine detects inferred deletions via sync_meta history"
```

---

### Task 4: SyncEngine — tombstones + collect proposals + applyDeletionResolutions

**Files:**
- Modify: `lib/services/sync/sync_engine.dart`

- [ ] **Step 1: Import the model**

At the top of `lib/services/sync/sync_engine.dart`, ensure the conflict_item import is present (it is already imported transitively; add explicitly):

```dart
import '../../models/conflict_item.dart';
```

(Check the existing imports first — add only if missing.)

- [ ] **Step 2: Add tombstone processing + excludeUids in `sync()`**

In `sync()`, find the block:

```dart
      // 3. Get local contacts + the local↔remote uid map.
      final localContacts = await _localContacts.getAllContacts();
      final uidMap = await _db.getUidMapForAccount(account.id!);

      // Cache the remote snapshot for the Contacts/Sync UI.
      await _cacheRemoteContacts(account.id!, remoteContacts);
```

Replace it with:

```dart
      // 3. Get local contacts + the local↔remote uid map.
      final localContacts = await _localContacts.getAllContacts();
      final uidMap = await _db.getUidMapForAccount(account.id!);

      // Counters (declared here because tombstone processing below already
      // increments deletedRemote; the original declaration further down must be
      // removed — see Step 4).
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
```

- [ ] **Step 2b: Remove the now-duplicate counter declaration**

The original line just before the diff loop now collides with the declaration added in Step 2. Delete this line:

```dart
      int pushed = 0, pulled = 0, deletedLocal = 0, deletedRemote = 0;
```

(Leave the `final conflicts = <ConflictItem>[];` line that followed it in place — Step 4 adds `deletionProposals` next to it.)

- [ ] **Step 3: Pass `excludeUids` to computeDiff**

Change the diff call from:

```dart
      final diffs = await _diffEngine.computeDiff(
        localContacts: localContacts,
        remoteContacts: remoteContacts,
        accountId: account.id!,
        localToRemoteUid: uidMap,
      );
```

to:

```dart
      final diffs = await _diffEngine.computeDiff(
        localContacts: localContacts,
        remoteContacts: remoteContacts,
        accountId: account.id!,
        localToRemoteUid: uidMap,
        excludeUids: tombstoneUids,
      );
```

- [ ] **Step 4: Collect inferred deletions instead of executing them**

Just before the `for (final diff in diffs)` loop, add:

```dart
      final deletionProposals = <DeletionProposal>[];
```

Replace the two deletion cases:

```dart
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
```

with:

```dart
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
```

- [ ] **Step 5: Return proposals in SyncResult**

Change the `return SyncResult(...)` at the end of the `try` block from:

```dart
      return SyncResult(
        status: status,
        pushed: pushed,
        pulled: pulled,
        deletedLocal: deletedLocal,
        deletedRemote: deletedRemote,
        conflicts: conflicts,
      );
```

to:

```dart
      return SyncResult(
        status: status,
        pushed: pushed,
        pulled: pulled,
        deletedLocal: deletedLocal,
        deletedRemote: deletedRemote,
        conflicts: conflicts,
        deletionProposals: deletionProposals,
      );
```

- [ ] **Step 6: Add `applyDeletionResolutions`**

Add this method to the `SyncEngine` class (after `applyResolutions`):

```dart
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
```

- [ ] **Step 7: Verify it analyzes**

Run: `flutter analyze lib/services/sync/sync_engine.dart`
Expected: "No issues found"

- [ ] **Step 8: Commit**

```bash
git add lib/services/sync/sync_engine.dart
git commit -m "feat: sync engine processes tombstones + routes inferred deletions to review"
```

---

### Task 5: SyncResult field + SyncNotifier methods

**Files:**
- Modify: `lib/services/sync/sync_engine.dart` (SyncResult class)
- Modify: `lib/providers/sync_provider.dart`

- [ ] **Step 1: Add `deletionProposals` to SyncResult**

In `lib/services/sync/sync_engine.dart`, in the `SyncResult` class, add a field and constructor param. Change:

```dart
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
```

to:

```dart
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
```

- [ ] **Step 2: Aggregate proposals in `syncAll`**

In `lib/providers/sync_provider.dart`, in `syncAll`, change the accumulation block from:

```dart
      final allConflicts = <ConflictItem>[];
      SyncResult? lastResult;
      int totalPushed = 0, totalPulled = 0, totalDeletedLocal = 0, totalDeletedRemote = 0;

      for (final account in accounts) {
        state = state.copyWith(statusMessage: 'Syncing ${account.username}...');
        final result = await _syncEngine.sync(account);
        lastResult = result;
        allConflicts.addAll(result.conflicts);
        totalPushed += result.pushed;
        totalPulled += result.pulled;
        totalDeletedLocal += result.deletedLocal;
        totalDeletedRemote += result.deletedRemote;
      }
```

to:

```dart
      final allConflicts = <ConflictItem>[];
      final allDeletionProposals = <DeletionProposal>[];
      SyncResult? lastResult;
      int totalPushed = 0, totalPulled = 0, totalDeletedLocal = 0, totalDeletedRemote = 0;

      for (final account in accounts) {
        state = state.copyWith(statusMessage: 'Syncing ${account.username}...');
        final result = await _syncEngine.sync(account);
        lastResult = result;
        allConflicts.addAll(result.conflicts);
        allDeletionProposals.addAll(result.deletionProposals);
        totalPushed += result.pushed;
        totalPulled += result.pulled;
        totalDeletedLocal += result.deletedLocal;
        totalDeletedRemote += result.deletedRemote;
      }
```

Then change the `summaryResult` construction from:

```dart
      final summaryResult = SyncResult(
        status: allConflicts.isNotEmpty ? SyncStatus.conflicts : (lastResult?.status ?? SyncStatus.success),
        pushed: totalPushed,
        pulled: totalPulled,
        deletedLocal: totalDeletedLocal,
        deletedRemote: totalDeletedRemote,
        conflicts: allConflicts,
        errorMessage: lastResult?.errorMessage,
      );
```

to:

```dart
      final summaryResult = SyncResult(
        status: allConflicts.isNotEmpty ? SyncStatus.conflicts : (lastResult?.status ?? SyncStatus.success),
        pushed: totalPushed,
        pulled: totalPulled,
        deletedLocal: totalDeletedLocal,
        deletedRemote: totalDeletedRemote,
        conflicts: allConflicts,
        deletionProposals: allDeletionProposals,
        errorMessage: lastResult?.errorMessage,
      );
```

- [ ] **Step 3: Add `resolveDeletions`**

In `SyncNotifier`, after `resolveConflicts`, add:

```dart
  /// Apply the user's choices for inferred deletions, then refresh.
  Future<void> resolveDeletions(Account account, List<DeletionProposal> proposals) async {
    state = state.copyWith(isSyncing: true, statusMessage: 'Applying deletions...');
    try {
      await _syncEngine.applyDeletionResolutions(account, proposals);
      state = state.copyWith(isSyncing: false, statusMessage: 'Deletions applied');
      _ref.invalidate(contactsProvider);
      _ref.read(remoteCacheVersionProvider.notifier).state++;
    } catch (e, st) {
      ErrorLoggerService.instance.log(source: 'sync', error: e, stackTrace: st);
      state = state.copyWith(isSyncing: false, statusMessage: 'Delete failed: $e');
    }
  }
```

- [ ] **Step 4: Add `deleteLocalContact`**

In `SyncNotifier`, after `resolveDeletions`, add:

```dart
  /// Delete a contact from the device and record a tombstone so the next sync
  /// removes it from the server too. If the contact was never synced (no
  /// uid_map entry) there is nothing to propagate — just delete locally.
  Future<void> deleteLocalContact({required int accountId, required String localUid}) async {
    final localService = _ref.read(localContactServiceProvider);
    final db = _ref.read(databaseServiceProvider);
    final uidMap = await db.getUidMapForAccount(accountId);
    final remoteUid = uidMap[localUid];
    await localService.deleteContact(localUid);
    if (remoteUid != null) {
      await db.insertTombstone(accountId, remoteUid);
    }
    _ref.invalidate(contactsProvider);
    _ref.read(remoteCacheVersionProvider.notifier).state++;
  }
```

- [ ] **Step 5: Verify it analyzes**

Run: `flutter analyze lib/providers/sync_provider.dart lib/services/sync/sync_engine.dart`
Expected: "No issues found"

- [ ] **Step 6: Commit**

```bash
git add lib/providers/sync_provider.dart lib/services/sync/sync_engine.dart
git commit -m "feat: SyncResult carries deletion proposals; resolveDeletions + deleteLocalContact"
```

---

### Task 6: pendingDeletionsProvider

**Files:**
- Modify: `lib/providers/contact_sync_status_provider.dart`

- [ ] **Step 1: Add the provider**

At the end of `lib/providers/contact_sync_status_provider.dart`, add:

```dart
/// Inferred deletions detected from the current diff (deleted outside the app,
/// or deleted on the server). The single source of truth for the deletion-review
/// UI. Tombstoned uids are excluded so in-app deletes aren't double-listed.
/// Confirming a proposal cleans sync_meta, so on recompute it drops out.
final pendingDeletionsProvider = FutureProvider<List<DeletionProposal>>((ref) async {
  ref.watch(remoteCacheVersionProvider);
  final db = ref.watch(databaseServiceProvider);
  final localService = ref.watch(localContactServiceProvider);
  final diffEngine = DiffEngine(db);

  final accountRows = await db.getAllAccounts();
  if (accountRows.isEmpty) return const [];

  final accountId = accountRows.first['id'] as int;
  final local = await localService.getAllContacts();

  final remote = <Contact>[];
  for (final row in await db.getRemoteCacheForAccount(accountId)) {
    final json = row['contact_json'] as String?;
    if (json == null) continue;
    try {
      remote.add(Contact.fromJson(jsonDecode(json) as Map<String, dynamic>));
    } catch (_) {
      // Skip unparseable cache rows.
    }
  }

  final uidMap = await db.getUidMapForAccount(accountId);
  final tombUids = (await db.getTombstonesForAccount(accountId))
      .map((r) => r['uid'] as String)
      .toSet();

  final diffs = await diffEngine.computeDiff(
    localContacts: local,
    remoteContacts: remote,
    accountId: accountId,
    localToRemoteUid: uidMap,
    excludeUids: tombUids,
  );

  final proposals = <DeletionProposal>[];
  for (final d in diffs) {
    if (d.type == DiffType.localDeleted && d.remoteContact != null) {
      proposals.add(DeletionProposal(
        uid: d.uid,
        side: DeletionSide.localDeleted,
        remoteContact: d.remoteContact,
      ));
    } else if (d.type == DiffType.remoteDeleted && d.localContact != null) {
      proposals.add(DeletionProposal(
        uid: d.uid,
        side: DeletionSide.remoteDeleted,
        localContact: d.localContact,
      ));
    }
  }
  return proposals;
});
```

- [ ] **Step 2: Verify it analyzes**

Run: `flutter analyze lib/providers/contact_sync_status_provider.dart`
Expected: "No issues found"

- [ ] **Step 3: Commit**

```bash
git add lib/providers/contact_sync_status_provider.dart
git commit -m "feat: pendingDeletionsProvider for inferred-deletion review"
```

---

### Task 7: In-app delete (detail page button + list swipe)

**Files:**
- Modify: `lib/pages/contact_detail_page.dart`
- Modify: `lib/pages/contacts_page.dart`

- [ ] **Step 1: Make ContactDetailPage accept a DisplayContact**

Replace the entire contents of `lib/pages/contact_detail_page.dart` with:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/contact.dart';
import '../providers/contact_sync_status_provider.dart';
import '../providers/contacts_provider.dart';
import '../providers/accounts_provider.dart';
import '../providers/sync_provider.dart';

/// Detail page showing all fields of a single contact, with a delete action.
/// Delete is offered only when a local copy exists; deleting records a tombstone
/// so the next sync removes the contact from the server too.
class ContactDetailPage extends ConsumerWidget {
  final DisplayContact display;

  const ContactDetailPage({super.key, required this.display});

  Contact get contact => display.localContact ?? display.remoteContact!;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final canDelete = display.localContact?.uid != null;

    return Scaffold(
      appBar: AppBar(
        title: Text(contact.bestName),
        actions: [
          if (canDelete)
            IconButton(
              icon: const Icon(Icons.delete_outline),
              tooltip: 'Delete',
              onPressed: () => _confirmDelete(context, ref),
            ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Column(
                children: [
                  CircleAvatar(
                    radius: 48,
                    backgroundColor: theme.colorScheme.primaryContainer,
                    foregroundColor: theme.colorScheme.onPrimaryContainer,
                    child: Text(
                      contact.bestName.isNotEmpty ? contact.bestName[0].toUpperCase() : '?',
                      style: const TextStyle(fontSize: 32, fontWeight: FontWeight.bold),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(contact.bestName, style: theme.textTheme.headlineSmall),
                  if (contact.organization != null) ...[
                    const SizedBox(height: 4),
                    Text(contact.organization!, style: theme.textTheme.bodyMedium),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 24),
            if (contact.phones.isNotEmpty) ...[
              _sectionTitle(context, 'Phone'),
              ...contact.phones.map((p) => _infoRow(context, p.label, p.number, Icons.phone)),
            ],
            if (contact.emails.isNotEmpty) ...[
              _sectionTitle(context, 'Email'),
              ...contact.emails.map((e) => _infoRow(context, e.label, e.address, Icons.email)),
            ],
            if (contact.title != null) ...[
              _sectionTitle(context, 'Title'),
              _infoRow(context, '', contact.title!, Icons.badge),
            ],
            if (contact.note != null) ...[
              _sectionTitle(context, 'Note'),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text(contact.note!),
              ),
            ],
            if (contact.birthday != null) ...[
              _sectionTitle(context, 'Birthday'),
              _infoRow(context, '', _formatDate(contact.birthday!), Icons.cake),
            ],
            if (contact.addresses.isNotEmpty) ...[
              _sectionTitle(context, 'Address'),
              ...contact.addresses.map((a) => _infoRow(
                    context,
                    a.label,
                    [a.street, a.city, a.region, a.postalCode, a.country]
                        .where((s) => s != null && s.isNotEmpty)
                        .join(', '),
                    Icons.location_on,
                  )),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref) async {
    final localUid = display.localContact!.uid;
    if (localUid == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete contact?'),
        content: const Text(
          'This removes the contact from your phone. It will also be removed '
          'from the server on the next sync.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    final accounts = await ref.read(accountsProvider.future);
    if (accounts.isEmpty) {
      await ref.read(localContactServiceProvider).deleteContact(localUid);
    } else {
      await ref.read(syncNotifierProvider.notifier).deleteLocalContact(
            accountId: accounts.first.id!,
            localUid: localUid,
          );
    }

    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Deleted. Will be removed from the server on next sync.')),
    );
    Navigator.of(context).pop();
  }

  Widget _sectionTitle(BuildContext context, String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Text(
        title,
        style: Theme.of(context).textTheme.titleSmall?.copyWith(
              color: Theme.of(context).colorScheme.primary,
              fontWeight: FontWeight.bold,
            ),
      ),
    );
  }

  Widget _infoRow(BuildContext context, String label, String value, IconData icon) {
    return ListTile(
      leading: Icon(icon, color: Theme.of(context).colorScheme.primary),
      title: Text(value),
      subtitle: label.isNotEmpty ? Text(label) : null,
    );
  }

  String _formatDate(DateTime date) {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }
}
```

- [ ] **Step 2: Pass DisplayContact from ContactsPage + add swipe-to-delete**

In `lib/pages/contacts_page.dart`:

2a. Add imports at the top (after the existing imports):

```dart
import '../providers/accounts_provider.dart';
import '../providers/sync_provider.dart';
```

2b. In the `itemBuilder`, wrap `ContactListItem` in a `Dismissible`. Replace:

```dart
                    final dc = items[index];
                    return ContactListItem(
                      contact: dc.contact,
                      status: dc.status,
                      onTap: () => _onTap(dc),
                      onStatusTap: dc.status == ContactSyncStatus.differing
                          ? () => _openResolve(dc)
                          : null,
                    );
```

with:

```dart
                    final dc = items[index];
                    final canDelete = dc.localContact?.uid != null;
                    return Dismissible(
                      key: ValueKey('contact-${dc.uid}-${dc.contact.bestName}'),
                      direction: canDelete
                          ? DismissDirection.endToStart
                          : DismissDirection.none,
                      background: Container(
                        color: Colors.red,
                        alignment: Alignment.centerRight,
                        padding: const EdgeInsets.symmetric(horizontal: 24),
                        child: const Icon(Icons.delete, color: Colors.white),
                      ),
                      confirmDismiss: canDelete
                          ? (_) => _confirmDelete(dc)
                          : null,
                      child: ContactListItem(
                        contact: dc.contact,
                        status: dc.status,
                        onTap: () => _onTap(dc),
                        onStatusTap: dc.status == ContactSyncStatus.differing
                            ? () => _openResolve(dc)
                            : null,
                      ),
                    );
```

2c. Change `_onTap` to pass the `DisplayContact`:

```dart
  void _onTap(DisplayContact dc) {
    if (dc.status == ContactSyncStatus.differing) {
      _openResolve(dc);
      return;
    }
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ContactDetailPage(display: dc),
      ),
    );
  }
```

2d. Add the delete-confirm helper methods to `_ContactsPageState` (after `_openResolve`):

```dart
  Future<bool> _confirmDelete(DisplayContact dc) async {
    final localUid = dc.localContact!.uid;
    if (localUid == null) return false;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete contact?'),
        content: const Text(
          'This removes the contact from your phone. It will also be removed '
          'from the server on the next sync.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return false;

    final accounts = await ref.read(accountsProvider.future);
    if (accounts.isEmpty) {
      await ref.read(localContactServiceProvider).deleteContact(localUid);
    } else {
      await ref.read(syncNotifierProvider.notifier).deleteLocalContact(
            accountId: accounts.first.id!,
            localUid: localUid,
          );
    }

    if (!mounted) return false;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Deleted. Will be removed from the server on next sync.')),
    );
    return true;
  }
```

- [ ] **Step 3: Verify it analyzes**

Run: `flutter analyze lib/pages/contact_detail_page.dart lib/pages/contacts_page.dart`
Expected: "No issues found"

- [ ] **Step 4: Run the full suite**

Run: `flutter test`
Expected: all tests pass.

- [ ] **Step 5: Commit**

```bash
git add lib/pages/contact_detail_page.dart lib/pages/contacts_page.dart
git commit -m "feat: in-app delete (detail page button + list swipe) with tombstone"
```

---

### Task 8: Deletion review page + Sync page entry

**Files:**
- Create: `lib/pages/deletion_review_page.dart`
- Modify: `lib/pages/sync_status_page.dart`

- [ ] **Step 1: Create the review page**

Create `lib/pages/deletion_review_page.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/conflict_item.dart';
import '../models/contact.dart';
import '../providers/accounts_provider.dart';
import '../providers/sync_provider.dart';

/// Review inferred deletions (deleted outside the app, or on the server) and
/// choose per item: propagate the deletion to the other side, or restore it.
/// Mirrors ConflictPage.
class DeletionReviewPage extends ConsumerStatefulWidget {
  final List<DeletionProposal> proposals;

  const DeletionReviewPage({super.key, required this.proposals});

  @override
  ConsumerState<DeletionReviewPage> createState() => _DeletionReviewPageState();
}

class _DeletionReviewPageState extends ConsumerState<DeletionReviewPage> {
  late final List<DeletionProposal> _proposals;

  @override
  void initState() {
    super.initState();
    _proposals = widget.proposals;
  }

  @override
  Widget build(BuildContext context) {
    final allDecided = _proposals
        .every((p) => p.choice != DeletionChoice.unresolved);

    return Scaffold(
      appBar: AppBar(title: Text('Pending deletions (${_proposals.length})')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _setAll(DeletionChoice.propagate),
                    icon: const Icon(Icons.delete_outline),
                    label: const Text('Delete All'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _setAll(DeletionChoice.restore),
                    icon: const Icon(Icons.restore),
                    label: const Text('Restore All'),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView.builder(
              itemCount: _proposals.length,
              itemBuilder: (context, index) => _ProposalCard(
                proposal: _proposals[index],
                onChoose: (choice) => setState(() => _proposals[index].choice = choice),
              ),
            ),
          ),
          if (allDecided)
            Padding(
              padding: const EdgeInsets.all(16),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _apply,
                  icon: const Icon(Icons.check),
                  label: const Text('Confirm'),
                ),
              ),
            ),
        ],
      ),
    );
  }

  void _setAll(DeletionChoice choice) {
    setState(() {
      for (final p in _proposals) {
        p.choice = choice;
      }
    });
  }

  Future<void> _apply() async {
    final accountsAsync = ref.read(accountsProvider);
    await accountsAsync.when(
      data: (accounts) async {
        if (accounts.isEmpty) return;
        for (final account in accounts) {
          await ref.read(syncNotifierProvider.notifier).resolveDeletions(
                account,
                _proposals,
              );
        }
        if (mounted) Navigator.pop(context);
      },
      loading: () {},
      error: (_, __) {},
    );
  }
}

class _ProposalCard extends StatelessWidget {
  final DeletionProposal proposal;
  final ValueChanged<DeletionChoice> onChoose;

  const _ProposalCard({required this.proposal, required this.onChoose});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final Contact contact;
    final String missingSide;
    if (proposal.side == DeletionSide.localDeleted) {
      contact = proposal.remoteContact!;
      missingSide = 'deleted from this phone';
    } else {
      contact = proposal.localContact!;
      missingSide = 'deleted from the server';
    }
    final decided = proposal.choice != DeletionChoice.unresolved;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(contact.bestName, style: theme.textTheme.titleMedium),
            const SizedBox(height: 4),
            Text('$missingSide — also delete it from the other side, or restore it?',
                style: theme.textTheme.bodySmall),
            if (contact.phones.isNotEmpty)
              Text('Tel: ${contact.phones.first.number}', style: const TextStyle(fontSize: 12)),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => onChoose(DeletionChoice.propagate),
                    style: OutlinedButton.styleFrom(
                      backgroundColor: proposal.choice == DeletionChoice.propagate
                          ? theme.colorScheme.primaryContainer
                          : null,
                    ),
                    child: const Text('Delete'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => onChoose(DeletionChoice.restore),
                    style: OutlinedButton.styleFrom(
                      backgroundColor: proposal.choice == DeletionChoice.restore
                          ? theme.colorScheme.primaryContainer
                          : null,
                    ),
                    child: const Text('Restore'),
                  ),
                ),
              ],
            ),
            if (decided)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  proposal.choice == DeletionChoice.propagate ? 'Will delete' : 'Will restore',
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
```

- [ ] **Step 2: Add the entry on the Sync page**

In `lib/pages/sync_status_page.dart`:

2a. Add the review-page import after the existing imports. (`pendingDeletionsProvider` is defined in `contact_sync_status_provider.dart`, which this file already imports, so it needs no new import.)

```dart
import 'deletion_review_page.dart';
```

2b. In `build`, after `final conflicts = ref.watch(differingConflictsProvider);`, add:

```dart
    final deletionsAsync = ref.watch(pendingDeletionsProvider);
```

2c. After the Conflicts button block (the `if (conflicts.isNotEmpty) ...[ ... ]`), add a deletions entry. Insert this immediately after that block:

```dart
            // Pending deletions (deleted outside the app, or on the server)
            deletionsAsync.when(
              data: (proposals) {
                if (proposals.isEmpty) return const SizedBox.shrink();
                return Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => DeletionReviewPage(proposals: proposals),
                          ),
                        );
                      },
                      icon: const Icon(Icons.delete_sweep_outlined),
                      label: Text('Review ${proposals.length} deletions'),
                    ),
                  ),
                );
              },
              loading: () => const SizedBox.shrink(),
              error: (_, __) => const SizedBox.shrink(),
            );
```

- [ ] **Step 3: Verify it analyzes**

Run: `flutter analyze lib/pages/deletion_review_page.dart lib/pages/sync_status_page.dart`
Expected: "No issues found"

- [ ] **Step 4: Run the full suite**

Run: `flutter test`
Expected: all tests pass.

- [ ] **Step 5: Commit**

```bash
git add lib/pages/deletion_review_page.dart lib/pages/sync_status_page.dart
git commit -m "feat: deletion review page + Sync entry for inferred deletions"
```

---

### Task 9: Final verification

**Files:** none (verification only)

- [ ] **Step 1: Full analyze**

Run: `flutter analyze`
Expected: "No issues found"

- [ ] **Step 2: Full test suite**

Run: `flutter test`
Expected: all tests pass (placeholder + 6 diff-engine tests).

- [ ] **Step 3: Release build (Android)**

Run: `flutter build apk --release` (on this WSL2 box, per project memory, ensure `org.gradle.vfs.watch=false` is set if the build stalls ~25 min; sqlite3 must stay pinned to 2.x)
Expected: built APK with no errors.

- [ ] **Step 4: Manual on-device verification**

Install the APK and confirm each scenario (per spec §Testing):
1. **In-app delete propagates**: delete a synced contact from the detail page → it vanishes from the list → Sync Now → it is gone from the server (verify via the remote-only count dropping / server) and does not reappear on a second sync.
2. **Out-of-app local delete → review queue**: delete a synced contact from the system address book → Sync Now → "Review 1 deletion" appears on the Sync page → open it, choose Delete, Confirm → contact is removed from the server and stays gone on the next sync.
3. **Restore path**: in the review queue, choose Restore for a local-deleted contact → it is pulled back to the phone.
4. **Server delete → review queue**: delete a contact on the server → Sync Now → "Review deletions" → Delete → removed locally.
5. **First-sync safety**: add a fresh account with existing server contacts → Sync Now → contacts pull in; nothing appears in the review queue; no deletions.

- [ ] **Step 5: Commit any follow-ups, then merge**

If verification surfaced fixes, commit them. Otherwise the branch `feat/contact-deletion-sync` is ready to merge into `main` (use the finishing-a-development-branch skill when the user is ready).

---

## Self-Review Notes

**Spec coverage:** Tombstones (Task 2, 4, 5) ✓ · diff detection + excludeUids (Task 3) ✓ · sync tombstone processing + proposals + applyDeletionResolutions (Task 4) ✓ · DeletionProposal model (Task 1) ✓ · pendingDeletionsProvider single source of truth (Task 6) ✓ · in-app delete detail + swipe (Task 7) ✓ · review page + Sync entry (Task 8) ✓ · first-sync safety + both directions tested (Task 3, 9) ✓. No spec section left without a task.

**Type/signature consistency:** `DeletionProposal(uid, side, localContact?, remoteContact?, choice)` used identically in Tasks 1, 4, 6, 8. `computeDiff(... excludeUids)` matches across Tasks 3, 4, 6. `deleteLocalContact({accountId, localUid})` matches Tasks 5, 7. `resolveDeletions(account, proposals)` matches Tasks 5, 8. `insertTombstone/getTombstonesForAccount/deleteTombstone/deleteUidMapForRemote` match Tasks 2, 4, 5, 6.

**Known deviation (documented, not a gap):** `DatabaseService` CRUD is verified by analyze + contract + manual rather than isolated unit tests, because the DB is a lazy file-backed singleton not currently injectable; refactoring it is out of scope. The actual deletion-detection logic (the bug) is fully unit-tested in Task 3.
