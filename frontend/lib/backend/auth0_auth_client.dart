import 'package:auth0_flutter/auth0_flutter_web.dart';

import 'auth_client.dart';

/// [AuthClient] for the web, backed by Auth0 Universal Login.
class Auth0AuthClient implements AuthClient {
  Auth0AuthClient({required String domain, required String clientId, required this.audience})
    : _auth0 = Auth0Web(domain, clientId);

  /// Identifier of the Auth0 API the access tokens are for.
  final String audience;
  final Auth0Web _auth0;

  static const _scopes = {'openid', 'profile', 'email'};

  @override
  Future<AuthProfile?> restore() async {
    final credentials = await _auth0.onLoad(audience: audience, scopes: _scopes);
    if (credentials == null) return null;
    final user = credentials.user;
    return AuthProfile(givenName: user.givenName, name: user.name, nickname: user.nickname);
  }

  @override
  Future<void> signIn({bool fresh = false}) => _auth0.loginWithRedirect(
    audience: audience,
    redirectUrl: Uri.base.origin,
    scopes: _scopes,
    parameters: fresh ? const {'prompt': 'login'} : const {},
  );

  @override
  Future<void> signOut() => _auth0.logout(returnToUrl: Uri.base.origin);

  @override
  Future<String> accessToken() async => (await _auth0.credentials(audience: audience)).accessToken;
}
