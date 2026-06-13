import 'package:xml/xml.dart';
import 'carddav_client.dart';

/// Discovers CardDAV addressbook URLs via well-known or PROPFIND.
class CardDavDiscovery {
  final CardDavHttpClient _client;

  CardDavDiscovery(this._client);

  /// Discover the principal URL from the server.
  Future<String> discoverPrincipalUrl() async {
    // Try .well-known first
    try {
      final response = await _client.propfind(
        '${_client.serverUrl}/.well-known/carddav',
        body: _principalRequestBody(),
        depth: '0',
      );
      if (response.statusCode == 207 || response.statusCode == 301 || response.statusCode == 302) {
        // Check redirect location or parse response
        if (response.headers.containsKey('location')) {
          return response.headers['location']!;
        }
        return _extractHref(response.body, 'current-user-principal');
      }
    } catch (_) {
      // well-known not supported, try direct
    }

    // Fall back to PROPFIND on server root
    final response = await _client.propfind(
      _client.serverUrl,
      body: _principalRequestBody(),
      depth: '0',
    );
    if (response.statusCode != 207) {
      throw Exception('Failed to discover principal URL: ${response.statusCode}');
    }
    return _extractHref(response.body, 'current-user-principal');
  }

  /// Discover the addressbook home URL from the principal.
  Future<String> discoverAddressbookHome(String principalUrl) async {
    final response = await _client.propfind(
      principalUrl,
      body: _addressbookHomeRequestBody(),
      depth: '0',
    );
    if (response.statusCode != 207) {
      throw Exception('Failed to discover addressbook home: ${response.statusCode}');
    }
    return _extractHref(response.body, 'addressbook-home-set');
  }

  /// List all addressbooks under the addressbook home.
  Future<List<AddressbookInfo>> discoverAddressbooks(String addressbookHomeUrl) async {
    final response = await _client.propfind(
      addressbookHomeUrl,
      body: _addressbookListRequestBody(),
      depth: '1',
    );
    if (response.statusCode != 207) {
      throw Exception('Failed to list addressbooks: ${response.statusCode}');
    }
    return _parseAddressbookList(response.body);
  }

  // ── Request bodies ──

  String _principalRequestBody() => '''<?xml version="1.0" encoding="utf-8"?>
<propfind xmlns="DAV:">
  <prop>
    <current-user-principal/>
  </prop>
</propfind>''';

  String _addressbookHomeRequestBody() => '''<?xml version="1.0" encoding="utf-8"?>
<propfind xmlns="DAV:" xmlns:C="urn:ietf:params:xml:ns:caldav">
  <prop>
    <C:calendar-home-set xmlns="urn:ietf:params:xml:ns:carddav"/>
  </prop>
</propfind>''';

  String _addressbookListRequestBody() => '''<?xml version="1.0" encoding="utf-8"?>
<propfind xmlns="DAV:" xmlns:CR="urn:ietf:params:xml:ns:carddav">
  <prop>
    <DAV:displayname/>
    <DAV:resourcetype/>
    <CR:addressbook-description/>
  </prop>
</propfind>''';

  // ── Response parsers ──

  String _extractHref(String xmlBody, String tagName) {
    final doc = XmlDocument.parse(xmlBody);
    // Search for the tag in any namespace
    final elements = doc.findAllElements(tagName);
    if (elements.isEmpty) {
      // Try without namespace - search for local name
      final allElements = doc.descendants
          .whereType<XmlElement>()
          .where((e) => e.localName == tagName);
      if (allElements.isEmpty) {
        throw Exception('Could not find $tagName in response');
      }
      final href = allElements.first.findElements('href').firstOrNull;
      if (href == null) throw Exception('No href in $tagName');
      return href.innerText;
    }
    final href = elements.first.findElements('href').firstOrNull;
    if (href == null) {
      // The element itself might contain the href text
      final text = elements.first.innerText.trim();
      if (text.isNotEmpty) return text;
      throw Exception('No href in $tagName');
    }
    return href.innerText;
  }

  List<AddressbookInfo> _parseAddressbookList(String xmlBody) {
    final doc = XmlDocument.parse(xmlBody);
    final results = <AddressbookInfo>[];

    final responses = doc.findAllElements('response');
    for (final resp in responses) {
      final hrefEl = resp.findElements('href').firstOrNull;
      if (hrefEl == null) continue;

      // Check if this is an addressbook (has addressbook resourcetype)
      final propstats = resp.findElements('propstat');
      var isAddressbook = false;
      String? displayName;

      for (final ps in propstats) {
        final props = ps.findElements('prop');
        for (final prop in props) {
          // Check resourcetype for addressbook
          final rt = prop.findElements('resourcetype').firstOrNull;
          if (rt != null) {
            final ab = rt.children.whereType<XmlElement>().where(
              (e) => e.localName == 'addressbook',
            );
            if (ab.isNotEmpty) isAddressbook = true;
          }
          // Get displayname
          final dn = prop.findElements('displayname').firstOrNull;
          if (dn != null) displayName = dn.innerText;
        }
      }

      if (isAddressbook) {
        results.add(AddressbookInfo(
          href: hrefEl.innerText,
          displayName: displayName ?? 'Contacts',
        ));
      }
    }

    return results;
  }
}

/// Info about a discovered addressbook.
class AddressbookInfo {
  final String href;
  final String displayName;

  const AddressbookInfo({required this.href, required this.displayName});
}
