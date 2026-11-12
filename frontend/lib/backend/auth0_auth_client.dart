import 'package:auth0_flutter/auth0_flutter_web.dart';

import 'auth_client.dart';

/// [AuthClient] for the web, backed by Auth0 Universal Login.
///
/// Tokens are renewed with refresh tokens kept in local storage, so the
/// sign-in survives reloads (e.g. a phone discarding a background tab) and
/// doesn't depend on Auth0's hidden iframe, which browsers blocking
/// third-party cookies (Brave, Safari) never answer: renewing then failed
/// with "Timeout" and asked to sign in again. Until the Auth0 application
/// issues refresh tokens (rotation on, offline access allowed for the API),
/// renewal falls back to the iframe, as before.
class Auth0AuthClient implements AuthClient {
  Auth0AuthClient({required String domain, required String clientId, required this.audience})
    : _auth0 = Auth0Web(domain, clientId, cacheLocation: CacheLocation.localStorage);

  /// Identifier of the Auth0 API the access tokens are for.
  final String audience;
  final Auth0Web _auth0;

  /// `offline_access` asks for a refresh token.
  static const _scopes = {'openid', 'profile', 'email', 'offline_access'};

  @override
  Future<AuthProfile?> restore() async {
    final credentials = await _auth0.onLoad(
      audience: audience,
      scopes: _scopes,
      useRefreshTokens: true,
      // Without a refresh token yet (e.g. a sign-in from before), the iframe.
      useRefreshTokensFallback: true,
    );
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
