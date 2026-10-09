import 'dart:convert';

import 'package:http/http.dart' as http;

import 'auth_client.dart';

/// A request the backend rejected.
class ApiException implements Exception {
  const ApiException(this.statusCode, this.message);

  final int statusCode;
  final String message;

  @override
  String toString() => message;
}

/// JSON calls to the backend, authenticated with the signed-in account.
class ApiClient {
  ApiClient({required String baseUrl, required this.auth, http.Client? httpClient})
    : _baseUrl = baseUrl.trim().replaceFirst(RegExp(r'/+$'), ''),
      _http = httpClient ?? http.Client();

  final String _baseUrl;
  final AuthClient auth;
  final http.Client _http;

  static const _timeout = Duration(seconds: 20);

  Future<Object?> get(String path) => _send('GET', path);

  Future<Object?> put(String path, Object body) => _send('PUT', path, body: body);

  Future<Object?> _send(String method, String path, {Object? body}) async {
    final request = http.Request(method, Uri.parse('$_baseUrl$path'))
      ..headers['Authorization'] = 'Bearer ${await auth.accessToken()}'
      ..headers['Accept'] = 'application/json';
    if (body != null) {
      request
        ..headers['Content-Type'] = 'application/json'
        ..body = jsonEncode(body);
    }
    final response = await http.Response.fromStream(await _http.send(request).timeout(_timeout));
    final decoded = response.body.isEmpty ? null : jsonDecode(response.body);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final detail = decoded is Map && decoded['detail'] is String ? decoded['detail'] as String : null;
      throw ApiException(response.statusCode, detail ?? 'Request failed with status ${response.statusCode}.');
    }
    return decoded;
  }
}
