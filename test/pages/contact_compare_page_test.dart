import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:easy_contact_sync/models/contact.dart';
import 'package:easy_contact_sync/pages/contact_compare_page.dart';
import 'package:easy_contact_sync/widgets/contact_photo.dart';

// Two distinct, valid 1x1 PNGs so the two sides render different images.
const _imgA =
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==';
const _imgB =
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+M8AAAMBAQDJ/pLvAAAAAElFTkSuQmCC';

Widget _wrap(Widget child) => MaterialApp(home: child);

void main() {
  testWidgets('shows Photo card when photos differ', (tester) async {
    await tester.pumpWidget(_wrap(const ContactComparePage(
      localContact: Contact(displayName: 'Alice', photo: _imgA),
      remoteContact: Contact(displayName: 'Alice', photo: _imgB),
    )));
    expect(find.text('Photo'), findsOneWidget);
    expect(find.text('Local'), findsOneWidget);
    expect(find.text('Remote'), findsOneWidget);
    expect(find.byType(ContactPhoto), findsNWidgets(2));
  });

  testWidgets('hides Photo card when photos are equal', (tester) async {
    await tester.pumpWidget(_wrap(const ContactComparePage(
      localContact: Contact(displayName: 'Alice', photo: _imgA),
      remoteContact: Contact(displayName: 'Alice', photo: _imgA),
    )));
    expect(find.text('Photo'), findsNothing);
  });

  testWidgets('hides Photo card when both photos are null', (tester) async {
    await tester.pumpWidget(_wrap(const ContactComparePage(
      localContact: Contact(displayName: 'Alice'),
      remoteContact: Contact(displayName: 'Alice'),
    )));
    expect(find.text('Photo'), findsNothing);
  });

  testWidgets('shows a no-photo placeholder on the side without a photo', (tester) async {
    await tester.pumpWidget(_wrap(const ContactComparePage(
      localContact: Contact(displayName: 'Alice', photo: _imgA),
      remoteContact: Contact(displayName: 'Alice'),
    )));
    expect(find.text('Photo'), findsOneWidget);
    // Only the local side has a decodable photo.
    expect(find.byType(ContactPhoto), findsOneWidget);
    // The empty side shows the person placeholder icon.
    expect(find.byIcon(Icons.person), findsOneWidget);
  });

  testWidgets('tapping an avatar opens a full-screen view', (tester) async {
    await tester.pumpWidget(_wrap(const ContactComparePage(
      localContact: Contact(displayName: 'Alice', photo: _imgA),
      remoteContact: Contact(displayName: 'Alice', photo: _imgB),
    )));
    await tester.tap(find.byType(ContactPhoto).first);
    await tester.pumpAndSettle();
    expect(find.byType(Dialog), findsOneWidget);
  });
}
