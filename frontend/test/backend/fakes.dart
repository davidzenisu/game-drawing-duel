import 'dart:convert';
import 'dart:math';

import 'package:frontend/backend/auth_client.dart';
import 'package:frontend/game/rules/models.dart';
import 'package:frontend/game/rules/setup_plan.dart';
import 'package:frontend/game/rules/upgrades.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// A fight in the fake backend: owner seat, day, challenger, fighters and
/// the challenger's boost stars when it was decided.
typedef FakeFight = ({
  String id,
  int owner,
  int day,
  Map<String, Object?> challenger,
  List<Map<String, Object?>> fighters,
  int boostStars,
});

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

  /// The codes of the speed mode servers. Their setup ends and today ends at
  /// [speedEndsAt]; prompts are written on the first three days only.
  final Set<String> speedServers = {};
  static const speedEndsAt = '2026-10-09T10:05:00Z';

  /// Codes of the servers whose setup started.
  final Set<String> started = {};

  /// Seat positions that finished their setup, by server code.
  final Map<String, Set<int>> finished = {};

  /// Codes of the servers that launched.
  final Set<String> launched = {};

  /// Who cancelled a server, by its code.
  final Map<String, String> cancelled = {};

  /// Server codes and player ids of the players who saw the cancellation.
  final Set<(String, String)> dismissed = {};

  /// Pulled character ids by server code and player id; everyone gets
  /// [launchBonus] pulls at the launch.
  final Map<(String, String), List<String>> pulls = {};
  static const launchBonus = 10;

  /// The banner of every pull request, in order.
  final List<String> bannersPulled = [];

  /// The current day by server code, from the launch on.
  final Map<String, int> days = {};

  /// Written prompts by server code, author's seat and day.
  final Map<(String, int, int), ({String title, int subject})> prompts = {};

  /// Fights by server code: owner seat, day, challenger and fighters.
  final Map<String, List<FakeFight>> fights = {};

  /// Boost stars by server code, day and booster seat, by challenger id.
  final Map<(String, int, int), Map<String, int>> boosts = {};

  int _boostStars(String code, Object? challengerId) => [
    for (final MapEntry(:key, :value) in boosts.entries)
      if (key.$1 == code) value[challengerId] ?? 0,
  ].fold(0, (a, b) => a + b);

  /// Whether the fighters beat the boosted challenger: more stars win, ties go
  /// to the challenger.
  Map<String, Object?> _outcome(FakeFight fight) {
    const stars = {'basic': 1, 'adventurer': 2, 'hero': 3, 'legend': 4};
    final fighterStars = fight.fighters.fold(0, (sum, c) => sum + stars[c['rarity']]!);
    final challengerStars = 3 + fight.boostStars;
    return {
      'fighter_stars': fighterStars,
      'boost_stars': fight.boostStars,
      'challenger_stars': challengerStars,
      'fighters_win': fighterStars > challengerStars,
    };
  }

  /// The latest weekly hero by server code, as `GET today` returns it, and
  /// the latest week's ranking, as `GET ranking` does; tests set them up.
  final Map<String, Map<String, Object?>> weeklyHeroes = {};
  final Map<String, Map<String, Object?>> rankings = {};

  /// Hurries by server code, day and sender seat: the target seat.
  final Map<(String, int, int), int> hurries = {};

  /// Seats that ended a day, by server code and day.
  final Map<(String, int), Set<int>> dayEnded = {};

  /// Unlocked upgrades by server code, player id and character id.
  final Map<(String, String, String), ({List<String> effects, String? element})> upgrades = {};

  /// Switched off effects by server code, player id and character id.
  final Map<(String, String, String), List<String>> hidden = {};

  /// Setup drawings by server code and assignment id: the character as the
  /// API returns it and the uploaded sketch.
  final Map<(String, String), ({Map<String, Object?> character, Object? sketch})> drawings = {};
  int _nextCharacter = 1;
  final List<http.Request> requests = [];

  /// The tutorials each player saw, by token.
  final Map<String, Set<String>> tutorialsSeen = {};

  /// Tokens with the content permission.
  final Set<String> contentEditors = {};

  /// The prompt hints, each with its premade title.
  final List<Map<String, Object?>> hints = [];

  /// The starter prompts of the setup drawings.
  final List<Map<String, Object?>> setupHints = [];

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

    final canEditContent = contentEditors.contains(token);
    Map<String, Object?> meJson() => {
      ...players[token]!,
      'created_at': '2026-10-09T10:00:00Z',
      'can_edit_content': canEditContent,
      'tutorials_seen': [...?tutorialsSeen[token]],
    };
    if (request.url.path == '/me') {
      if (request.method == 'PUT') {
        players[token] = {'id': me?['id'] ?? 'player-uuid-${players.length + 1}', 'first_name': body!['first_name']};
        return _json(200, meJson());
      }
      return me == null ? _json(404, {'detail': 'Not signed up yet'}) : _json(200, meJson());
    }
    if (request.method == 'PUT' && path.length == 3 && path[0] == 'me' && path[1] == 'tutorials') {
      if (me == null) return _json(404, {'detail': 'Not signed up yet'});
      tutorialsSeen.putIfAbsent(token, () => {}).add(path[2]);
      return _json(200, meJson());
    }
    if (path.first == 'content') {
      if (!canEditContent) return _json(403, {'detail': 'Missing permission edit:content'});
      if (path[1] == 'setup-hints') return _setupHints(request, path, body);
      if (path[1] != 'hints') return _json(404, {'detail': 'Not found'});
      final entries = hints;
      switch ((request.method, path.length)) {
        case ('GET', 2):
          final theme = request.url.queryParameters['theme'];
          return _json(200, [
            for (final e in entries)
              if (e['retired'] != true && (theme == null || e['theme'] == theme)) e,
          ]);
        case ('POST', 2):
          final added = <Map<String, Object?>>[];
          final skipped = <String>[];
          for (final draft in (body!['hints'] as List).cast<Map<String, Object?>>()) {
            final text = (draft['text'] as String).trim();
            final known = entries.any((e) => e['retired'] != true && e['theme'] == body['theme'] && e['text'] == text);
            if (known) {
              skipped.add(text);
              continue;
            }
            final entry = {
              'id': 'content-${entries.length + 1}',
              'theme': body['theme'],
              'text': text,
              'premade_title': (draft['premade_title'] as String).trim(),
              'created_at': '2026-10-12T10:00:00Z',
            };
            entries.add(entry);
            added.add(entry);
          }
          return _json(201, {'added': added, 'skipped': skipped});
        case ('DELETE', 3):
          final entry = entries.where((e) => e['id'] == path[2] && e['retired'] != true).firstOrNull;
          if (entry == null) return _json(404, {'detail': 'No such hint'});
          entry['retired'] = true;
          return http.Response('', 204);
      }
    }
    if (me == null) return _json(403, {'detail': 'Finish signing up first'});
    final myId = me['id'] as String;

    if (request.method == 'POST' && request.url.path == '/servers') {
      final code = '${_nextCode++}';
      if (body!['mode'] == 'speed') speedServers.add(code);
      servers[code] = (
        admin: myId,
        isTest: body['is_test'] as bool? ?? false,
        seats: [
          {'name': me['first_name'], 'player': myId},
          for (final name in body['other_names'] as List) {'name': name, 'player': null},
        ],
      );
      return _json(201, _server(code, myId));
    }
    if (request.method == 'GET' && request.url.path == '/servers/mine') {
      final mine = servers.keys
          .where((c) => servers[c]!.seats.any((s) => s['player'] == myId) && !dismissed.contains((c, myId)))
          .toList()
          .reversed;
      return _json(200, [for (final code in mine) _server(code, myId)]);
    }
    if (path.length >= 2 && path[0] == 'servers' && servers.containsKey(path[1])) {
      final code = path[1];
      if (request.method == 'GET' && path.length == 2) return _json(200, _server(code, myId));
      if (request.method == 'POST' && path.length == 3 && path[2] == 'dismiss') {
        if (!cancelled.containsKey(code)) return _json(409, {'detail': "The server wasn't cancelled"});
        dismissed.add((code, myId));
        return http.Response('', 204);
      }
      if (cancelled.containsKey(code)) return _json(410, {'detail': 'The server was cancelled'});
      if (request.method == 'DELETE' && path.length == 2) {
        final seat = servers[code]!.seats.where((s) => s['player'] == myId).firstOrNull;
        if (seat == null) return _json(403, {'detail': "You haven't joined this server"});
        cancelled[code] = seat['name'] as String;
        dismissed.add((code, myId));
        drawings.removeWhere((key, _) => key.$1 == code);
        pulls.removeWhere((key, _) => key.$1 == code);
        fights.remove(code);
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
          for (final character in _characters(code))
            if (copies[character['id']] case final int n) _owned(code, myId, character, n),
        ]);
      }
      if (request.method == 'PUT' && path.length == 5 && path[2] == 'collection' && path[4] == 'element') {
        final character = _characters(code).firstWhere((c) => c['id'] == path[3]);
        final done = upgrades[(code, myId, path[3])];
        if (done == null || !done.effects.contains('element')) {
          return _json(409, {'detail': 'Unlock element first'});
        }
        upgrades[(code, myId, path[3])] = (effects: done.effects, element: body!['element'] as String);
        return _json(200, _owned(code, myId, character, _copies(code, myId)[path[3]] ?? 0));
      }
      if (request.method == 'PUT' && path.length == 5 && path[2] == 'collection' && path[4] == 'effects') {
        final character = _characters(code).firstWhere((c) => c['id'] == path[3]);
        final done = upgrades[(code, myId, path[3])]?.effects ?? const <String>[];
        final wanted = (body!['hidden'] as List).cast<String>();
        final locked = wanted.where((e) => !done.contains(e)).toList();
        if (locked.isNotEmpty) return _json(409, {'detail': 'Unlock ${locked.join(', ')} first'});
        hidden[(code, myId, path[3])] = wanted;
        return _json(200, _owned(code, myId, character, _copies(code, myId)[path[3]] ?? 0));
      }
      if (request.method == 'POST' && path.length == 5 && path[2] == 'collection' && path[4] == 'upgrades') {
        final character = _characters(code).firstWhere((c) => c['id'] == path[3]);
        final copies = _copies(code, myId)[path[3]] ?? 0;
        final done = upgrades.putIfAbsent((code, myId, path[3]), () => (effects: <String>[], element: null));
        final rarity = Rarity.values.byName(character['rarity'] as String);
        final path_ = UpgradeTree.pathFor(rarity);
        final costs = UpgradeTree.costsFor(rarity);
        final step = path_.indexWhere((e) => !done.effects.contains(e.name));
        final spare =
            copies -
            1 -
            [
              for (final (i, e) in path_.indexed)
                if (done.effects.contains(e.name)) costs[i],
            ].fold(0, (a, b) => a + b);
        final cost = costs[step];
        if (spare < cost) {
          final missing = cost - max(spare, 0);
          return _json(409, {'detail': 'You need $missing more duplicate${missing > 1 ? 's' : ''} to unlock this'});
        }
        final next = path_[step];
        if (next == UpgradeEffect.element && body!['element'] == null) {
          return _json(422, {'detail': 'Choose an element for this upgrade'});
        }
        upgrades[(code, myId, path[3])] = (
          effects: [...done.effects, next.name],
          element: next == UpgradeEffect.element ? body!['element'] as String : done.element,
        );
        return _json(200, _owned(code, myId, character, copies));
      }
      if (request.method == 'GET' && path.length == 3 && path[2] == 'ranking') {
        return _json(200, rankings[code]);
      }
      if (request.method == 'GET' && path.length == 3 && path[2] == 'challengers') {
        return _json(200, _challengers(code, myId));
      }
      if (path.length >= 3 && (path[2] == 'today' || path[2] == 'days')) {
        return _day(code, myId, request.method, path.sublist(2), body);
      }
      if (request.method == 'GET' && path.length == 3 && path[2] == 'gacha') {
        return _json(200, _gacha(code, myId));
      }
      if (request.method == 'POST' && path.length == 3 && path[2] == 'pulls') {
        final count = body!['count'] as int;
        final banner = body['banner'] as String? ?? 'standard';
        bannersPulled.add(banner);
        if (count > _tickets(code, myId)) return _json(409, {'detail': 'Not enough pulls'});
        if (banner == 'weekly' && _rateUp(code).isEmpty) {
          return _json(409, {'detail': 'The weekly banner opens with the first finale'});
        }
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
      'mode': speedServers.contains(code) ? 'speed' : 'regular',
      'setup_ends_at': speedServers.contains(code) && started.contains(code) ? speedEndsAt : null,
      'is_test': server.isTest,
      'is_admin': server.admin == playerId,
      'phase': cancelled.containsKey(code)
          ? 'cancelled'
          : launched.contains(code)
          ? 'running'
          : started.contains(code)
          ? 'setup'
          : 'lobby',
      'cancelled_by': cancelled[code],
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

  /// Every character: the setup drawings and the challengers.
  List<Map<String, Object?>> _characters(String code) => [
    for (final MapEntry(:key, :value) in drawings.entries)
      if (key.$1 == code) value.character,
  ];

  /// The gacha pool: the setup drawings only.
  List<Map<String, Object?>> _pool(String code) => [
    for (final character in _characters(code))
      if (character['prompt'] != 'challenger') character,
  ];

  /// Copies by character id: your setup drawings and your pulls.
  Map<String, int> _copies(String code, String playerId) {
    final yours = servers[code]!.seats.indexWhere((s) => s['player'] == playerId);
    final copies = <String, int>{};
    for (final character in _characters(code)) {
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
      'hidden': hidden[(code, playerId, character['id'] as String)] ?? const <String>[],
    };
  }

  int _tickets(String code, String playerId) {
    final yours = servers[code]!.seats.indexWhere((s) => s['player'] == playerId);
    final challengers = _characters(
      code,
    ).where((c) => c['prompt'] == 'challenger' && c['artist_position'] == yours).length;
    return launchBonus + challengers + _wins(code, yours).length - (pulls[(code, playerId)]?.length ?? 0);
  }

  /// The fights [seat] won: each earns a pull and the challenger's stars.
  Iterable<FakeFight> _wins(String code, int seat) => [
    for (final f in fights[code] ?? const <FakeFight>[])
      if (f.owner == seat && _outcome(f)['fighters_win'] == true) f,
  ];

  static const themes = ['forest', 'beach', 'volcano', 'snow', 'jungle', 'space', 'castle'];

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
        _characters(code).where((c) => c['artist_position'] == yours && c['day'] == day).firstOrNull;
    // The first challenger drawn two days before [day] that isn't yours.
    Map<String, Object?>? fightChallengerOn(int day) => day < 4
        ? null
        : _characters(code).where((c) => c['day'] == day - 2 && c['artist_position'] != yours).firstOrNull;
    Map<String, Object?>? fightChallenger() => fightChallengerOn(days[code]!);
    Map<String, Object?> fightJson(FakeFight f) {
      return {
        'id': f.id,
        'day': f.day,
        'owner_position': f.owner,
        'challenger': f.challenger,
        'fighters': [
          for (final c in f.fighters) {'character': c, 'upgrades': const <String>[], 'element': null},
        ],
        'by_chance': false,
        'outcome': _outcome(f),
      };
    }

    /// Up to three of the challengers drawn the day before [day] you may
    /// boost: not the one you drew or the one you fight the day after.
    List<Map<String, Object?>> boostTargets(int day) {
      if (day < 3) return const [];
      final fought = fightChallengerOn(day + 1)?['id'];
      return _characters(
        code,
      ).where((c) => c['day'] == day - 1 && c['artist_position'] != yours && c['id'] != fought).take(3).toList();
    }

    switch ((method, path)) {
      case ('POST', ['today', 'prompt']):
        if (prompts.containsKey((code, yours, day))) return _json(409, {'detail': "You wrote today's prompt already"});
        final subject = body!['subject_position'] as int;
        if (subject == yours || subject >= server.seats.length) {
          return _json(422, {'detail': 'Choose another player of the server'});
        }
        prompts[(code, yours, day)] = (title: (body['title'] as String).trim(), subject: subject);
      case ('PUT', ['today', 'challenger']):
        if (challenger() != null) return _json(409, {'detail': "You drew today's challenger already"});
        final written = prompts[(code, author, day - 1)];
        drawings[(code, 'challenger-$day-$yours')] = (
          character: {
            'id': 'challenger-$day-$yours',
            'title': written?.title ?? 'Premade prompt',
            'rarity': 'hero',
            'prompt': 'challenger',
            'artist_position': yours,
            'subject_position': written?.subject ?? subjectOf(author),
            'day': day,
            // A challenger takes the theme of the day it's fought.
            'theme': theme(day + 2),
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
        final pool = _characters(code);
        list.add((
          id: 'fight-$day-$yours',
          owner: yours,
          day: day,
          challenger: challenger,
          fighters: [for (final id in body!['character_ids'] as List) pool.firstWhere((c) => c['id'] == id)],
          boostStars: _boostStars(code, challenger['id']),
        ));
      case ('PUT', ['today', 'boosts']):
        final targets = {for (final c in boostTargets(day)) c['id']};
        final given = {
          for (final b in (body!['boosts'] as List).cast<Map<String, Object?>>())
            b['challenger_id'] as String: b['stars'] as int,
        };
        if (targets.isEmpty || !targets.containsAll(given.keys)) {
          return _json(409, {'detail': "You can't boost that challenger today"});
        }
        if (given.values.any((n) => n < 0 || n > 3) || given.values.fold(0, (a, b) => a + b) > 3) {
          return _json(409, {'detail': 'You have 3 stars to give'});
        }
        boosts[(code, day, yours)] = given;
      case ('POST', ['today', 'hurry']):
        if (hurries.containsKey((code, day, yours))) return _json(409, {'detail': "You sent today's hurry already"});
        hurries[(code, day, yours)] = body!['target_position'] as int;
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
      'ends_at': speedServers.contains(code) ? speedEndsAt : null,
      'prompt': speedServers.contains(code) && today > 3
          ? null
          : {
              'hint': 'a challenger on a ${theme(today + 3)} day',
              'theme': theme(today + 3),
              'subject_position': prompts[(code, yours, today)]?.subject,
              'title': prompts[(code, yours, today)]?.title,
            },
      'to_draw': today == 1
          ? null
          : {
              'author_position': author,
              'subject_position': written?.subject ?? subjectOf(author),
              'title': written?.title ?? 'Premade prompt',
              'theme': theme(today + 2),
              // The hint the author got yesterday.
              'hint': written == null ? null : 'a challenger on a ${theme(today + 2)} day',
              'premade': written == null,
              'challenger': _characters(
                code,
              ).where((c) => c['artist_position'] == yours && c['day'] == today).firstOrNull,
            },
      'fight': switch (fightChallenger()) {
        null => null,
        final challenger => {
          'challenger': challenger,
          'yours': [
            for (final f in fights[code] ?? const [])
              if (f.owner == yours && f.day == today) fightJson(f),
          ].firstOrNull,
          // Day 1 is a Monday in the fake, so weeks start on days 1, 8, ...
          'resting': {
            for (final f in fights[code] ?? const [])
              if (f.owner == yours && f.day < today && f.day >= today - (today - 1) % 7)
                for (final c in f.fighters)
                  if (c['rarity'] != 'basic') c['id'],
          }.toList(),
        },
      },
      'boost': switch (boostTargets(today)) {
        [] => null,
        final targets => {
          'targets': [
            for (final c in targets) {'challenger': c, 'stars': boosts[(code, today, yours)]?[c['id']] ?? 0},
          ],
          'stars': 3,
          'max_per_challenger': 3,
        },
      },
      'results': [
        for (final f in fights[code] ?? const [])
          if (f.day == today - 1 && (f.owner == yours || f.challenger['artist_position'] == yours)) fightJson(f),
      ],
      'hurry_sent_to': hurries[(code, today, yours)],
      'incoming_hurries': [
        for (final MapEntry(:key, :value) in hurries.entries)
          if (key.$1 == code && key.$2 == today && value == yours) {'by_position': key.$3, 'at_fraction': 0.4},
      ],
      'day_ended': [...?dayEnded[(code, today)]]..sort(),
      'weekly_hero': weeklyHeroes[code],
    });
  }

  /// The challengers you drew, fought or boosted; fights count once their
  /// day is over.
  List<Map<String, Object?>> _challengers(String code, String playerId) {
    final yours = servers[code]!.seats.indexWhere((s) => s['player'] == playerId);
    final all = fights[code] ?? const [];
    bool encountered(Map<String, Object?> c) =>
        c['artist_position'] == yours ||
        boosts.entries.any((e) => e.key.$1 == code && e.key.$3 == yours && e.value.containsKey(c['id'])) ||
        all.any((f) => f.challenger['id'] == c['id'] && f.owner == yours);
    return [
      for (final c in _characters(code).reversed)
        if (c['prompt'] == 'challenger' && encountered(c))
          () {
            final decided = all.where((f) => f.challenger['id'] == c['id'] && f.day < days[code]!);
            final wins = decided.where((f) => _outcome(f)['fighters_win'] == false);
            return {'character': c, 'fights': decided.length, 'wins': wins.length};
          }(),
    ];
  }

  Map<String, Object?> _gacha(String code, String playerId) {
    final total = pulls[(code, playerId)]?.length ?? 0;
    return {
      'tickets': _tickets(code, playerId),
      'total_pulls': total,
      'pulls_until_legend': 50 - total,
      'beginner_pulls_left': total < 10 ? 10 - total : null,
      'rate_up': _rateUp(code),
      'victory_stars': _wins(
        code,
        servers[code]!.seats.indexWhere((s) => s['player'] == playerId),
      ).fold<int>(0, (sum, f) => sum + (_outcome(f)['challenger_stars'] as int)),
    };
  }

  /// Like the real API: the latest weekly hero and the pool's legends of
  /// the same player.
  List<String> _rateUp(String code) {
    final hero = weeklyHeroes[code]?['character'] as Map<String, Object?>?;
    if (hero == null) return [];
    return [
      hero['id'] as String,
      for (final c in _pool(code))
        if (c['rarity'] == 'legend' && c['subject_position'] == hero['subject_position']) c['id'] as String,
    ];
  }

  /// Planned like the real API does, with ids made up from seat and prompt.
  List<Map<String, Object?>> _assignments(String code, String playerId) {
    final server = servers[code]!;
    final seats = [for (final (i, s) in server.seats.indexed) Player(id: '$i', name: s['name'] as String)];
    final artist = server.seats.indexWhere((s) => s['player'] == playerId);
    // Seeded, so the same artist keeps the same random subjects.
    final planned = server.isTest
        ? SetupPlan.testAssignmentsFor(seats, artist, Random(int.parse(code) + artist))
        : speedServers.contains(code)
        ? SetupPlan.speedAssignmentsFor(seats, artist)
        : SetupPlan.assignmentsFor(seats, artist);
    String id(DrawingAssignment a) => 'assignment-uuid-${seats[artist].id}-${a.prompt.name}';
    return [
      for (final a in planned)
        {
          'id': id(a),
          'prompt': a.prompt.name,
          'subject_position': int.parse(a.subject.id),
          'based_on': a.basedOn == null ? null : id(planned.firstWhere((b) => b.id == a.basedOn)),
          'hint': 'Starter prompt of the ${a.prompt.name}',
        },
    ];
  }

  http.Response _setupHints(http.Request request, List<String> path, Map<String, Object?>? body) {
    switch ((request.method, path.length)) {
      case ('GET', 2):
        final prompt = request.url.queryParameters['prompt'];
        return _json(200, [
          for (final e in setupHints)
            if (e['retired'] != true && (prompt == null || e['prompt'] == prompt)) e,
        ]);
      case ('POST', 2):
        final added = <Map<String, Object?>>[];
        final skipped = <String>[];
        for (final text in (body!['texts'] as List).cast<String>().map((t) => t.trim())) {
          final known = setupHints.any(
            (e) => e['retired'] != true && e['prompt'] == body['prompt'] && e['text'] == text,
          );
          if (known) {
            skipped.add(text);
            continue;
          }
          final entry = {
            'id': 'setup-hint-${setupHints.length + 1}',
            'prompt': body['prompt'],
            'text': text,
            'created_at': '2026-10-12T10:00:00Z',
          };
          setupHints.add(entry);
          added.add(entry);
        }
        return _json(201, {'added': added, 'skipped': skipped});
      case ('DELETE', 3):
        final entry = setupHints.where((e) => e['id'] == path[2] && e['retired'] != true).firstOrNull;
        if (entry == null) return _json(404, {'detail': 'No such starter prompt'});
        entry['retired'] = true;
        return http.Response('', 204);
    }
    return _json(404, {'detail': 'Not found'});
  }

  static http.Response _json(int status, Object? body) =>
      http.Response(jsonEncode(body), status, headers: {'content-type': 'application/json'});
}
