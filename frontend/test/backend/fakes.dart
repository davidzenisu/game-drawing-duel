import 'dart:convert';
import 'dart:math';

import 'package:frontend/backend/auth_client.dart';
import 'package:frontend/game/rules/models.dart';
import 'package:frontend/game/rules/setup_plan.dart';
import 'package:frontend/game/rules/upgrades.dart';
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
  /// Players by token: `{'id': 'player-uuid-7', 'first_name': 'Pat'}`.
  final Map<String, Map<String, Object?>> players = {};

  /// Servers by code; every seat has a `name` and the `player` id or null.
  final Map<String, ({String admin, bool isTest, List<Map<String, Object?>> seats})> servers = {};

  /// Codes of the servers whose setup started.
  final Set<String> started = {};

  /// Seat positions that finished their setup, by server code.
  final Map<String, Set<int>> finished = {};

  /// Codes of the servers that launched.
  final Set<String> launched = {};

  /// Pulled character ids by server code and player id; everyone gets
  /// [launchBonus] pulls at the launch.
  final Map<(String, String), List<String>> pulls = {};
  static const launchBonus = 10;

  /// The current day by server code, from the launch on.
  final Map<String, int> days = {};

  /// Written prompts by server code, author's seat and day.
  final Map<(String, int, int), String> prompts = {};

  /// Fights by server code: owner seat, day, challenger, fighters and votes
  /// by voter seat.
  final Map<
    String,
    List<
      ({
        String id,
        int owner,
        int day,
        Map<String, Object?> challenger,
        List<Map<String, Object?>> fighters,
        Map<int, bool> votes,
      })
    >
  >
  fights = {};

  /// Seats that ended a day, by server code and day.
  final Map<(String, int), Set<int>> dayEnded = {};

  /// Unlocked upgrades by server code, player id and character id.
  final Map<(String, String, String), ({List<String> effects, String? element})> upgrades = {};

  /// Setup drawings by server code and assignment id: the character as the
  /// API returns it and the uploaded sketch.
  final Map<(String, String), ({Map<String, Object?> character, Object? sketch})> drawings = {};
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
        players[token] = {'id': me?['id'] ?? 'player-uuid-${players.length + 1}', 'first_name': body!['first_name']};
        return _json(200, {...players[token]!, 'created_at': '2026-10-09T10:00:00Z'});
      }
      return me == null ? _json(404, {'detail': 'Not signed up yet'}) : _json(200, me);
    }
    if (me == null) return _json(403, {'detail': 'Finish signing up first'});
    final myId = me['id'] as String;

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
      if (request.method == 'GET' && path.length == 3 && path[2] == 'pool') {
        return _json(200, _pool(code));
      }
      if (request.method == 'GET' && path.length == 3 && path[2] == 'collection') {
        final copies = _copies(code, myId);
        return _json(200, [
          for (final character in _pool(code))
            if (copies[character['id']] case final int n) _owned(code, myId, character, n),
        ]);
      }
      if (request.method == 'POST' && path.length == 5 && path[2] == 'collection' && path[4] == 'upgrades') {
        final character = _pool(code).firstWhere((c) => c['id'] == path[3]);
        final copies = _copies(code, myId)[path[3]] ?? 0;
        final done = upgrades.putIfAbsent((code, myId, path[3]), () => (effects: <String>[], element: null));
        final rarity = Rarity.values.byName(character['rarity'] as String);
        final path_ = UpgradeTree.pathFor(rarity);
        if (copies - 1 - done.effects.length < 1) {
          return _json(409, {'detail': 'You need a duplicate to unlock this'});
        }
        final next = path_[done.effects.length];
        if (next == UpgradeEffect.element && body!['element'] == null) {
          return _json(422, {'detail': 'Choose an element for this upgrade'});
        }
        upgrades[(code, myId, path[3])] = (
          effects: [...done.effects, next.name],
          element: next == UpgradeEffect.element ? body!['element'] as String : done.element,
        );
        return _json(200, _owned(code, myId, character, copies));
      }
      if (path.length >= 3 && (path[2] == 'today' || path[2] == 'days')) {
        return _day(code, myId, request.method, path.sublist(2), body);
      }
      if (request.method == 'GET' && path.length == 3 && path[2] == 'gacha') {
        return _json(200, _gacha(code, myId));
      }
      if (request.method == 'POST' && path.length == 3 && path[2] == 'pulls') {
        final count = body!['count'] as int;
        if (count > _tickets(code, myId)) return _json(409, {'detail': 'Not enough pulls'});
        final pool = _pool(code);
        final pulled = pulls.putIfAbsent((code, myId), () => []);
        final outcomes = <Map<String, Object?>>[];
        for (var i = 0; i < count; i++) {
          // Round-robin through the pool, so tests know what comes next.
          final character = pool[pulled.length % pool.length];
          pulled.add(character['id'] as String);
          final copies = _copies(code, myId)[character['id']]!;
          outcomes.add({'character': character, 'is_new': copies == 1, 'copies': copies});
        }
        return _json(200, {'outcomes': outcomes, 'gacha': _gacha(code, myId)});
      }
      if (request.method == 'GET' && path.length == 3 && path[2] == 'assignments') {
        return _json(200, [
          for (final a in _assignments(code, myId)) {...a, 'character': drawings[(code, a['id'] as String)]?.character},
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
        drawings[(code, assignment['id'] as String)] = (character: character, sketch: body['sketch']);
        return _json(200, character);
      }
    }
    if (request.method == 'GET' && path.length == 3 && path[0] == 'characters' && path[2] == 'sketch') {
      final drawing = drawings.values.where((d) => d.character['id'] == path[1]).firstOrNull;
      return drawing == null ? _json(404, {'detail': 'No such character'}) : _json(200, drawing.sketch);
    }
    return _json(404, {'detail': 'No server with this code'});
  });

  Map<String, Object?> _server(String code, String playerId) {
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

  List<Map<String, Object?>> _pool(String code) => [
    for (final MapEntry(:key, :value) in drawings.entries)
      if (key.$1 == code) value.character,
  ];

  /// Copies by character id: your setup drawings and your pulls.
  Map<String, int> _copies(String code, String playerId) {
    final yours = servers[code]!.seats.indexWhere((s) => s['player'] == playerId);
    final copies = <String, int>{};
    for (final character in _pool(code)) {
      if (character['artist_position'] == yours) copies[character['id'] as String] = 1;
    }
    for (final id in pulls[(code, playerId)] ?? const <String>[]) {
      copies[id] = (copies[id] ?? 0) + 1;
    }
    return copies;
  }

  Map<String, Object?> _owned(String code, String playerId, Map<String, Object?> character, int copies) {
    final done = upgrades[(code, playerId, character['id'] as String)];
    return {
      'character': character,
      'copies': copies,
      'upgrades': done?.effects ?? const <String>[],
      'element': done?.element,
    };
  }

  int _tickets(String code, String playerId) {
    final yours = servers[code]!.seats.indexWhere((s) => s['player'] == playerId);
    final challengers = _pool(code).where((c) => c['prompt'] == 'challenger' && c['artist_position'] == yours).length;
    return launchBonus + challengers - (pulls[(code, playerId)]?.length ?? 0);
  }

  static const themes = ['forest', 'beach', 'volcano', 'snow', 'space', 'castle'];

  /// The daily loop, simplified: you write a prompt for the player two seats
  /// on and draw the previous joined player's prompt from the day before.
  http.Response _day(String code, String playerId, String method, List<String> path, Map<String, Object?>? body) {
    final server = servers[code]!;
    final joined = [
      for (final (i, s) in server.seats.indexed)
        if (s['player'] != null) i,
    ];
    final yours = server.seats.indexWhere((s) => s['player'] == playerId);
    final day = days[code] ??= 1;
    String theme(int day) => themes[(day - 1) % themes.length];
    final author = joined[(joined.indexOf(yours) - 1) % joined.length];
    int subjectOf(int seat) => (seat + 2) % server.seats.length;
    Map<String, Object?>? challenger() =>
        _pool(code).where((c) => c['artist_position'] == yours && c['day'] == day).firstOrNull;
    // The first of yesterday's challengers that isn't yours.
    Map<String, Object?>? fightChallenger() => days[code]! < 3
        ? null
        : _pool(code).where((c) => c['day'] == days[code]! - 1 && c['artist_position'] != yours).firstOrNull;
    Map<String, Object?> fightJson(
      ({
        String id,
        int owner,
        int day,
        Map<String, Object?> challenger,
        List<Map<String, Object?>> fighters,
        Map<int, bool> votes,
      })
      f, {
      required bool decided,
    }) {
      final forFighters = f.votes.values.where((v) => v).length;
      return {
        'id': f.id,
        'day': f.day,
        'owner_position': f.owner,
        'challenger': f.challenger,
        'fighters': [
          for (final c in f.fighters) {'character': c, 'upgrades': const <String>[], 'element': null},
        ],
        'by_chance': false,
        'your_vote': f.votes[yours],
        'outcome': decided
            ? {
                'fighter_votes': forFighters,
                'challenger_votes': f.votes.length - forFighters,
                'fighters_win': forFighters > f.votes.length - forFighters,
              }
            : null,
      };
    }

    switch ((method, path)) {
      case ('POST', ['today', 'prompt']):
        if (prompts.containsKey((code, yours, day))) return _json(409, {'detail': "You wrote today's prompt already"});
        prompts[(code, yours, day)] = (body!['title'] as String).trim();
      case ('PUT', ['today', 'challenger']):
        if (challenger() != null) return _json(409, {'detail': "You drew today's challenger already"});
        final written = prompts[(code, author, day - 1)];
        drawings[(code, 'challenger-$day-$yours')] = (
          character: {
            'id': 'challenger-$day-$yours',
            'title': written ?? 'Premade prompt',
            'rarity': 'hero',
            'prompt': 'challenger',
            'artist_position': yours,
            'subject_position': subjectOf(author),
            'day': day,
            'theme': theme(day - 1),
          },
          sketch: body!['sketch'],
        );
      case ('PUT', ['today', 'fighters']):
        final challenger = fightChallenger();
        if (challenger == null) return _json(409, {'detail': "There's no challenger to fight today"});
        final list = fights.putIfAbsent(code, () => []);
        if (list.any((f) => f.owner == yours && f.day == day)) {
          return _json(409, {'detail': "You picked today's fighters already"});
        }
        final pool = _pool(code);
        list.add((
          id: 'fight-$day-$yours',
          owner: yours,
          day: day,
          challenger: challenger,
          fighters: [for (final id in body!['character_ids'] as List) pool.firstWhere((c) => c['id'] == id)],
          votes: {},
        ));
      case ('POST', ['today', 'votes', final fightId]):
        final fight = fights[code]!.firstWhere((f) => f.id == fightId);
        if (fight.votes.containsKey(yours)) return _json(409, {'detail': 'You voted on this fight already'});
        fight.votes[yours] = body!['fighters_win'] as bool;
      case ('POST', ['today', 'end']):
        final ended = dayEnded.putIfAbsent((code, day), () => {})..add(yours);
        if (joined.every(ended.contains)) days[code] = day + 1;
      case ('POST', ['days', 'next']):
        if (server.admin != playerId) return _json(403, {'detail': 'Only the admin can start the next day'});
        days[code] = day + 1;
      case ('GET', ['today']):
        break;
      default:
        return _json(404, {'detail': 'Not found'});
    }
    final today = days[code]!;
    final written = prompts[(code, author, today - 1)];
    return _json(200, {
      'day': today,
      'theme': theme(today),
      'prompt': {'subject_position': subjectOf(yours), 'title': prompts[(code, yours, today)]},
      'to_draw': today == 1
          ? null
          : {
              'author_position': author,
              'subject_position': subjectOf(author),
              'title': written ?? 'Premade prompt',
              'theme': theme(today - 1),
              'premade': written == null,
              'challenger': _pool(code).where((c) => c['artist_position'] == yours && c['day'] == today).firstOrNull,
            },
      'fight': switch (fightChallenger()) {
        null => null,
        final challenger => {
          'challenger': challenger,
          'yours': [
            for (final f in fights[code] ?? const [])
              if (f.owner == yours && f.day == today) fightJson(f, decided: false),
          ].firstOrNull,
        },
      },
      'to_vote': [
        for (final f in fights[code] ?? const [])
          if (f.day == today - 1 && f.owner != yours && f.challenger['artist_position'] != yours)
            fightJson(f, decided: false),
      ],
      'results': [
        for (final f in fights[code] ?? const [])
          if (f.day == today - 2 && (f.owner == yours || f.challenger['artist_position'] == yours))
            fightJson(f, decided: true),
      ],
      'day_ended': [...?dayEnded[(code, today)]]..sort(),
    });
  }

  Map<String, Object?> _gacha(String code, String playerId) {
    final total = pulls[(code, playerId)]?.length ?? 0;
    return {
      'tickets': _tickets(code, playerId),
      'total_pulls': total,
      'pulls_until_legend': 50 - total,
      'beginner_pulls_left': total < 10 ? 10 - total : null,
    };
  }

  /// Planned like the real API does, with ids made up from seat and prompt.
  List<Map<String, Object?>> _assignments(String code, String playerId) {
    final server = servers[code]!;
    final seats = [for (final (i, s) in server.seats.indexed) Player(id: '$i', name: s['name'] as String)];
    final artist = server.seats.indexWhere((s) => s['player'] == playerId);
    // Seeded, so the same artist keeps the same random subjects.
    final planned = server.isTest
        ? SetupPlan.testAssignmentsFor(seats, artist, Random(int.parse(code) + artist))
        : SetupPlan.assignmentsFor(seats, artist);
    String id(DrawingAssignment a) => 'assignment-uuid-${seats[artist].id}-${a.prompt.name}';
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
