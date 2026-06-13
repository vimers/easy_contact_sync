import '../../models/conflict_item.dart';

/// Resolves conflicts based on user choices.
class ConflictResolver {
  /// Apply batch resolution to all unresolved conflicts.
  void resolveAll(List<ConflictItem> conflicts, ConflictResolution resolution) {
    for (final conflict in conflicts) {
      if (conflict.resolution == ConflictResolution.unresolved) {
        conflict.resolution = resolution;
      }
    }
  }

  /// Resolve a single conflict.
  void resolve(ConflictItem conflict, ConflictResolution resolution) {
    conflict.resolution = resolution;
  }

  /// Check if all conflicts are resolved.
  bool allResolved(List<ConflictItem> conflicts) {
    return conflicts.every((c) => c.resolution != ConflictResolution.unresolved);
  }

  /// Get the chosen contact for a resolved conflict.
  ResolvedContact getChosenContact(ConflictItem conflict) {
    if (conflict.resolution == ConflictResolution.useLocal) {
      return ResolvedContact(contact: conflict.localContact, source: Source.local);
    } else if (conflict.resolution == ConflictResolution.useRemote) {
      return ResolvedContact(contact: conflict.remoteContact, source: Source.remote);
    }
    throw Exception('Conflict not resolved: ${conflict.uid}');
  }
}

/// Result of resolving a conflict.
class ResolvedContact {
  final dynamic contact;
  final Source source;

  const ResolvedContact({required this.contact, required this.source});
}

enum Source { local, remote }
