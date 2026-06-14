import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lpinyin/lpinyin.dart';

import '../models/conflict_item.dart';
import '../models/contact.dart';
import '../services/sync/diff_engine.dart';
import 'accounts_provider.dart';
import 'contacts_provider.dart';

/// Sort key for a contact name: Chinese chars → full pinyin, others kept as-is,
/// lowercased. Gives proper alphabetical ordering for mixed CJK/Latin names.
String _pinyinSortKey(String name) {
  final py = PinyinHelper.getPinyin(name, separator: '');
  return (py.isEmpty ? name : py).toLowerCase();
}

/// Per-contact sync state shown in the Contacts list.
enum ContactSyncStatus {
  localOnly, // on phone, not on remote
  remoteOnly, // on remote, not on phone
  inSync, // both exist and paired (content matches, or matched by name/phone)
  differing, // both exist but content differs
}

/// A contact as shown in the Contacts list, carrying its sync status and (for
/// state 4) both sides so the compare page can render the diff.
class DisplayContact {
  final String uid;
  final Contact contact; // local version if it exists, else remote
  final Contact? localContact;
  final Contact? remoteContact;
  final ContactSyncStatus status;

  const DisplayContact({
    required this.uid,
    required this.contact,
    required this.localContact,
    required this.remoteContact,
    required this.status,
  });
}

/// Snapshot consumed by both the Contacts page (per-contact icons) and the Sync
/// page (tallies).
class ContactSyncSnapshot {
  final List<DisplayContact> items;
  final int remoteTotal;
  final int inSync;
  final int differing;
  final int remoteOnly;
  final int localOnly;

  const ContactSyncSnapshot({
    required this.items,
    required this.remoteTotal,
    required this.inSync,
    required this.differing,
    required this.remoteOnly,
    required this.localOnly,
  });

  factory ContactSyncSnapshot.empty() => const ContactSyncSnapshot(
        items: [],
        remoteTotal: 0,
        inSync: 0,
        differing: 0,
        remoteOnly: 0,
        localOnly: 0,
      );
}

/// Bumped after each sync so [contactSyncStatusProvider] recomputes against the
/// refreshed remote cache.
final remoteCacheVersionProvider = StateProvider<int>((ref) => 0);

/// Computes per-contact sync status by pairing local contacts with the cached
/// remote snapshot using the SAME logic as the sync engine (uid map + normalized
/// matchKey). A paired local+remote collapses to a single row; only genuinely
/// single-sided contacts show as local-only / remote-only.
final contactSyncStatusProvider =
    FutureProvider<ContactSyncSnapshot>((ref) async {
  // Recompute when the cache is refreshed.
  ref.watch(remoteCacheVersionProvider);

  final db = ref.watch(databaseServiceProvider);
  final localService = ref.watch(localContactServiceProvider);
  final diffEngine = DiffEngine(db);

  final local = await localService.getAllContacts();
  final accountRows = await db.getAllAccounts();

  if (accountRows.isEmpty) {
    return ContactSyncSnapshot(
      items: local
          .map((c) => DisplayContact(
                uid: c.uid ?? '',
                contact: c,
                localContact: c,
                remoteContact: null,
                status: ContactSyncStatus.localOnly,
              ))
          .toList(),
      remoteTotal: 0,
      inSync: 0,
      differing: 0,
      remoteOnly: 0,
      localOnly: local.length,
    );
  }

  final accountId = accountRows.first['id'] as int;

  // Cached remote contacts for the account.
  final cacheRows = await db.getRemoteCacheForAccount(accountId);
  final remote = <Contact>[];
  for (final row in cacheRows) {
    final json = row['contact_json'] as String?;
    if (json == null) continue;
    try {
      remote.add(Contact.fromJson(jsonDecode(json) as Map<String, dynamic>));
    } catch (_) {
      // Skip unparseable cache rows.
    }
  }

  final uidMap = await db.getUidMapForAccount(accountId);

  // Reuse the sync engine's diff to pair local↔remote (uid map + matchKey).
  final diffs = await diffEngine.computeDiff(
    localContacts: local,
    remoteContacts: remote,
    accountId: accountId,
    localToRemoteUid: uidMap,
  );

  final items = <DisplayContact>[];
  var inSync = 0, differing = 0, remoteOnly = 0, localOnly = 0;

  for (final d in diffs) {
    // Classify by which sides exist; a paired contact is one row.
    ContactSyncStatus status;
    if (d.localContact != null && d.remoteContact != null) {
      // Both sides present. `identical` (incl. matchKey-paired) ⇒ in sync;
      // anything else (conflict / one-sided change) ⇒ differing.
      status = d.type == DiffType.identical
          ? ContactSyncStatus.inSync
          : ContactSyncStatus.differing;
    } else if (d.localContact != null) {
      status = ContactSyncStatus.localOnly;
    } else {
      status = ContactSyncStatus.remoteOnly;
    }

    switch (status) {
      case ContactSyncStatus.inSync:
        inSync++;
        break;
      case ContactSyncStatus.differing:
        differing++;
        break;
      case ContactSyncStatus.localOnly:
        localOnly++;
        break;
      case ContactSyncStatus.remoteOnly:
        remoteOnly++;
        break;
    }

    items.add(DisplayContact(
      uid: d.uid,
      contact: d.localContact ?? d.remoteContact!,
      localContact: d.localContact,
      remoteContact: d.remoteContact,
      status: status,
    ));
  }

  items.sort((a, b) =>
      _pinyinSortKey(a.contact.bestName).compareTo(_pinyinSortKey(b.contact.bestName)));

  return ContactSyncSnapshot(
    items: items,
    remoteTotal: remote.length,
    inSync: inSync,
    differing: differing,
    remoteOnly: remoteOnly,
    localOnly: localOnly,
  );
});

/// Contacts that exist on both sides but differ in content — surfaced as
/// resolvable conflicts. Drives the "Resolve Conflicts" entry on the Sync page
/// and the jump-to-resolve action from a differing contact.
final differingConflictsProvider = Provider<List<ConflictItem>>((ref) {
  final async = ref.watch(contactSyncStatusProvider);
  return async.maybeWhen(
    data: (s) => s.items
        .where((d) =>
            d.status == ContactSyncStatus.differing &&
            d.localContact != null &&
            d.remoteContact != null)
        .map((d) => ConflictItem(
              uid: d.uid,
              localContact: d.localContact!,
              remoteContact: d.remoteContact!,
            ))
        .toList(),
    orElse: () => const [],
  );
});
