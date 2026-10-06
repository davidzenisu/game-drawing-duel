import 'package:auth0_flutter/auth0_flutter_web.dart';
import 'package:auth0_flutter/auth0_flutter.dart' show Credentials;
import 'package:flutter/material.dart';

const _auth0Domain = String.fromEnvironment('AUTH0_DOMAIN');
const _auth0ClientId = String.fromEnvironment('AUTH0_CLIENT_ID');
const _isAuth0Configured = _auth0Domain != '' && _auth0ClientId != '';

void main() {
  runApp(const MainApp());
}

class MainApp extends StatefulWidget {
  const MainApp({super.key});

  @override
  State<MainApp> createState() => _MainAppState();
}

class _MainAppState extends State<MainApp> {
  int _counter = 0;
  Auth0Web? _auth0;
  Credentials? _credentials;
  String? _error;
  bool _isLoading = true;
  bool _isWorking = false;

  static const _seedColor = Color(0xFF6750A4);

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
      await _auth0!.loginWithRedirect(
        redirectUrl: Uri.base.origin,
        scopes: const {'openid', 'profile', 'email'},
      );
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

  void _incrementCounter() {
    setState(() {
      _counter++;
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: _seedColor),
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: _seedColor, brightness: Brightness.dark),
      ),
      themeMode: ThemeMode.system,
      home: Scaffold(
        appBar: AppBar(
          title: const Text('Drawing Duel'),
          centerTitle: true,
          actions: [
            if (_credentials != null)
              IconButton(
                onPressed: _isWorking ? null : _logout,
                tooltip: 'Sign out',
                icon: const Icon(Icons.logout_rounded),
              ),
          ],
        ),
        body: _buildBody(),
      ),
    );
  }

  Widget _buildBody() {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 400),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_error != null) ...[
                Text(_error!, textAlign: TextAlign.center),
                const SizedBox(height: 16),
              ],
              if (_isLoading)
                const Center(child: CircularProgressIndicator())
              else if (!_isAuth0Configured)
                const Center(child: Text('Authentication is not configured.'))
              else if (_credentials == null)
                Center(
                  child: FilledButton.icon(
                    onPressed: _isWorking ? null : _login,
                    icon: const Icon(Icons.login_rounded),
                    label: const Text('Sign in'),
                  ),
                )
              else
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.draw_rounded, size: 40, color: colorScheme.primary),
                        const SizedBox(height: 16),
                        Text('Counter', style: textTheme.titleLarge),
                        const SizedBox(height: 8),
                        Text('$_counter', style: textTheme.bodyLarge),
                        const SizedBox(height: 24),
                        FilledButton.icon(
                          onPressed: _incrementCounter,
                          icon: const Icon(Icons.add_rounded),
                          label: const Text('Increment counter'),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
