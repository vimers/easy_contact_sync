/// Unified contact model used throughout the app.
/// Maps to/from vCard and local system contacts.
class Contact {
  final String? uid;
  final String? etag;
  final String? href;
  final String? displayName;
  final String? firstName;
  final String? lastName;
  final List<ContactPhone> phones;
  final List<ContactEmail> emails;
  final String? organization;
  final String? title;
  final String? note;
  final List<ContactAddress> addresses;
  final DateTime? birthday;
  final List<String> categories;
  final String? photo; // base64 encoded
  final DateTime? revision;

  const Contact({
    this.uid,
    this.etag,
    this.href,
    this.displayName,
    this.firstName,
    this.lastName,
    this.phones = const [],
    this.emails = const [],
    this.organization,
    this.title,
    this.note,
    this.addresses = const [],
    this.birthday,
    this.categories = const [],
    this.photo,
    this.revision,
  });

  Contact copyWith({
    String? uid,
    String? etag,
    String? href,
    String? displayName,
    String? firstName,
    String? lastName,
    List<ContactPhone>? phones,
    List<ContactEmail>? emails,
    String? organization,
    String? title,
    String? note,
    List<ContactAddress>? addresses,
    DateTime? birthday,
    List<String>? categories,
    String? photo,
    DateTime? revision,
  }) {
    return Contact(
      uid: uid ?? this.uid,
      etag: etag ?? this.etag,
      href: href ?? this.href,
      displayName: displayName ?? this.displayName,
      firstName: firstName ?? this.firstName,
      lastName: lastName ?? this.lastName,
      phones: phones ?? this.phones,
      emails: emails ?? this.emails,
      organization: organization ?? this.organization,
      title: title ?? this.title,
      note: note ?? this.note,
      addresses: addresses ?? this.addresses,
      birthday: birthday ?? this.birthday,
      categories: categories ?? this.categories,
      photo: photo ?? this.photo,
      revision: revision ?? this.revision,
    );
  }

  /// Compute a content hash for diff detection.
  /// Excludes uid, etag, href as those are metadata.
  String get contentHash {
    final parts = [
      displayName ?? '',
      firstName ?? '',
      lastName ?? '',
      phones.map((p) => '${p.number}:${p.label}').join(','),
      emails.map((e) => '${e.address}:${e.label}').join(','),
      organization ?? '',
      title ?? '',
      note ?? '',
      birthday?.toIso8601String() ?? '',
      categories.join(','),
      photo?.length.toString() ?? '',
    ];
    return parts.join('|||');
  }

  /// Get the best available display name.
  String get bestName {
    if (displayName != null && displayName!.isNotEmpty) return displayName!;
    final parts = [firstName, lastName].where((s) => s != null && s.isNotEmpty);
    if (parts.isNotEmpty) return parts.join(' ');
    if (phones.isNotEmpty) return phones.first.number;
    if (emails.isNotEmpty) return emails.first.address;
    return 'Unknown';
  }
}

class ContactPhone {
  final String number;
  final String label; // mobile, home, work, other

  const ContactPhone({
    required this.number,
    this.label = 'mobile',
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ContactPhone && number == other.number && label == other.label;

  @override
  int get hashCode => Object.hash(number, label);
}

class ContactEmail {
  final String address;
  final String label; // home, work, other

  const ContactEmail({
    required this.address,
    this.label = 'home',
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ContactEmail && address == other.address && label == other.label;

  @override
  int get hashCode => Object.hash(address, label);
}

class ContactAddress {
  final String? street;
  final String? city;
  final String? region;
  final String? postalCode;
  final String? country;
  final String label; // home, work, other

  const ContactAddress({
    this.street,
    this.city,
    this.region,
    this.postalCode,
    this.country,
    this.label = 'home',
  });
}
