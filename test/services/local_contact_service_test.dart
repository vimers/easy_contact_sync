import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_contacts/flutter_contacts.dart' as fc;
import 'package:easy_contact_sync/models/contact.dart';
import 'package:easy_contact_sync/services/local_contact_service.dart';

// A valid 1x1 red PNG, base64-encoded.
const _pngBase64 =
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==';

void main() {
  final svc = LocalContactService();

  group('photo propagation to flutter_contacts', () {
    test('toFlutterContact writes the decoded photo bytes', () {
      const c = Contact(displayName: 'Ada', photo: _pngBase64);
      final fc1 = svc.toFlutterContact(c);
      expect(fc1.photo, isNotNull);
      expect(fc1.photo, equals(base64Decode(_pngBase64)));
    });

    test('toFlutterContact leaves photo null when the contact has none', () {
      expect(svc.toFlutterContact(const Contact(displayName: 'Ada')).photo,
          isNull);
    });

    test('toFlutterContact ignores a non-base64 (URL) photo value', () {
      const c = Contact(displayName: 'Ada', photo: 'https://example.com/p.png');
      expect(svc.toFlutterContact(c).photo, isNull);
    });

    test('mergeIntoFlutterContact writes the remote photo onto the local copy',
        () {
      final existing = fc.Contact(name: fc.Name(first: 'old'));
      svc.mergeIntoFlutterContact(
          existing, const Contact(displayName: 'Ada', photo: _pngBase64));
      expect(existing.photo, equals(base64Decode(_pngBase64)));
    });

    test(
        'mergeIntoFlutterContact keeps an existing local photo when remote has none',
        () {
      final existing = fc.Contact(name: fc.Name(first: 'old'));
      existing.photo = base64Decode(_pngBase64);
      svc.mergeIntoFlutterContact(existing, const Contact(displayName: 'Ada'));
      // Must NOT be cleared just because the remote contact carries no photo.
      expect(existing.photo, equals(base64Decode(_pngBase64)));
    });
  });
}
