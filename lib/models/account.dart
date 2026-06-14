/// CardDAV account model.
class Account {
  final int? id;
  final String serverUrl;
  final String username;
  final String addressbookName;
  final DateTime createdAt;

  const Account({
    this.id,
    required this.serverUrl,
    required this.username,
    this.addressbookName = 'default',
    required this.createdAt,
  });

  Account copyWith({
    int? id,
    String? serverUrl,
    String? username,
    String? addressbookName,
    DateTime? createdAt,
  }) {
    return Account(
      id: id ?? this.id,
      serverUrl: serverUrl ?? this.serverUrl,
      username: username ?? this.username,
      addressbookName: addressbookName ?? this.addressbookName,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  Map<String, dynamic> toMap({bool excludeId = false}) {
    final map = <String, dynamic>{
      'server_url': serverUrl,
      'username': username,
      'addressbook_name': addressbookName,
      'created_at': createdAt.toIso8601String(),
    };
    if (!excludeId && id != null) {
      map['id'] = id;
    }
    return map;
  }

  factory Account.fromMap(Map<String, dynamic> map) {
    return Account(
      id: map['id'] as int?,
      serverUrl: map['server_url'] as String,
      username: map['username'] as String,
      addressbookName: map['addressbook_name'] as String? ?? 'default',
      createdAt: DateTime.parse(map['created_at'] as String),
    );
  }
}
