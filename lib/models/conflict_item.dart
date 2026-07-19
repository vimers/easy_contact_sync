import 'contact.dart';

/// Represents a conflict between local and remote versions of a contact.
class ConflictItem {
  final String uid;
  final Contact localContact;
  final Contact remoteContact;
  ConflictResolution resolution;

  ConflictItem({
    required this.uid,
    required this.localContact,
    required this.remoteContact,
    this.resolution = ConflictResolution.unresolved,
  });
}

/// User's choice for resolving a conflict.
enum ConflictResolution {
  unresolved,
  useLocal,
  useRemote,
}

/// The type of change detected by the diff engine.
enum DiffType {
  localOnly, // new on local, not on remote
  remoteOnly, // new on remote, not on local
  localDeleted, // was synced, now missing locally
  remoteDeleted, // was synced, now missing remotely
  conflict, // both sides modified
  identical, // no change
  // Paired contact whose local copy is untouched since the last sync but whose
  // content still differs from remote — either a genuine remote edit, or
  // "stale anchor" divergence where an earlier (buggy) pull dropped a field
  // (e.g. the photo before it was propagated). The engine refreshes the local
  // copy from remote in place; it must NOT createContact (that duplicates).
  remoteNewer,
}

/// A single diff result from comparing local vs remote.
class DiffResult {
  final String uid;
  final DiffType type;
  final Contact? localContact;
  final Contact? remoteContact;

  const DiffResult({
    required this.uid,
    required this.type,
    this.localContact,
    this.remoteContact,
  });
}

/// Field-level diff between two contacts.
class FieldDiff {
  final String fieldName;
  final String? localValue;
  final String? remoteValue;

  const FieldDiff({
    required this.fieldName,
    this.localValue,
    this.remoteValue,
  });

  bool get hasDifference => localValue != remoteValue;
}

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
