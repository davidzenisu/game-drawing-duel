import 'dart:convert';

import 'package:frontend/backend/auth_client.dart';
import 'package:frontend/game/rules/models.dart';
import 'package:frontend/game/rules/setup_plan.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

class FakeAuthClient implements AuthClient {
  FakeAuthClient({this.profile, this.token = 'test-token', this.restoreError, this.tokenError});

  AuthProfile? profile;
  final String token;
  final Object? restoreError;
  Object? tokenError;
  int signIns = 0;

  /// Whether each sign-in asked for a fresh login.
  final List<bool> freshSignIns = [];
  int signOuts = 0;

  @override
  Future<AuthProfile?> restore() async {
    if (restoreError != null) throw restoreError!;
    return profile;
  }

  @override
  Future<void> signIn({bool fresh = false}) async {
    signIns++;
    freshSignIns.add(fresh);
  }

  @override
  Future<void> signOut() async => signOuts++;

  @override
  Future<String> accessToken() async {
    if (tokenError != null) throw tokenError!;
    return token;
  }
}

/// An in-memory stand-in for the API. Callers are told apart by their token.
class FakeBackend {
  /// Players by token: `{'id': 7, 'first_name': 'Pat'}`.
  final Map<String, Map<String, Object?>> players = {};

  /// Servers by code; every seat has a `name` and the `player` id or null.
  final Map<String, ({int admin, bool isTest, List<Map<String, Object?>> seats})> servers = {};

  /// Codes of the servers whose setup started.
  final Set<String> started = {};

  /// Seat positions that finished their setup, by server code.
  final Map<String, Set<int>> finished = {};

  /// Codes of the servers that launched.
  final Set<String> launched = {};

  /// Setup drawings by server code and assignment id: the character as the
  /// API returns it and the uploaded sketch.
  final Map<(String, int), ({Map<String, Object?> character, Object? sketch})> drawings = {};
  int _nextCharacter = 1;
  final List<http.Request> requests = [];

  /// Rejects every request with this status and detail, like the real API
  /// does for a bad token.
  ({int status, String detail})? rejectAll;
  int _nextCode = 123456;

  MockClient get client => MockClient((request) async {
    requests.add(request);
    if (rejectAll != null) return _json(rejectAll!.status, {'detail': rejectAll!.detail});
    final token = (request.headers['Authorization'] ?? '').replaceFirst('Bearer ', '');
    final path = request.url.pathSegments;
    final me = players[token];
    final body = request.body.isEmpty ? null : jsonDecode(request.body) as Map<String, Object?>;

    if (request.url.path == '/me') {
      if (request.method == 'PUT') {
        players[token] = {'id': me?['id'] ?? players.length + 1, 'first_name': body!['first_name']};
        return _json(200, {...players[token]!, 'created_at': '2026-10-09T10:00:00Z'});
      }
      return me == null ? _json(404, {'detail': 'Not signed up yet'}) : _json(200, me);
    }
    if (me == null) return _json(403, {'detail': 'Finish signing up first'});
    final myId = me['id'] as int;

    if (request.method == 'POST' && request.url.path == '/servers') {
      final code = '${_nextCode++}';
      servers[code] = (
        admin: myId,
        isTest: body!['is_test'] as bool? ?? false,
        seats: [
          {'name': me['first_name'], 'player': myId},
          for (final name in body['other_names'] as List) {'name': name, 'player': null},
        ],
      );
      return _json(201, _server(code, myId));
    }
    if (request.method == 'GET' && request.url.path == '/servers/mine') {
      final mine = servers.keys.where((c) => servers[c]!.seats.any((s) => s['player'] == myId)).toList().reversed;
      return _json(200, [for (final code in mine) _server(code, myId)]);
    }
    if (path.length >= 2 && path[0] == 'servers' && servers.containsKey(path[1])) {
      final code = path[1];
      if (request.method == 'GET' && path.length == 2) return _json(200, _server(code, myId));
      if (request.method == 'DELETE' && path.length == 2) {
        if (!servers[code]!.seats.any((s) => s['player'] == myId)) {
          return _json(403, {'detail': "You haven't joined this server"});
        }
        servers.remove(code);
        started.remove(code);
        drawings.removeWhere((key, _) => key.$1 == code);
        return http.Response('', 204);
      }
      if (request.method == 'POST' && path.length == 5 && path[4] == 'claim') {
        final seats = servers[code]!.seats;
        final seat = seats[int.parse(path[3])];
        if (seat['player'] != null) return _json(409, {'detail': 'This seat is taken'});
        if (seats.any((s) => s['player'] == myId)) return _json(409, {'detail': 'You already joined this server'});
        seat['player'] = myId;
        return _json(200, _server(code, myId));
      }
      if (request.method == 'POST' && path.length == 3 && path[2] == 'setup') {
        final server = servers[code]!;
        if (server.admin != myId) return _json(403, {'detail': 'Only the admin can start the setup'});
        if (!server.isTest && server.seats.any((s) => s['player'] == null)) {
          return _json(409, {'detail': 'Not everyone joined yet'});
        }
        if (!started.add(code)) return _json(409, {'detail': 'The setup already started'});
        return _json(200, _server(code, myId));
      }
      if (request.method == 'POST' && path.length == 4 && path[2] == 'setup' && path[3] == 'done') {
        final seats = servers[code]!.seats;
        final done = finished.putIfAbsent(code, () => {})..add(seats.indexWhere((s) => s['player'] == myId));
        final artists = [
          for (final (i, s) in seats.indexed)
            if (!servers[code]!.isTest || s['player'] != null) i,
        ];
        if (artists.every(done.contains)) launched.add(code);
        return _json(200, _server(code, myId));
      }
      if (request.method == 'GET' && path.length == 3 && (path[2] == 'pool' || path[2] == 'collection')) {
        final yours = servers[code]!.seats.indexWhere((s) => s['player'] == myId);
        return _json(200, [
          for (final MapEntry(:key, :value) in drawings.entries)
            if (key.$1 == code && (path[2] == 'pool' || value.character['artist_position'] == yours)) value.character,
        ]);
      }
      if (request.method == 'GET' && path.length == 3 && path[2] == 'assignments') {
        return _json(200, [
          for (final a in _assignments(code, myId)) {...a, 'character': drawings[(code, a['id'] as int)]?.character},
        ]);
      }
      if (request.method == 'PUT' && path.length == 5 && path[4] == 'drawing') {
        final assignment = _assignments(code, myId).firstWhere((a) => '${a['id']}' == path[3]);
        final prompt = SetupPrompt.values.byName(assignment['prompt'] as String);
        final character = {
          'id': 'character-${_nextCharacter++}',
          'title': (body!['title'] as String).trim(),
          'rarity': prompt.rarity.name,
          'prompt': prompt.name,
          'artist_position': servers[code]!.seats.indexWhere((s) => s['player'] == myId),
          'subject_position': assignment['subject_position'],
        };
        drawings[(code, assignment['id'] as int)] = (character: character, sketch: body['sketch']);
        return _json(200, character);
      }
    }
    if (request.method == 'GET' && path.length == 3 && path[0] == 'characters' && path[2] == 'sketch') {
      final drawing = drawings.values.where((d) => d.character['id'] == path[1]).firstOrNull;
      return drawing == null ? _json(404, {'detail': 'No such character'}) : _json(200, drawing.sketch);
    }
    return _json(404, {'detail': 'No server with this code'});
  });

  Map<String, Object?> _server(String code, int playerId) {
    final server = servers[code]!;
    final yours = server.seats.indexWhere((s) => s['player'] == playerId);
    return {
      'code': code,
      'created_at': '2026-10-09T10:00:00Z',
      'is_test': server.isTest,
      'is_admin': server.admin == playerId,
      'phase': launched.contains(code)
          ? 'running'
          : started.contains(code)
          ? 'setup'
          : 'lobby',
      'your_position': yours < 0 ? null : yours,
      'seats': [
        for (final (i, s) in server.seats.indexed)
          {
            'position': i,
            'name': s['name'],
            'joined': s['player'] != null,
            'setup_done': finished[code]?.contains(i) ?? false,
          },
      ],
    };
  }

  /// Planned like the real API does, with ids made up from seat and prompt.
  List<Map<String, Object?>> _assignments(String code, int playerId) {
    final server = servers[code]!;
    final seats = [
      for (final (i, s) in server.seats.indexed)
        if (!server.isTest || s['player'] != null) Player(id: '$i', name: s['name'] as String),
    ];
    final artist = seats.indexWhere((p) => server.seats[int.parse(p.id)]['player'] == playerId);
    final planned = server.isTest
        ? SetupPlan.testAssignmentsFor(seats, artist)
        : SetupPlan.assignmentsFor(seats, artist);
    int id(DrawingAssignment a) => int.parse(seats[artist].id) * 10 + a.prompt.index;
    return [
      for (final a in planned)
        {
          'id': id(a),
          'prompt': a.prompt.name,
          'subject_position': int.parse(a.subject.id),
          'based_on': a.basedOn == null ? null : id(planned.firstWhere((b) => b.id == a.basedOn)),
        },
    ];
  }

  static http.Response _json(int status, Object? body) =>
      http.Response(jsonEncode(body), status, headers: {'content-type': 'application/json'});
}
