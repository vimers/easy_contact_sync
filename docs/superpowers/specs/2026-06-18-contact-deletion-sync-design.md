# Contact Deletion Sync — Design

Date: 2026-06-18

## Goal

Contacts deleted on one side must stay deleted — currently they come back. Two
problems share one root cause:

1. **Bug**: deleting a contact in the local (device) address book does not
   propagate; the next sync pulls it back. Same in reverse — a contact deleted
   on the server gets re-pushed.
2. **Missing feature**: the app has no delete action.

## Root cause

`DiffType.localDeleted` / `remoteDeleted` exist and have switch branches in
`SyncEngine.sync()`, but `DiffEngine.computeDiff()` **never emits them**. The
diff engine loads the previous-sync history (`syncMetaMap`, keyed by remote uid)
yet never consults it, so every "remote contact with no local counterpart" is
classified as brand-new `remoteOnly` (→ pulled back) and every "local contact
with no remote counterpart" as `localOnly` (→ re-pushed). The deletion branches
are dead code.

A second, sharper risk makes naive "auto-propagate" unsafe: `_listContactsViaPropfind`
(`operations.dart:62-72`) **silently skips** any contact whose individual GET
fails. A flaky connection therefore makes `listContacts` return a *partial* set,
so "remote didn't return it" is not proof the server deleted it. Treating it as
proof and auto-deleting locally could destroy many local contacts in one bad sync.

## Core insight

Distinguish **known** deletions from **inferred** ones, and treat them differently:

- **Known** — the user deleted via the app. Record a **tombstone** at delete time;
  the tombstone is proof of intent → propagate to the server with no guessing,
  no friction.
- **Inferred** — a deletion observed only by comparing current state to sync
  history (deleted outside the app, or deleted on the server). These can only be
  detected, never proven → never delete silently; surface them in a
  **confirmation queue** (mirroring the existing conflict-resolution flow) and
  act only after the user approves.

The boundary that prevents first-sync data loss: inferred deletion detection keys
off `sync_meta`, so an empty `sync_meta` (fresh account / first sync) classifies
everything as new — nothing is ever flagged as a deletion until it has prior sync
history.

## Data model

New table (DB v4 → v5, `onUpgrade`):

```sql
CREATE TABLE deleted_uids (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  account_id INTEGER NOT NULL,
  uid TEXT NOT NULL,            -- remote uid deleted in-app
  deleted_at TEXT NOT NULL,
  UNIQUE(account_id, uid)
)
```

A tombstone is a durable record that "this remote uid was deliberately deleted
locally and should be removed from the server at the next sync." It is written by
the in-app delete action and consumed (and removed) by `sync()`.

`DatabaseService` gains:
- `insertTombstone(accountId, uid)`
- `getTombstonesForAccount(accountId) → List<{uid, deleted_at}>`
- `deleteTombstone(accountId, uid)`
- `deleteUidMapForRemote(accountId, remoteUid)` — mirrors the existing
  `deleteUidMapForLocal` (needed to clean the uid map when the local side is
  already gone).

Inferred deletion proposals are **not** a new table — they are derived on demand
by re-running the diff (see Providers). Confirming a proposal cleans `sync_meta`,
after which the diff no longer flags it.

## diff_engine changes

`computeDiff` gains an optional `excludeUids: Set<String>?` (tombstoned uids,
passed in by the sync engine) and now consults the already-loaded `syncMetaMap`:

- **Phase 3** (remote uid with no local counterpart):
  - in `syncMetaMap` and not in `excludeUids` → `localDeleted`
  - else → `remoteOnly`
- **Phase 2 else branch** (local with no remote counterpart and no `matchKey`
  content match):
  - its ruid in `syncMetaMap` → `remoteDeleted`
  - else → `localOnly`

`matchKey` content matching continues to run first, so a contact that merely
changed uid (same name+phone+email) is re-paired as `identical` rather than
mis-detected as a deletion. `excludeUids` keeps a not-yet-processed tombstone
from also being queued as an inferred deletion.

## sync_engine changes

`sync()` gains a tombstone-processing step before the diff loop:

1. For each tombstone `(accountId, R)`:
   - if `R` is still in `remoteContacts` → `operations.deleteContact(R)`; on
     success remove `R` from the in-memory `remoteContacts`, then delete the
     tombstone, the `sync_meta` row, and the `uid_map` row. **On failure, leave
     all three intact** so the next sync retries — never clean metadata before
     the server delete succeeds.
   - if `R` is already absent remotely → just delete the tombstone.
2. Pass the set of tombstoned uids as `excludeUids` to `computeDiff`.
3. In the diff loop, `localDeleted` / `remoteDeleted` are **no longer executed**.
   They are collected into a new `SyncResult.deletionProposals: List<DeletionProposal>`.
   `localOnly` / `remoteOnly` / `identical` / `conflict` are unchanged.

New `applyDeletionResolutions(account, List<DeletionProposal> resolved)` mirrors
`applyResolutions`. Per proposal, by user choice:
- **propagate** — finish the deletion on the other side (`localDeleted` → delete
  remote; `remoteDeleted` → delete local) and clean `sync_meta` + `uid_map`.
- **restore** — undo the inference (`localDeleted` → pull `R` to local +
  re-establish linkage, i.e. act as `remoteOnly`; `remoteDeleted` → push local
  to remote + re-establish linkage, i.e. act as `localOnly`).

Cleanup is ordered after a successful operation so a failure leaves state
unchanged and retriable.

## Models

```dart
enum DeletionSide { localDeleted, remoteDeleted } // which side is now missing

class DeletionProposal {
  final String uid;
  final DeletionSide side;
  final Contact? localContact;   // present for remoteDeleted
  final Contact? remoteContact;  // present for localDeleted
  DeletionChoice choice;         // unresolved | propagate | restore
}
enum DeletionChoice { unresolved, propagate, restore }
```

`SyncResult` gains `List<DeletionProposal> deletionProposals` (default empty).

## Providers

- `SyncNotifier.syncAll()` refreshes as today (`contactsProvider` invalidate +
  `remoteCacheVersionProvider` bump — unchanged). The post-sync "deletions need
  review" signal is the live `pendingDeletionsProvider` count, not a snapshot on
  `SyncState`.
- `SyncNotifier.resolveDeletions(account, proposals)` mirrors `resolveConflicts`,
  calling `applyDeletionResolutions` then refreshing.
- `pendingDeletionsProvider` — a `FutureProvider` that re-runs `computeDiff`
  (sync_meta-aware, same as `contactSyncStatusProvider`), passing the account's
  tombstone uids as `excludeUids` so a not-yet-processed tombstone isn't double-
  listed as a proposal. It emits the current inferred-deletion proposals and is
  the **single source of truth for the review UI** (both the "Pending deletions
  (N)" entry count and the review page list read it live). This avoids persisting
  a separate queue; confirming a proposal cleans `sync_meta`, so on the next
  recompute it drops out. (`SyncState.pendingDeletions` is deliberately **not**
  added — the live provider replaces it. `SyncResult.deletionProposals` stays as
  the sync return value / stat, not a UI source.)
- **In-app delete action** (`SyncNotifier` or a dedicated method on a contacts
  notifier):
  1. confirm dialog
  2. `LocalContactService.deleteContact(localUid)`
  3. look up `R = uid_map[localUid]` for the account
  4. if `R` found → `insertTombstone(accountId, R)` (sync_meta/uid_map are left
     intact; the sync's tombstone step cleans them after the server delete
     succeeds — this is what keeps a failed tombstone sync from re-pulling the
     contact). If `R` is **not** found (a local-only contact never synced), skip
     the tombstone — there is nothing on the server to remove.
  5. refresh (`contactsProvider` invalidate)

  Single-account assumption is retained (matches the rest of the app, which uses
  `accounts.first` throughout); multi-account targeting is a future refinement.

## UI

- **Contact detail page**: trailing AppBar delete icon. **Contacts list**: left
  swipe (`Dismissible`) to delete. Both gated on a local contact existing
  (local-only / in-sync / differing); `remoteOnly` (no local copy) offers no
  delete — it hasn't been pulled yet. A confirmation dialog precedes deletion;
  a snackbar states the contact will be removed from the server on next sync.
  `ContactDetailPage` currently takes a bare `Contact`; it is extended to receive
  the `DisplayContact` (or at least the local uid + remote uid + account) so it
  can write the correct tombstone.
- **Deletion review page** (mirrors `ConflictPage`): per-item
  "also delete from server / restore locally" with batch actions and a confirm
  button → `resolveDeletions`. Entry point on the Sync page as
  "Pending deletions (N)" alongside "Resolve conflicts", shown only when
  `pendingDeletions` is non-empty.

`contact_sync_status_provider` needs no behavioral change: an inferred
`localDeleted` (local null) maps to its existing `remoteOnly` branch and a
`remoteDeleted` (remote null) to `localOnly` — correct transient states before
the user confirms.

## Testing (TDD — failing tests first)

`DiffEngine.computeDiff` is pure Dart; `DatabaseService` methods are virtual, so
a test `extends DatabaseService` overriding `getSyncMetaForAccount` to return
canned rows exercises the engine without touching a real DB. Cases:

- `localDeleted`: remote uid in `sync_meta`, no local counterpart.
- `remoteDeleted`: local ruid in `sync_meta`, no remote counterpart, no matchKey.
- `remoteOnly`: remote uid **not** in `sync_meta` → still pulls (new contact).
- `localOnly`: local ruid **not** in `sync_meta` → still pushes.
- `identical`: content match regardless of sync_meta.
- first-sync safety: empty `sync_meta` ⇒ zero deletions detected.
- `excludeUids`: a tombstoned uid is not flagged `localDeleted`.

Manual verification on device: delete in-app → sync → gone from server; delete
via system address book → sync → appears in review queue → confirm → gone from
server and stays gone; delete on server → sync → review queue → confirm → gone
locally.

## Out of scope (YAGNI)

- Auto-sync immediately after an in-app delete (propagation happens on the next
  manual/background sync; tombstones make a later immediate-sync opt-in safe but
  it is not added now).
- Multi-account targeting for the tombstone — single account, matching the app.
- Batch/multi-select delete in the list — single delete (detail + swipe) only.
- Soft-delete / undo window beyond the review queue.
