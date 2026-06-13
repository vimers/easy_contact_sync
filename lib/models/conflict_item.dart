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
