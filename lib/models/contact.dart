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
  /// Excludes uid, etag, href as those are metadata. Phones, emails and
  /// categories are sorted first, so reordering by the server or address book
  /// does not register as a change.
  String get contentHash {
    final sortedPhones = phones.map((p) => '${p.number}:${p.label}').toList()..sort();
    final sortedEmails = emails.map((e) => '${e.address}:${e.label}').toList()..sort();
    // NOTE: `categories` is intentionally excluded — it is not round-tripped
    // through flutter_contacts (Android groups ≠ vCard CATEGORIES), so
    // including it made any categorized remote contact re-conflict forever.
    // `birthday` IS round-tripped via events in the mappers.
    final parts = [
      firstName ?? '',
      lastName ?? '',
      sortedPhones.join(','),
      sortedEmails.join(','),
      organization ?? '',
      title ?? '',
      note ?? '',
      birthday?.toIso8601String() ?? '',
      // photo intentionally excluded from the hash: flutter_contacts 1.1.9+2
      // writes the photo to the raw-level DisplayPhoto asset but reads it back
      // from the contact-level DISPLAY_PHOTO, which Android does not aggregate
      // back — so the stored photo reads as null and any photo-bearing contact
      // re-conflicts forever. Photo is still synced for display (see
      // _fromFlutterContact thumbnail fallback); it just no longer gates
      // conflict detection.
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

  /// Normalized key used to match a contact across local/remote despite
  /// formatting drift (phone punctuation, case, whitespace) introduced by the
  /// vCard round-trip and the device address book. Two contacts with the same
  /// matchKey are treated as the same person. Distinct from [contentHash],
  /// which is exact and used for change detection.
  String get matchKey {
    // Strip ALL whitespace from the name: some CardDAV servers insert a space
    // into short names (e.g. "宗良" → "宗 良"), which would otherwise break
    // matching. Whitespace isn't meaningful for identity.
    final name = bestName.toLowerCase().replaceAll(RegExp(r'\s+'), '');
    final phoneDigits = phones
        .map((p) => p.number.replaceAll(RegExp(r'\D'), ''))
        .toList()
      ..sort();
    final emailsLower = emails
        .map((e) => e.address.toLowerCase().trim())
        .toList()
      ..sort();
    return '$name|${phoneDigits.join(',')}|${emailsLower.join(',')}';
  }

  /// Serialize for the remote contact cache (and any other JSON storage).
  Map<String, dynamic> toJson() => {
        'uid': uid,
        'etag': etag,
        'href': href,
        'displayName': displayName,
        'firstName': firstName,
        'lastName': lastName,
        'phones': phones.map((p) => p.toJson()).toList(),
        'emails': emails.map((e) => e.toJson()).toList(),
        'organization': organization,
        'title': title,
        'note': note,
        'addresses': addresses.map((a) => a.toJson()).toList(),
        'birthday': birthday?.toIso8601String(),
        'categories': categories,
        'photo': photo,
        'revision': revision?.toIso8601String(),
      };

  factory Contact.fromJson(Map<String, dynamic> j) => Contact(
        uid: j['uid'] as String?,
        etag: j['etag'] as String?,
        href: j['href'] as String?,
        displayName: j['displayName'] as String?,
        firstName: j['firstName'] as String?,
        lastName: j['lastName'] as String?,
        phones: (j['phones'] as List? ?? [])
            .map((p) => ContactPhone.fromJson(p as Map<String, dynamic>))
            .toList(),
        emails: (j['emails'] as List? ?? [])
            .map((e) => ContactEmail.fromJson(e as Map<String, dynamic>))
            .toList(),
        organization: j['organization'] as String?,
        title: j['title'] as String?,
        note: j['note'] as String?,
        addresses: (j['addresses'] as List? ?? [])
            .map((a) => ContactAddress.fromJson(a as Map<String, dynamic>))
            .toList(),
        birthday:
            j['birthday'] != null ? DateTime.parse(j['birthday'] as String) : null,
        categories:
            (j['categories'] as List? ?? []).map((c) => c as String).toList(),
        photo: j['photo'] as String?,
        revision:
            j['revision'] != null ? DateTime.parse(j['revision'] as String) : null,
      );
}

class ContactPhone {
  final String number;
  final String label; // mobile, home, work, other

  const ContactPhone({
    required this.number,
    this.label = 'mobile',
  });

  Map<String, dynamic> toJson() => {'number': number, 'label': label};

  factory ContactPhone.fromJson(Map<String, dynamic> j) => ContactPhone(
        number: j['number'] as String,
        label: j['label'] as String? ?? 'mobile',
      );

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

  Map<String, dynamic> toJson() => {'address': address, 'label': label};

  factory ContactEmail.fromJson(Map<String, dynamic> j) => ContactEmail(
        address: j['address'] as String,
        label: j['label'] as String? ?? 'home',
      );

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

  Map<String, dynamic> toJson() => {
        'street': street,
        'city': city,
        'region': region,
        'postalCode': postalCode,
        'country': country,
        'label': label,
      };

  factory ContactAddress.fromJson(Map<String, dynamic> j) => ContactAddress(
        street: j['street'] as String?,
        city: j['city'] as String?,
        region: j['region'] as String?,
        postalCode: j['postalCode'] as String?,
        country: j['country'] as String?,
        label: j['label'] as String? ?? 'home',
      );
}
