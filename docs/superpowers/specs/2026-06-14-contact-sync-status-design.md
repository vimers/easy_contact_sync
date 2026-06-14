# Contact Sync Status — Design

Date: 2026-06-14

## Goal

Two UI improvements that surface sync state per contact:

1. **Contacts page**: show a sync-status icon next to every contact (local ∪ remote),
   with 4 states. State 4 (inconsistent) is tappable to open a read-only field
   comparison.
2. **Sync page**: a summary card with counts — remote total, in-sync, differing,
   remote-only (remote has more than local), local-only (remote has fewer).

## States

| # | State | Meaning |
|---|-------|---------|
| 1 | local-only | On phone, not on remote |
| 2 | remote-only | On remote, not on phone |
| 3 | in-sync | Both exist and are consistent |
| 4 | differing | Both exist but content differs |

## Core insight

Both features consume one shared computation: diff local contacts against the
cached remote snapshot and derive a per-contact status. The Contacts page draws
icons from it; the Sync page tallies it.

## State derivation (reuses DiffEngine, no reinvention)

`DiffEngine.computeDiff(local, cachedRemote, accountId)` already classifies
changes using `sync_meta` (avoids false conflicts from local/vCard formatting
drift). Map `DiffType` → display state by **contact existence + `identical` flag**:

- both `localContact` and `remoteContact` present:
  - `identical` → state 3
  - else (`conflict` / local-changed / remote-changed) → state 4
- only `localContact` present (`localOnly`, `remoteDeleted`) → state 1
- only `remoteContact` present (`remoteOnly`, `localDeleted`) → state 2

Direct `contentHash` comparison is intentionally **not** used (formatting drift
between the Android address book and vCard causes false state-4).

## Data model

New table (DB v2 → v3, `onUpgrade`):

```sql
CREATE TABLE remote_contact_cache (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  account_id INTEGER NOT NULL,
  uid TEXT NOT NULL,
  etag TEXT,
  content_hash TEXT NOT NULL,
  contact_json TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  UNIQUE(account_id, uid)
)
```

Stores the full remote `Contact` as JSON so remote-only contacts render and
state-4 compare works. Replaced wholesale per account after each sync.

`Contact` (and `ContactPhone`/`ContactEmail`/`ContactAddress`) gain
`toJson()` / `fromJson()`.

CRUD: `replaceRemoteCacheForAccount(accountId, contacts)`,
`getRemoteCacheForAccount(accountId)`, `getAllRemoteCache()`.

## Providers

- `remoteCacheVersionProvider` (`StateProvider<int>`) — bumped after sync to
  trigger recompute.
- `contactSyncStatusProvider` (`FutureProvider<ContactSyncSnapshot>`):
  - reads local contacts + all accounts' remote cache
  - runs `computeDiff` per account, merges by uid
  - emits `ContactSyncSnapshot`:
    - `List<DisplayContact> items` (contact + `ContactSyncStatus` + `fromRemote` flag),
      sorted by name, local-before-remote-on-tie
    - tallies: `remoteTotal`, `inSync`, `differing`, `remoteOnly`, `localOnly`
  - watches local contacts + `remoteCacheVersionProvider`

`enum ContactSyncStatus { localOnly, remoteOnly, inSync, differing }`

## Sync engine wiring

- `sync()`: after fetching `remoteContacts`, call
  `replaceRemoteCacheForAccount(account.id, remoteContacts)`; bump
  `remoteCacheVersionProvider` via the notifier after sync completes (in
  `SyncNotifier`).
- `applyResolutions()`: upsert resolved-contact cache rows for resolved uids.

## Contacts page

- Data source switches from `contactsProvider` to `contactSyncStatusProvider`.
- `ContactListItem` gains a trailing status icon:
  - state 1 `phone_android` (grey) · state 2 `cloud` (grey) ·
    state 3 `check_circle` (green) · state 4 `sync_problem` (orange, tappable).
- Tapping a state-4 contact opens a **read-only** compare page built from
  `DiffEngine.computeFieldDiff` + existing `DiffViewerWidget`.
- Conflict resolution (use local/remote) stays on Sync → Conflicts (not in the list).

## Sync page

A "Sync Status Overview" card below the status card, with 5 chips/rows:
remote total · in-sync · differing · remote-only · local-only. Refreshes on
sync / pull-to-refresh (driven by the shared provider).

## Out of scope (YAGNI)

- Dedicated "refresh status only" button — Sync Now already refreshes.
- Per-account UI in the list — iterate accounts, merge into one list.
- Inline conflict resolution in the contacts list.

## Testing

- `computeDiff`-based mapping is the risk area; verify mapping logic with a
  focused unit test over `DiffType` → `ContactSyncStatus` (existence + identical).
- Manual: build APK, install, confirm icons + counts update after Sync Now.
