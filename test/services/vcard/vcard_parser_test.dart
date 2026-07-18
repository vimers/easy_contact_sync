import 'package:flutter_test/flutter_test.dart';
import 'package:easy_contact_sync/services/vcard/vcard_parser.dart';

// A valid 1x1 red PNG, base64-encoded.
const _photoBase64 =
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==';

String _vcard(String photoLine) => [
      'BEGIN:VCARD',
      'VERSION:3.0',
      'FN:Ada Lovelace',
      photoLine,
      'END:VCARD',
    ].join('\n');

void main() {
  final parser = VCardParser();

  group('PHOTO parsing', () {
    test('parses ENCODING=b form (vCard 3.0)', () {
      final c = parser.parse(_vcard('PHOTO;ENCODING=b:$_photoBase64'));
      expect(c.photo, _photoBase64);
    });

    test('strips vCard 4.0 data-URL prefix (PHOTO;data:image/...;base64,)', () {
      final c =
          parser.parse(_vcard('PHOTO;data:image/jpeg;base64,$_photoBase64'));
      expect(c.photo, _photoBase64);
    });

    test('strips a bare data: prefix (PHOTO:data:image/png;base64,)', () {
      final c = parser.parse(_vcard('PHOTO:data:image/png;base64,$_photoBase64'));
      expect(c.photo, _photoBase64);
    });

    test('photo is null when absent', () {
      final c = parser.parse(_vcard('NOTE:no photo here'));
      expect(c.photo, isNull);
    });
  });
}
