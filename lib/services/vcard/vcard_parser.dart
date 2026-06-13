import '../../models/contact.dart';

/// Parses vCard 3.0 and 4.0 text into Contact models.
class VCardParser {
  /// Parse a single vCard string into a Contact.
  Contact parse(String vcardText) {
    final lines = _unfoldLines(vcardText);
    final properties = <String, List<String>>{};
    final orderedKeys = <String>[];

    for (final line in lines) {
      if (line.isEmpty) continue;
      final colonIdx = line.indexOf(':');
      if (colonIdx < 0) continue;
      final key = line.substring(0, colonIdx).toUpperCase();
      final value = line.substring(colonIdx + 1);
      // Normalize key: strip group prefix (e.g. "ITEM1.TEL" -> "TEL")
      final normalizedKey = key.contains('.')
          ? key.substring(key.lastIndexOf('.') + 1)
          : key;
      // Strip TYPE= prefix from parameters, keep the type value
      final cleanKey = _extractKeyAndType(normalizedKey);
      final mapKey = cleanKey.key;

      properties.putIfAbsent(mapKey, () => []);
      properties[mapKey]!.add(value);
      if (!orderedKeys.contains(mapKey)) orderedKeys.add(mapKey);
    }

    return Contact(
      uid: _first(properties['UID']),
      displayName: _first(properties['FN']),
      firstName: _extractN(properties['N'])?['firstName'],
      lastName: _extractN(properties['N'])?['lastName'],
      phones: _extractPhones(lines),
      emails: _extractEmails(lines),
      organization: _extractOrg(properties['ORG']),
      title: _first(properties['TITLE']),
      note: _first(properties['NOTE']),
      addresses: _extractAddresses(lines),
      birthday: _parseDate(_first(properties['BDAY'])),
      categories: _extractCategories(properties['CATEGORIES']),
      photo: _first(properties['PHOTO']),
      revision: _parseDate(_first(properties['REV'])),
    );
  }

  /// Parse multiple vCards from a single string.
  List<Contact> parseAll(String text) {
    final vcards = <String>[];
    final buffer = StringBuffer();
    var inVcard = false;

    for (final line in text.split(RegExp(r'\r?\n'))) {
      if (line.toUpperCase().startsWith('BEGIN:VCARD')) {
        inVcard = true;
        buffer.clear();
      }
      if (inVcard) {
        buffer.writeln(line);
      }
      if (line.toUpperCase().startsWith('END:VCARD')) {
        inVcard = false;
        vcards.add(buffer.toString());
      }
    }

    return vcards.map((v) => parse(v)).toList();
  }

  // ── Internal helpers ──

  /// Unfold continuation lines (lines starting with space or tab).
  List<String> _unfoldLines(String text) {
    final rawLines = text.split(RegExp(r'\r?\n'));
    final result = <String>[];
    for (final line in rawLines) {
      if (line.startsWith(' ') || line.startsWith('\t')) {
        if (result.isNotEmpty) {
          result[result.length - 1] += line.substring(1);
        }
      } else {
        result.add(line);
      }
    }
    return result;
  }

  ({String key, String? type}) _extractKeyAndType(String rawKey) {
    // Handle "TEL;TYPE=CELL,VOICE" -> key=TEL, type not needed here
    final semiIdx = rawKey.indexOf(';');
    if (semiIdx < 0) return (key: rawKey, type: null);
    return (key: rawKey.substring(0, semiIdx), type: null);
  }

  String? _first(List<String>? values) {
    if (values == null || values.isEmpty) return null;
    return values.first;
  }

  Map<String, String>? _extractN(List<String>? values) {
    if (values == null || values.isEmpty) return null;
    // N:LastName;FirstName;MiddleName;Prefix;Suffix
    final parts = values.first.split(';');
    return {
      'lastName': parts.length > 0 ? parts[0] : '',
      'firstName': parts.length > 1 ? parts[1] : '',
      'middleName': parts.length > 2 ? parts[2] : '',
      'prefix': parts.length > 3 ? parts[3] : '',
      'suffix': parts.length > 4 ? parts[4] : '',
    };
  }

  List<ContactPhone> _extractPhones(List<String> lines) {
    final phones = <ContactPhone>[];
    for (final line in lines) {
      final upper = line.toUpperCase();
      if (!upper.startsWith('TEL') && !upper.contains('.TEL')) continue;
      final colonIdx = line.indexOf(':');
      if (colonIdx < 0) continue;
      final prefix = line.substring(0, colonIdx).toUpperCase();
      final number = line.substring(colonIdx + 1).trim();
      if (number.isEmpty) continue;

      String label = 'other';
      if (prefix.contains('CELL') || prefix.contains('MOBILE')) {
        label = 'mobile';
      } else if (prefix.contains('HOME')) {
        label = 'home';
      } else if (prefix.contains('WORK')) {
        label = 'work';
      }
      phones.add(ContactPhone(number: number, label: label));
    }
    return phones;
  }

  List<ContactEmail> _extractEmails(List<String> lines) {
    final emails = <ContactEmail>[];
    for (final line in lines) {
      final upper = line.toUpperCase();
      if (!upper.startsWith('EMAIL') && !upper.contains('.EMAIL')) continue;
      final colonIdx = line.indexOf(':');
      if (colonIdx < 0) continue;
      final prefix = line.substring(0, colonIdx).toUpperCase();
      final address = line.substring(colonIdx + 1).trim();
      if (address.isEmpty) continue;

      String label = 'other';
      if (prefix.contains('HOME')) {
        label = 'home';
      } else if (prefix.contains('WORK')) {
        label = 'work';
      }
      emails.add(ContactEmail(address: address, label: label));
    }
    return emails;
  }

  String? _extractOrg(List<String>? values) {
    if (values == null || values.isEmpty) return null;
    // ORG:Organization;Department
    return values.first.split(';').first;
  }

  List<ContactAddress> _extractAddresses(List<String> lines) {
    final addresses = <ContactAddress>[];
    for (final line in lines) {
      final upper = line.toUpperCase();
      if (!upper.startsWith('ADR') && !upper.contains('.ADR')) continue;
      final colonIdx = line.indexOf(':');
      if (colonIdx < 0) continue;
      final prefix = line.substring(0, colonIdx).toUpperCase();
      final value = line.substring(colonIdx + 1).trim();
      // ADR:POBox;ExtAddr;Street;City;Region;PostalCode;Country
      final parts = value.split(';');

      String label = 'other';
      if (prefix.contains('HOME')) {
        label = 'home';
      } else if (prefix.contains('WORK')) {
        label = 'work';
      }

      addresses.add(ContactAddress(
        street: parts.length > 2 ? parts[2] : null,
        city: parts.length > 3 ? parts[3] : null,
        region: parts.length > 4 ? parts[4] : null,
        postalCode: parts.length > 5 ? parts[5] : null,
        country: parts.length > 6 ? parts[6] : null,
        label: label,
      ));
    }
    return addresses;
  }

  DateTime? _parseDate(String? value) {
    if (value == null) return null;
    try {
      // Handle YYYY-MM-DD and YYYYMMDD
      final cleaned = value.replaceAll('-', '').replaceAll('/', '');
      if (cleaned.length == 8) {
        return DateTime(
          int.parse(cleaned.substring(0, 4)),
          int.parse(cleaned.substring(4, 6)),
          int.parse(cleaned.substring(6, 8)),
        );
      }
      return DateTime.parse(value);
    } catch (_) {
      return null;
    }
  }

  List<String> _extractCategories(List<String>? values) {
    if (values == null || values.isEmpty) return [];
    return values.first.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
  }
}
