import 'dart:convert';

import 'package:auth0_flutter/auth0_flutter_web.dart';
import 'package:auth0_flutter/auth0_flutter.dart' show Credentials;
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'feature_flags.dart';
import 'game/game_app.dart';
import 'mockup/mock_game_session.dart';
import 'theme/app_theme.dart';

const _auth0Domain = String.fromEnvironment('AUTH0_DOMAIN');
const _auth0ClientId = String.fromEnvironment('AUTH0_CLIENT_ID');
const _apiUrl = String.fromEnvironment('API_URL');
const _isAuth0Configured = _auth0Domain != '' && _auth0ClientId != '';

void main() {
  runApp(FeatureFlags.mockupGameplay ? GameApp(session: MockGameSession()) : const MainApp());
}

class MainApp extends StatefulWidget {
  const MainApp({super.key});

  @override
  State<MainApp> createState() => _MainAppState();
}

class _MainAppState extends State<MainApp> {
  Auth0Web? _auth0;
  Credentials? _credentials;
  String? _error;
  String? _drawingsError;
  List<_DrawingItem> _drawings = [];
  bool _isLoading = true;
  bool _isWorking = false;
  bool _isDrawingsLoading = false;

  @override
  void initState() {
    super.initState();
    if (_isAuth0Configured) {
      _auth0 = Auth0Web(_auth0Domain, _auth0ClientId);
      _restoreSession();
    } else {
      _isLoading = false;
    }
  }

  Future<void> _restoreSession() async {
    try {
      final credentials = await _auth0!.onLoad();
      if (!mounted) return;
      setState(() {
        _credentials = credentials;
        _isLoading = false;
      });
      if (credentials != null) await _loadDrawings();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.toString();
        _isLoading = false;
      });
    }
  }

  Future<void> _login() async {
    setState(() {
      _isWorking = true;
      _error = null;
    });
    try {
      await _auth0!.loginWithRedirect(redirectUrl: Uri.base.origin, scopes: const {'openid', 'profile', 'email'});
      if (!mounted) return;
      setState(() => _isWorking = false);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.toString();
        _isWorking = false;
      });
    }
  }

  Future<void> _logout() async {
    setState(() {
      _isWorking = true;
      _error = null;
    });
    try {
      await _auth0!.logout(returnToUrl: Uri.base.origin);
      if (!mounted) return;
      setState(() {
        _credentials = null;
        _drawings = [];
        _drawingsError = null;
        _isWorking = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.toString();
        _isWorking = false;
      });
    }
  }

  Future<void> _loadDrawings() async {
    if (_apiUrl.trim().isEmpty) {
      setState(() {
        _drawingsError = 'API_URL is not configured.';
        _isDrawingsLoading = false;
      });
      return;
    }

    setState(() {
      _isDrawingsLoading = true;
      _drawingsError = null;
    });

    try {
      final apiBaseUrl = _apiUrl.trim().replaceFirst(RegExp(r'/+$'), '');
      final response = await http.get(Uri.parse('$apiBaseUrl/drawings')).timeout(const Duration(seconds: 20));
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Exception('Request failed with status ${response.statusCode}.');
      }

      final responseBody = jsonDecode(response.body);
      if (responseBody is! List) {
        throw const FormatException('The drawings response must be a JSON array.');
      }

      final drawings = responseBody
          .map((item) {
            if (item is! Map<String, dynamic>) {
              throw const FormatException('A drawing item must be a JSON object.');
            }
            return _DrawingItem.fromJson(item);
          })
          .toList(growable: false);

      if (!mounted) return;
      setState(() {
        _drawings = drawings;
        _isDrawingsLoading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _drawingsError = error.toString();
        _isDrawingsLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: ThemeMode.system,
      home: Scaffold(
        appBar: AppBar(
          title: const Text('Drawing Duel'),
          centerTitle: true,
          actions: [
            if (_credentials != null) ...[
              IconButton(
                onPressed: _isDrawingsLoading ? null : _loadDrawings,
                tooltip: 'Refresh drawings',
                icon: const Icon(Icons.refresh_rounded),
              ),
              IconButton(
                onPressed: _isWorking ? null : _logout,
                tooltip: 'Sign out',
                icon: const Icon(Icons.logout_rounded),
              ),
            ],
          ],
        ),
        body: _buildBody(),
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading) return const Center(child: CircularProgressIndicator());
    if (!_isAuth0Configured) {
      return const Center(child: Text('Authentication is not configured.'));
    }
    if (_credentials == null) return _buildSignIn();
    return _buildDrawings();
  }

  Widget _buildSignIn() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_error != null) ...[
            Padding(
              padding: const EdgeInsets.all(24),
              child: Text(_error!, textAlign: TextAlign.center),
            ),
          ],
          FilledButton.icon(
            onPressed: _isWorking ? null : _login,
            icon: const Icon(Icons.login_rounded),
            label: const Text('Sign in'),
          ),
        ],
      ),
    );
  }

  Widget _buildDrawings() {
    if (_isDrawingsLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_drawingsError != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_drawingsError!, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: _loadDrawings,
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }
    if (_drawings.isEmpty) {
      return const Center(child: Text('No drawings found.'));
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 900),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              columns: const [
                DataColumn(label: Text('ID'), numeric: true),
                DataColumn(label: Text('Description')),
              ],
              rows: _drawings
                  .map(
                    (drawing) =>
                        DataRow(cells: [DataCell(Text(drawing.id.toString())), DataCell(Text(drawing.description))]),
                  )
                  .toList(growable: false),
            ),
          ),
        ),
      ),
    );
  }
}

class _DrawingItem {
  const _DrawingItem({required this.id, required this.description});

  final int id;
  final String description;

  factory _DrawingItem.fromJson(Map<String, dynamic> json) {
    final id = json['id'];
    final description = json['description'];
    if (id is! int || description is! String) {
      throw const FormatException('Each drawing must have an integer id and a string description.');
    }
    return _DrawingItem(id: id, description: description);
  }
}
