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

/// The sign-in can't be used (any more): no token, or the backend rejected it.
class SignInRequired implements Exception {
  const SignInRequired(this.message);

  final String message;

  @override
  String toString() => message;
}

/// JSON calls to the backend, authenticated with the signed-in account.
///
/// Throws [SignInRequired] when the sign-in is the problem, [ApiException] for
/// other rejected requests.
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

  Future<Object?> post(String path, [Object? body]) => _send('POST', path, body: body);

  Future<Object?> _send(String method, String path, {Object? body}) async {
    final String token;
    try {
      token = await auth.accessToken();
    } catch (error) {
      throw SignInRequired('Your sign-in expired ($error).');
    }
    final request = http.Request(method, Uri.parse('$_baseUrl$path'))
      ..headers['Authorization'] = 'Bearer $token'
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
      if (response.statusCode == 401 || (detail?.startsWith('Missing permission') ?? false)) {
        throw SignInRequired('The server rejected your sign-in: ${detail ?? 'status ${response.statusCode}'}.');
      }
      throw ApiException(response.statusCode, detail ?? 'Request failed with status ${response.statusCode}.');
    }
    return decoded;
  }
}
