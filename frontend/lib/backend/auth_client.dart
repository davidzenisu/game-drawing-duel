/// The profile of the signed-in account, as the identity provider reports it.
class AuthProfile {
  const AuthProfile({this.givenName, this.name, this.nickname});

  final String? givenName;
  final String? name;
  final String? nickname;

  /// The best guess for a first name.
  String get firstName {
    for (final candidate in [givenName, name?.split(' ').first, nickname]) {
      if (candidate != null && candidate.trim().isNotEmpty) return candidate.trim();
    }
    return '';
  }
}

/// Signing in with the identity provider and handing out access tokens.
abstract class AuthClient {
  /// Restores a previous sign-in, or returns `null` if there is none.
  Future<AuthProfile?> restore();

  /// Starts the sign-in, which may leave the app (redirect).
  Future<void> signIn();

  /// Ends the sign-in, which may leave the app (redirect).
  Future<void> signOut();

  /// A valid access token for the backend.
  Future<String> accessToken();
}
