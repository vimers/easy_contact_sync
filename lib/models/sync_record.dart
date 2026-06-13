/// Sync metadata for a single contact, tracking remote state.
class SyncMeta {
  final int? id;
  final int accountId;
  final String uid;
  final String? etag;
  final String lastSyncHash;
  final DateTime updatedAt;

  const SyncMeta({
    this.id,
    required this.accountId,
    required this.uid,
    this.etag,
    required this.lastSyncHash,
    required this.updatedAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'account_id': accountId,
      'uid': uid,
      'etag': etag,
      'last_sync_hash': lastSyncHash,
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  factory SyncMeta.fromMap(Map<String, dynamic> map) {
    return SyncMeta(
      id: map['id'] as int?,
      accountId: map['account_id'] as int,
      uid: map['uid'] as String,
      etag: map['etag'] as String?,
      lastSyncHash: map['last_sync_hash'] as String,
      updatedAt: DateTime.parse(map['updated_at'] as String),
    );
  }
}

/// Status of a sync run.
enum SyncStatus { success, failure, conflicts }

/// A single sync log entry.
class SyncLog {
  final int? id;
  final int accountId;
  final DateTime timestamp;
  final SyncStatus status;
  final int conflictsCount;
  final String? errorMessage;

  const SyncLog({
    this.id,
    required this.accountId,
    required this.timestamp,
    required this.status,
    this.conflictsCount = 0,
    this.errorMessage,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'account_id': accountId,
      'timestamp': timestamp.toIso8601String(),
      'status': status.name,
      'conflicts_count': conflictsCount,
      'error_message': errorMessage,
    };
  }

  factory SyncLog.fromMap(Map<String, dynamic> map) {
    return SyncLog(
      id: map['id'] as int?,
      accountId: map['account_id'] as int,
      timestamp: DateTime.parse(map['timestamp'] as String),
      status: SyncStatus.values.firstWhere((s) => s.name == map['status']),
      conflictsCount: map['conflicts_count'] as int? ?? 0,
      errorMessage: map['error_message'] as String?,
    );
  }
}
