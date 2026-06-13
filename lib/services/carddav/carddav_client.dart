import 'dart:convert';
import 'dart:async';
import 'package:http/http.dart' as http;

/// Low-level CardDAV HTTP client handling auth and XML requests.
class CardDavHttpClient {
  final String serverUrl;
  final String username;
  final String _password;

  late final http.Client _client;

  CardDavHttpClient({
    required this.serverUrl,
    required this.username,
    required String password,
  }) : _password = password {
    _client = http.Client();
  }

  String get _authHeader =>
      'Basic ${base64Encode(utf8.encode('$username:$_password'))}';

  Map<String, String> get _headers => {
        'Authorization': _authHeader,
        'Content-Type': 'application/xml; charset=utf-8',
        'Depth': '0',
      };

  /// Send a PROPFIND request.
  Future<http.Response> propfind(String url, {String? body, String depth = '0'}) async {
    final uri = _normalizeUrl(url);
    final request = http.Request('PROPFIND', uri);
    request.headers.addAll(_headers);
    request.headers['Depth'] = depth;
    if (body != null) {
      request.body = body;
    }
    final streamed = await _client.send(request);
    return http.Response.fromStream(streamed);
  }

  /// Send a REPORT request.
  Future<http.Response> report(String url, String body, {String depth = '1'}) async {
    final uri = _normalizeUrl(url);
    final request = http.Request('REPORT', uri);
    request.headers.addAll(_headers);
    request.headers['Depth'] = depth;
    request.body = body;
    final streamed = await _client.send(request);
    return http.Response.fromStream(streamed);
  }

  /// Send a GET request.
  Future<http.Response> get(String url) async {
    final uri = _normalizeUrl(url);
    return _client.get(uri, headers: {
      'Authorization': _authHeader,
    });
  }

  /// Send a PUT request to create or update a contact.
  Future<http.Response> put(String url, String vcardBody, {String? etag}) async {
    final uri = _normalizeUrl(url);
    final headers = <String, String>{
      'Authorization': _authHeader,
      'Content-Type': 'text/vcard; charset=utf-8',
    };
    if (etag != null) {
      headers['If-Match'] = etag;
    }
    return _client.put(uri, headers: headers, body: vcardBody);
  }

  /// Send a DELETE request.
  Future<http.Response> delete(String url, {String? etag}) async {
    final uri = _normalizeUrl(url);
    final headers = <String, String>{
      'Authorization': _authHeader,
    };
    if (etag != null) {
      headers['If-Match'] = etag;
    }
    final request = http.Request('DELETE', uri);
    request.headers.addAll(headers);
    final streamed = await _client.send(request);
    return http.Response.fromStream(streamed);
  }

  /// Send a MKCOL request (create addressbook).
  Future<http.Response> mkcol(String url, String body) async {
    final uri = _normalizeUrl(url);
    final request = http.Request('MKCOL', uri);
    request.headers.addAll(_headers);
    request.body = body;
    final streamed = await _client.send(request);
    return http.Response.fromStream(streamed);
  }

  Uri _normalizeUrl(String url) {
    var normalized = url;
    if (!normalized.startsWith('http')) {
      normalized = '$serverUrl${normalized.startsWith('/') ? '' : '/'}$normalized';
    }
    return Uri.parse(normalized);
  }

  void dispose() {
    _client.close();
  }
}
