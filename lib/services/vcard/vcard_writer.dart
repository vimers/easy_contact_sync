import '../../models/contact.dart';

/// Writes Contact models to vCard 3.0 format.
class VCardWriter {
  /// Convert a Contact to vCard 3.0 string.
  String write(Contact contact) {
    final lines = <String>[];

    lines.add('BEGIN:VCARD');
    lines.add('VERSION:3.0');

    if (contact.uid != null) {
      lines.add('UID:${contact.uid}');
    }

    if (contact.displayName != null) {
      lines.add('FN:${_escape(contact.displayName!)}');
    }

    // N:LastName;FirstName;MiddleName;Prefix;Suffix
    final lastName = contact.lastName ?? '';
    final firstName = contact.firstName ?? '';
    lines.add('N:$lastName;$firstName;;;');

    for (final phone in contact.phones) {
      final type = _phoneLabelToVcard(phone.label);
      lines.add('TEL;TYPE=$type:${phone.number}');
    }

    for (final email in contact.emails) {
      final type = _emailLabelToVcard(email.label);
      lines.add('EMAIL;TYPE=$type:${email.address}');
    }

    if (contact.organization != null) {
      lines.add('ORG:${_escape(contact.organization!)}');
    }

    if (contact.title != null) {
      lines.add('TITLE:${_escape(contact.title!)}');
    }

    if (contact.note != null) {
      lines.add('NOTE:${_escape(contact.note!)}');
    }

    for (final addr in contact.addresses) {
      final type = _addressLabelToVcard(addr.label);
      lines.add('ADR;TYPE=$type:;;${addr.street ?? ''};${addr.city ?? ''};${addr.region ?? ''};${addr.postalCode ?? ''};${addr.country ?? ''}');
    }

    if (contact.birthday != null) {
      lines.add('BDAY:${_formatDate(contact.birthday!)}');
    }

    if (contact.categories.isNotEmpty) {
      lines.add('CATEGORIES:${contact.categories.join(',')}');
    }

    if (contact.photo != null) {
      lines.add('PHOTO;ENCODING=b:${contact.photo}');
    }

    if (contact.revision != null) {
      lines.add('REV:${contact.revision!.toUtc().toIso8601String()}');
    }

    lines.add('END:VCARD');
    return lines.join('\r\n');
  }

  String _escape(String value) {
    return value.replaceAll('\\', '\\\\').replaceAll(',', '\\,').replaceAll(';', '\\;').replaceAll('\n', '\\n');
  }

  String _phoneLabelToVcard(String label) {
    switch (label) {
      case 'mobile':
        return 'CELL';
      case 'home':
        return 'HOME';
      case 'work':
        return 'WORK';
      default:
        return 'VOICE';
    }
  }

  String _emailLabelToVcard(String label) {
    switch (label) {
      case 'home':
        return 'HOME';
      case 'work':
        return 'WORK';
      default:
        return 'INTERNET';
    }
  }

  String _addressLabelToVcard(String label) {
    switch (label) {
      case 'home':
        return 'HOME';
      case 'work':
        return 'WORK';
      default:
        return 'OTHER';
    }
  }

  String _formatDate(DateTime date) {
    final y = date.year.toString().padLeft(4, '0');
    final m = date.month.toString().padLeft(2, '0');
    final d = date.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }
}
