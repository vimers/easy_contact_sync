import 'package:xml/xml.dart';
import 'carddav_client.dart';
import '../vcard/vcard_parser.dart';
import '../vcard/vcard_writer.dart';
import '../../models/contact.dart';

/// High-level CardDAV CRUD operations.
class CardDavOperations {
  final CardDavHttpClient _client;
  final VCardParser _parser = VCardParser();

  CardDavOperations(this._client);

  /// Fetch all contacts from an addressbook (full sync).
  /// Uses PROPFIND first (most compatible), falls back to REPORT.
  Future<List<Contact>> listContacts(String addressbookUrl) async {
    // Strategy 1: PROPFIND depth 1 to get href+etag, then GET each vCard
    try {
      return await _listContactsViaPropfind(addressbookUrl);
    } catch (_) {
      // Strategy 2: REPORT with addressbook-query
      try {
        return await _listContactsViaReport(addressbookUrl);
      } catch (_) {
        // Strategy 3: PROPFIND depth infinity fallback
        return await _listContactsViaPropfindDeep(addressbookUrl);
      }
    }
  }

  /// List contacts via PROPFIND depth 1 + individual GETs.
  Future<List<Contact>> _listContactsViaPropfind(String addressbookUrl) async {
    final body = '''<?xml version="1.0" encoding="utf-8"?>
<propfind xmlns="DAV:">
  <prop>
    <getetag/>
    <resourcetype/>
  </prop>
</propfind>''';

    final response = await _client.propfind(addressbookUrl, body: body, depth: '1');
    if (response.statusCode != 207) {
      throw Exception('PROPFIND failed: ${response.statusCode}');
    }

    // Parse href + etag pairs from the PROPFIND response, filter to .vcf only.
    final doc = XmlDocument.parse(response.body);
    final pairs = <({String href, String? etag})>[];
    for (final resp in doc.findAllElements('response')) {
      final href = resp.findElements('href').firstOrNull?.innerText;
      if (href == null || !href.toLowerCase().endsWith('.vcf')) continue;
      String? etag;
      for (final ps in resp.findElements('propstat')) {
        final status = ps.findElements('status').firstOrNull;
        if (status != null && !status.innerText.contains('200')) continue;
        final etagEl = ps.findElements('prop').firstOrNull?.findElements('getetag').firstOrNull;
        if (etagEl != null) etag = etagEl.innerText;
      }
      pairs.add((href: href, etag: etag));
    }

    // GET each contact's vCard, attach the PROPFIND etag.
    final contacts = <Contact>[];
    for (final p in pairs) {
      try {
        final contact = await getContact(p.href);
        contacts.add(contact.copyWith(etag: contact.etag ?? p.etag));
      } catch (_) {
        // Skip individual failures
      }
    }
    return contacts;
  }

  /// List contacts via REPORT addressbook-query.
  Future<List<Contact>> _listContactsViaReport(String addressbookUrl) async {
    final body = '''<?xml version="1.0" encoding="utf-8"?>
<C:addressbook-query xmlns:D="DAV:" xmlns:C="urn:ietf:params:xml:ns:carddav">
  <D:prop>
    <D:getetag/>
    <C:address-data/>
  </D:prop>
</C:addressbook-query>''';

    final response = await _client.report(addressbookUrl, body, depth: '1');
    if (response.statusCode != 207) {
      throw Exception('Failed to list contacts: ${response.statusCode}');
    }
    return _parseContactResponse(response.body);
  }

  /// Deep PROPFIND that tries to get address-data inline.
  Future<List<Contact>> _listContactsViaPropfindDeep(String addressbookUrl) async {
    final body = '''<?xml version="1.0" encoding="utf-8"?>
<propfind xmlns="DAV:" xmlns:CR="urn:ietf:params:xml:ns:carddav">
  <prop>
    <getetag/>
    <CR:address-data/>
    <resourcetype/>
  </prop>
</propfind>''';

    final response = await _client.propfind(addressbookUrl, body: body, depth: '1');
    if (response.statusCode != 207) {
      throw Exception('Failed to list contacts: ${response.statusCode}');
    }
    return _parseContactResponse(response.body);
  }

  /// Fetch only changed contacts since a sync token (incremental sync).
  Future<SyncCollectionResult> syncCollection(
    String addressbookUrl, {
    String? syncToken,
  }) async {
    final body = '''<?xml version="1.0" encoding="utf-8"?>
<sync-collection xmlns="DAV:">
  <sync-token>${syncToken ?? ''}</sync-token>
  <prop>
    <getetag/>
    <address-data xmlns="urn:ietf:params:xml:ns:carddav"/>
  </prop>
</sync-collection>''';

    final response = await _client.report(addressbookUrl, body, depth: '0');
    if (response.statusCode != 207) {
      // If sync-token is invalid, fall back to full sync
      if (response.statusCode == 403 || response.statusCode == 409) {
        throw SyncTokenInvalidException();
      }
      throw Exception('sync-collection failed: ${response.statusCode}');
    }

    final contacts = _parseContactResponse(response.body);
    final newSyncToken = _extractSyncToken(response.body);
    final deletedHrefs = _extractDeletedHrefs(response.body);

    return SyncCollectionResult(
      contacts: contacts,
      syncToken: newSyncToken,
      deletedHrefs: deletedHrefs,
    );
  }

  /// Get a single contact by its href.
  Future<Contact> getContact(String href) async {
    final response = await _client.get(href);
    if (response.statusCode != 200) {
      throw Exception('Failed to get contact: ${response.statusCode}');
    }
    final contact = _parser.parse(response.body);
    // Capture the etag from the GET response when the server provides it.
    return contact.copyWith(href: href, etag: contact.etag ?? response.headers['etag']);
  }

  /// Create a new contact on the server. Returns the created contact with href/etag.
  Future<Contact> createContact(String addressbookUrl, Contact contact) async {
    final writer = VCardWriter();
    final vcard = writer.write(contact);
    final uid = contact.uid ?? _generateUid();
    final href = '$addressbookUrl/${uid}.vcf';

    final response = await _client.put(href, vcard);
    if (response.statusCode != 201 && response.statusCode != 204) {
      throw Exception('Failed to create contact: ${response.statusCode}');
    }

    return contact.copyWith(
      uid: uid,
      href: href,
      etag: response.headers['etag'],
    );
  }

  /// Update an existing contact.
  ///
  /// [force]: send `If-Match: *` (overwrite the current version) instead of the
  /// stored etag. Use when the caller knows it wants to overwrite regardless of
  /// the server's current version — e.g. conflict resolution where the user
  /// explicitly chose a side.
  Future<Contact> updateContact(Contact contact, {bool force = false}) async {
    if (contact.href == null) throw Exception('Contact href is required for update');

    final writer = VCardWriter();
    final vcard = writer.write(contact);

    final response = await _client.put(
      contact.href!,
      vcard,
      etag: force ? '*' : contact.etag,
    );
    if (response.statusCode != 204 && response.statusCode != 200) {
      // SYNC-DIAG: capture the vCard body + server explanation if it still fails.
      // ignore: avoid_print
      print('SYNC-DIAG putFail href=${contact.href} sentEtag=${contact.etag} '
          'vcard=${vcard.length > 400 ? vcard.substring(0, 400) : vcard} '
          'status=${response.statusCode} body=${response.body.length > 400 ? response.body.substring(0, 400) : response.body}');
      throw Exception('Failed to update contact: ${response.statusCode}');
    }

    return contact.copyWith(
      etag: response.headers['etag'],
    );
  }

  /// Delete a contact from the server. A 404 (already gone) is treated as success.
  Future<void> deleteContact(Contact contact) async {
    if (contact.href == null) throw Exception('Contact href is required for delete');

    final response = await _client.delete(contact.href!, etag: contact.etag);
    if (response.statusCode != 204 && response.statusCode != 200 && response.statusCode != 404) {
      throw Exception('Failed to delete contact: ${response.statusCode}');
    }
  }

  /// Fetch the current etag of a contact resource via PROPFIND depth 0. Used to
  /// get a fresh, server-authoritative etag before an update (some servers
  /// reject updates without a matching If-Match etag).
  Future<String?> fetchEtag(String href) async {
    final body = '''<?xml version="1.0" encoding="utf-8"?>
<propfind xmlns="DAV:">
  <prop>
    <getetag/>
  </prop>
</propfind>''';
    final response = await _client.propfind(href, body: body, depth: '0');
    if (response.statusCode != 207) return null;
    final doc = XmlDocument.parse(response.body);
    for (final resp in doc.findAllElements('response')) {
      for (final ps in resp.findElements('propstat')) {
        final status = ps.findElements('status').firstOrNull;
        if (status != null && !status.innerText.contains('200')) continue;
        final etagEl = ps.findElements('prop').firstOrNull?.findElements('getetag').firstOrNull;
        if (etagEl != null) return etagEl.innerText;
      }
    }
    return null;
  }

  // ── Internal helpers ──

  List<Contact> _parseContactResponse(String xmlBody) {
    final doc = XmlDocument.parse(xmlBody);
    final results = <Contact>[];
    final responses = doc.findAllElements('response');

    for (final resp in responses) {
      final hrefEl = resp.findElements('href').firstOrNull;
      if (hrefEl == null) continue;
      final href = hrefEl.innerText;

      String? etag;
      String? vcardData;

      final propstats = resp.findElements('propstat');
      for (final ps in propstats) {
        final status = ps.findElements('status').firstOrNull;
        if (status != null && !status.innerText.contains('200')) continue;

        final props = ps.findElements('prop');
        for (final prop in props) {
          final etagEl = prop.findElements('getetag').firstOrNull;
          if (etagEl != null) etag = etagEl.innerText;

          // address-data can be in carddav namespace
          final ad = prop.children.whereType<XmlElement>().where(
            (e) => e.localName == 'address-data',
          ).firstOrNull;
          if (ad != null) vcardData = ad.innerText;
        }
      }

      if (vcardData != null) {
        final contact = _parser.parse(vcardData);
        results.add(contact.copyWith(href: href, etag: etag));
      }
    }

    return results;
  }

  String? _extractSyncToken(String xmlBody) {
    final doc = XmlDocument.parse(xmlBody);
    final tokens = doc.descendants
        .whereType<XmlElement>()
        .where((e) => e.localName == 'sync-token');
    if (tokens.isEmpty) return null;
    return tokens.first.innerText;
  }

  List<String> _extractDeletedHrefs(String xmlBody) {
    final doc = XmlDocument.parse(xmlBody);
    final hrefs = <String>[];
    final responses = doc.findAllElements('response');

    for (final resp in responses) {
      final status = resp.findElements('propstat').firstOrNull
          ?.findElements('status').firstOrNull;
      if (status != null && status.innerText.contains('404')) {
        final href = resp.findElements('href').firstOrNull?.innerText;
        if (href != null) hrefs.add(href);
      }
    }
    return hrefs;
  }

  String _generateUid() {
    final timestamp = DateTime.now().millisecondsSinceEpoch.toRadixString(36);
    final random = List.generate(8, (_) => 'abcdefghijklmnopqrstuvwxyz0123456789'[DateTime.now().microsecond % 36]).join();
    return '$timestamp-$random';
  }
}

/// Result of a sync-collection REPORT.
class SyncCollectionResult {
  final List<Contact> contacts;
  final String? syncToken;
  final List<String> deletedHrefs;

  const SyncCollectionResult({
    required this.contacts,
    this.syncToken,
    this.deletedHrefs = const [],
  });
}

/// Thrown when a sync token is no longer valid.
class SyncTokenInvalidException implements Exception {}
