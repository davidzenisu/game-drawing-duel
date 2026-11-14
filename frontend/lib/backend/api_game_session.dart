import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../game/game_session.dart';
import '../game/rules/content.dart';
import '../game/rules/daily_loop.dart';
import '../game/rules/gacha.dart';
import '../game/rules/models.dart';
import '../game/rules/setup_plan.dart';
import '../game/rules/themes.dart';
import '../game/rules/upgrades.dart';
import '../platform/sketch_store.dart';
import 'api_client.dart';
import 'auth_client.dart';
import 'sketch_json.dart';

/// [GameSession] backed by the API and Auth0.
class ApiGameSession extends GameSession {
  ApiGameSession({
    required ApiClient? api,
    String? signInProblem,
    this.retryDelay = const Duration(milliseconds: 500),
    SketchStore? sketchStore,
  }) : _api = api,
       _sketchStore = sketchStore ?? SketchStore(),
       _signInProblem = api == null ? signInProblem ?? 'Sign-in is not configured.' : signInProblem;

  final ApiClient? _api;

  /// How long a drawing download waits before its first retry; each next
  /// retry waits twice as long.
  final Duration retryDelay;

  /// The drawings downloaded on earlier visits.
  final SketchStore _sketchStore;

  GamePhase _phase = GamePhase.loading;
  String? _signInProblem;
  String _suggestedFirstName = '';
  Player? _account;
  ServerSession? _server;
  List<DrawingAssignment> _assignments = const [];

  /// Your setup drawings by assignment id.
  Map<String, CharacterCard> _setupDrawings = {};

  List<CharacterCard> _pool = const [];
  List<OwnedCard> _collection = const [];
  int _tickets = 0;
  int _stars = 0;
  GachaStatus _gachaStatus = GachaMachine().status;
  Set<String> _rateUp = const {};

  /// Sketches by character id. A character never changes, so refreshing
  /// only downloads new ones.
  final Map<String, Sketch> _sketches = {};

  String? _serverNotice;

  /// After a failed sign-in, signing in again must not reuse the old session.
  bool _freshSignInNeeded = false;

  AuthClient get _auth => _api!.auth;

  /// Restores a previous sign-in and loads the player.
  Future<void> start() async {
    if (_api == null) return _setPhase(GamePhase.signIn);
    try {
      final profile = await _auth.restore();
      if (profile == null) return _setPhase(GamePhase.signIn);
      _suggestedFirstName = profile.firstName;
      await _loadPlayer();
    } on SignInRequired catch (error) {
      _requireSignIn(error.message);
    } catch (error) {
      _requireSignIn('Signing in failed: $error');
    }
  }

  /// Back to the sign-in with the reason; the next sign-in is a fresh one.
  void _requireSignIn(String problem) {
    _signInProblem = problem;
    _freshSignInNeeded = true;
    _account = null;
    _canEditContent = false;
    _canManageServers = false;
    _tutorialsSeen = {};
    _server = null;
    _assignments = const [];
    _setupDrawings = {};
    _pool = const [];
    _collection = const [];
    _challengers = const [];
    _tickets = 0;
    _gifts = const [];
    _setPhase(GamePhase.signIn);
  }

  Future<Object?> _get(String path) => _guard(() => _api!.get(path));

  /// [_get], tried up to [_retries] more times when the network or the API
  /// hiccups. Loading the game downloads every drawing of the pool at once,
  /// and one lost download shouldn't stop the whole game from loading.
  Future<Object?> _getRetrying(String path) async {
    for (var attempt = 0; ; attempt++) {
      try {
        return await _get(path);
      } catch (error) {
        if (attempt >= _retries || !_isTransient(error)) rethrow;
        await Future<void>.delayed(retryDelay * (1 << attempt));
      }
    }
  }

  static const _retries = 2;

  /// A failure that may well pass on a second try: no response at all (the
  /// browser's "Failed to fetch"), a timeout, or the API being overloaded.
  static bool _isTransient(Object error) => switch (error) {
    SignInRequired() => false,
    ApiException(:final statusCode) => statusCode >= 500 || statusCode == 429,
    http.ClientException() || TimeoutException() => true,
    _ => false,
  };

  Future<Object?> _put(String path, Object body) => _guard(() => _api!.put(path, body));

  Future<Object?> _post(String path, [Object? body]) => _guard(() => _api!.post(path, body));

  Future<Object?> _delete(String path) => _guard(() => _api!.delete(path));

  Future<Object?> _guard(Future<Object?> Function() request) async {
    try {
      return await request();
    } on SignInRequired catch (error) {
      _requireSignIn(error.message);
      rethrow;
    } on ApiException catch (error) {
      // Someone cancelled the server while you were in it.
      if (error.statusCode == 410 && _server != null) await _enterServer(await _get('/servers/${_server!.code}'));
      rethrow;
    }
  }

  Future<void> _loadPlayer() async {
    final Object? me;
    try {
      me = await _get('/me');
    } on ApiException catch (error) {
      if (error.statusCode != 404) rethrow;
      // Signed in, but the account isn't finished yet.
      return _setPhase(GamePhase.signup);
    }
    _setAccount(me);
    await _loadServer();
  }

  void _setAccount(Object? json) {
    if (json is! Map || json['id'] is! String || json['first_name'] is! String) {
      throw const FormatException('Unexpected player response.');
    }
    _account = Player(id: 'player-${json['id']}', name: json['first_name'] as String, isYou: true);
    _canEditContent = json['can_edit_content'] == true;
    _canManageServers = json['can_manage_servers'] == true;
    _tutorialsSeen = {for (final key in json['tutorials_seen'] as List? ?? const []) key as String};
  }

  Set<String> _tutorialsSeen = {};

  @override
  Set<String> get tutorialsSeen => _tutorialsSeen;

  @override
  Future<void> markTutorialSeen(String key) async {
    if (!_tutorialsSeen.add(key)) return;
    notifyListeners();
    try {
      // The response would only repeat what's known, and could miss a key
      // marked meanwhile.
      await _put('/me/tutorials/$key', const {});
    } on Exception {
      // Not stored: it shows again next time, which is fine.
    }
  }

  bool _canEditContent = false;

  @override
  bool get canEditContent => _canEditContent;

  bool _canManageServers = false;
  @override
  bool get canManageServers => _canManageServers;

  ContentEntry _contentEntry(Object? json) {
    if (json case {
      'id': String id,
      'theme': String theme,
      'text': String text,
      'premade_title': String premadeTitle,
      'created_at': String createdAt,
    }) {
      return ContentEntry(
        id: id,
        theme: _theme(theme),
        text: text,
        premadeTitle: premadeTitle,
        createdAt: DateTime.parse(createdAt),
      );
    }
    throw _unexpected('content entry', json, const ['id', 'theme', 'text', 'premade_title', 'created_at']);
  }

  /// Names what's wrong with a response object: the first of [textFields]
  /// that's missing or not a string, e.g. after the API changed.
  static FormatException _unexpected(String what, Object? json, List<String> textFields) {
    if (json is! Map) return FormatException('Unexpected $what: not an object.');
    for (final field in textFields) {
      if (!json.containsKey(field)) return FormatException('Unexpected $what: "$field" is missing.');
      if (json[field] is! String) return FormatException('Unexpected $what: "$field" is not text.');
    }
    return FormatException('Unexpected $what.');
  }

  @override
  Future<List<ContentEntry>> contentEntries(DailyTheme theme) async {
    final json = await _get('/content/hints?theme=${theme.name}');
    if (json is! List) throw const FormatException('Unexpected content response.');
    return [for (final entry in json) _contentEntry(entry)];
  }

  @override
  Future<ContentAddResult> addContent(DailyTheme theme, List<HintDraft> hints) async {
    final json = await _post('/content/hints', {
      'theme': theme.name,
      'hints': [
        for (final hint in hints) {'text': hint.text, 'premade_title': hint.premadeTitle},
      ],
    });
    if (json case {'added': List added, 'skipped': List skipped}) {
      return ContentAddResult(
        added: [for (final entry in added) _contentEntry(entry)],
        skipped: [for (final text in skipped) text as String],
      );
    }
    throw const FormatException('Unexpected content response.');
  }

  @override
  Future<void> retireContent(ContentEntry entry) async {
    await _delete('/content/hints/${entry.id}');
  }

  SetupHintEntry _setupHintEntry(Object? json) {
    if (json case {'id': String id, 'prompt': String prompt, 'text': String text, 'created_at': String createdAt}) {
      return SetupHintEntry(
        id: id,
        prompt: SetupPrompt.values.asNameMap()[prompt] ?? (throw FormatException('Unknown prompt $prompt.')),
        text: text,
        createdAt: DateTime.parse(createdAt),
      );
    }
    throw _unexpected('starter prompt', json, const ['id', 'prompt', 'text', 'created_at']);
  }

  @override
  Future<List<SetupHintEntry>> setupHints(SetupPrompt prompt) async {
    final json = await _get('/content/setup-hints?prompt=${prompt.name}');
    if (json is! List) throw const FormatException('Unexpected starter prompts response.');
    return [for (final entry in json) _setupHintEntry(entry)];
  }

  @override
  Future<SetupHintAddResult> addSetupHints(SetupPrompt prompt, List<String> texts) async {
    final json = await _post('/content/setup-hints', {'prompt': prompt.name, 'texts': texts});
    if (json case {'added': List added, 'skipped': List skipped}) {
      return SetupHintAddResult(
        added: [for (final entry in added) _setupHintEntry(entry)],
        skipped: [for (final text in skipped) text as String],
      );
    }
    throw const FormatException('Unexpected starter prompts response.');
  }

  @override
  Future<void> retireSetupHint(SetupHintEntry entry) async {
    await _delete('/content/setup-hints/${entry.id}');
  }

  /// Back to your newest server, or to creating or joining one.
  Future<void> _loadServer() async {
    final servers = await _get('/servers/mine');
    if (servers is! List) throw const FormatException('Unexpected servers response.');
    if (servers.isEmpty) return _setPhase(GamePhase.server);
    await _enterServer(servers.first);
  }

  /// Shows the server's lobby, or your setup once the admin started it.
  Future<void> _enterServer(Object? json) async {
    final server = _parseServer(json);
    _serverNotice = null;
    switch ((json as Map)['phase']) {
      case 'lobby':
        _server = server;
        _setPhase(GamePhase.lobby);
      case 'setup':
        await _loadSetup(server);
        _server = server;
        _setPhase(GamePhase.setup);
      // A finished speed mode session stays in the daily hub, see
      // [sessionOver].
      case 'running' || 'finished':
        await _loadPool(server);
        _server = server;
        _setPhase(GamePhase.daily);
      case 'cancelled':
        // Seen: from now on it's no longer one of your servers.
        await _post('/servers/${server.code}/dismiss');
        final by = json['cancelled_by'];
        _leaveServer(by is String ? '$by cancelled server ${server.code}.' : 'Server ${server.code} was cancelled.');
      default:
        throw const FormatException('Unexpected server phase.');
    }
  }

  static String _seatId(int position) => 'seat-$position';

  static int _seatPosition(Player seat) => int.parse(seat.id.substring('seat-'.length));

  /// Every seat becomes a player; yours is marked with `isYou`.
  ServerSession _parseServer(Object? json) {
    if (json is! Map ||
        json['code'] is! String ||
        json['seats'] is! List ||
        json['is_admin'] is! bool ||
        json['is_test'] is! bool ||
        json['phase'] is! String) {
      throw const FormatException('Unexpected server response.');
    }
    final yourPosition = json['your_position'];
    final players = <Player>[];
    final joined = <String>{};
    final setupDone = <String>{};
    for (final seat in json['seats'] as List) {
      if (seat is! Map ||
          seat['position'] is! int ||
          seat['name'] is! String ||
          seat['joined'] is! bool ||
          seat['setup_done'] is! bool) {
        throw const FormatException('Unexpected seat in server response.');
      }
      final position = seat['position'] as int;
      final player = Player(id: _seatId(position), name: seat['name'] as String, isYou: position == yourPosition);
      players.add(player);
      if (seat['joined'] as bool) joined.add(player.id);
      if (seat['setup_done'] as bool) setupDone.add(player.id);
    }
    return ServerSession(
      code: json['code'] as String,
      players: players,
      isAdmin: json['is_admin'] as bool,
      joined: joined,
      isTest: json['is_test'] as bool,
      isSpeed: json['mode'] == 'speed',
      setupEndsAt: switch (json['setup_ends_at']) {
        final String at => DateTime.parse(at),
        _ => null,
      },
      setupDone: setupDone,
    );
  }

  static String _assignmentId(String id) => 'assignment-$id';

  /// The API's id of [assignment].
  static String _assignmentKey(DrawingAssignment assignment) => assignment.id.substring('assignment-'.length);

  /// Your setup assignments and the drawings you made for them so far.
  Future<void> _loadSetup(ServerSession server) async {
    final json = await _get('/servers/${server.code}/assignments');
    if (json is! List) throw const FormatException('Unexpected assignments response.');
    final assignments = <DrawingAssignment>[];
    final characters = <String, Object?>{};
    for (final item in json) {
      if (item case {
        'id': String id,
        'prompt': String prompt,
        'subject_position': int subject,
        'based_on': String? basedOn,
      }) {
        final assignment = DrawingAssignment(
          id: _assignmentId(id),
          prompt: SetupPrompt.values.asNameMap()[prompt] ?? (throw FormatException('Unknown prompt $prompt.')),
          subject: _seat(server, subject),
          basedOn: basedOn == null ? null : _assignmentId(basedOn),
          hint: switch (item['hint']) {
            final String hint => hint,
            _ => null,
          },
        );
        assignments.add(assignment);
        if (item['character'] != null) characters[assignment.id] = item['character'];
      } else {
        throw const FormatException('Unexpected assignment in response.');
      }
    }
    final drawings = await Future.wait([
      for (final MapEntry(key: assignmentId, value: character) in characters.entries)
        _loadCharacter(server, character).then((card) => MapEntry(assignmentId, card)),
    ]);
    _assignments = assignments;
    _setupDrawings = Map.fromEntries(drawings);
  }

  static DailyTheme _theme(String name) =>
      DailyTheme.values.asNameMap()[name] ?? (throw FormatException('Unknown theme $name.'));

  /// The pool, your collection and today of a running game.
  Future<void> _loadPool(ServerSession server) async {
    final (pool, collection, gacha, today, challengers, gifts) = await (
      _get('/servers/${server.code}/pool'),
      _get('/servers/${server.code}/collection'),
      _get('/servers/${server.code}/gacha'),
      _get('/servers/${server.code}/today'),
      _get('/servers/${server.code}/challengers'),
      _get('/servers/${server.code}/gifts'),
    ).wait;
    if (pool is! List || collection is! List) throw const FormatException('Unexpected pool response.');
    _pool = await Future.wait([for (final character in pool) _loadCharacter(server, character)]);
    _collection = [
      for (final owned in collection)
        if (owned case {'character': final Object character})
          // Challengers pulled before they left the pool are still yours.
          _setOwned(OwnedCard(await _card(server, character)), owned)
        else
          throw const FormatException('Unexpected character in collection.'),
    ];
    await _setChallengers(server, challengers);
    _setGacha(gacha);
    await _setToday(server, today);
    _gifts = _parseGifts(gifts);
  }

  List<Gift> _gifts = const [];

  @override
  List<Gift> get gifts => _gifts;

  static List<Gift> _parseGifts(Object? json) => switch (json) {
    List gifts => [
      for (final gift in gifts)
        if (gift case {'id': String id, 'message': String message, 'pulls': int pulls, 'sent_at': String sentAt})
          Gift(
            id: id,
            message: message,
            pulls: pulls,
            stars: gift['stars'] as int? ?? 0,
            sentAt: DateTime.parse(sentAt),
          )
        else
          throw const FormatException('Unexpected gift.'),
    ],
    _ => throw const FormatException('Unexpected gifts.'),
  };

  @override
  Future<void> acceptGift(Gift gift) async {
    final server = this.server;
    _gifts = _parseGifts(await _post('/servers/${server.code}/gifts/${gift.id}/accept'));
    _setGacha(await _get('/servers/${server.code}/gacha'));
    notifyListeners();
  }

  static Suggestion _parseSuggestion(Object? json) => switch (json) {
    {
      'id': String id,
      'kind': String kind,
      'title': String title,
      'description': String description,
      'author': String author,
      'created_at': String createdAt,
      'votes': int votes,
      'voted': bool voted,
      'yours': bool yours,
      'removable': bool removable,
    } =>
      Suggestion(
        id: id,
        kind: SuggestionKind.values.byName(kind),
        title: title,
        description: description,
        author: author,
        createdAt: DateTime.parse(createdAt),
        votes: votes,
        voted: voted,
        yours: yours,
        removable: removable,
      ),
    _ => throw const FormatException('Unexpected suggestion.'),
  };

  @override
  Future<List<Suggestion>> suggestions() async => switch (await _get('/servers/${server.code}/suggestions')) {
    List suggestions => [for (final s in suggestions) _parseSuggestion(s)],
    _ => throw const FormatException('Unexpected suggestions.'),
  };

  @override
  Future<Suggestion> suggest({
    required SuggestionKind kind,
    required String title,
    required String description,
  }) async => _parseSuggestion(
    await _post('/servers/${server.code}/suggestions', {
      'kind': kind.name,
      'title': title.trim(),
      'description': description.trim(),
    }),
  );

  @override
  Future<Suggestion> voteOn(Suggestion suggestion, {required bool up}) async {
    final path = '/servers/${server.code}/suggestions/${suggestion.id}/vote';
    return _parseSuggestion(up ? await _put(path, const {}) : await _delete(path));
  }

  @override
  Future<void> removeSuggestion(Suggestion suggestion) async {
    await _delete('/servers/${server.code}/suggestions/${suggestion.id}');
  }

  @override
  Future<List<AdminDrawing>> serverDrawings(String serverCode) async =>
      switch (await _get('/manage/servers/$serverCode/drawings')) {
        List drawings => [
          for (final drawing in drawings)
            if (drawing case {
              'id': String id,
              'day': int? day,
              'date': String? date,
              'artist': String artist,
              'subject': String subject,
              'title': String title,
              'rarity': String rarity,
            })
              AdminDrawing(
                id: id,
                day: day,
                date: date == null ? null : DateTime.parse('${date}T00:00:00Z'),
                artist: artist,
                subject: subject,
                title: title,
                rarity: Rarity.values.asNameMap()[rarity] ?? (throw FormatException('Unknown rarity $rarity.')),
              )
            else
              throw const FormatException('Unexpected drawing.'),
        ],
        _ => throw const FormatException('Unexpected drawings.'),
      };

  @override
  Future<Sketch> drawingSketch(AdminDrawing drawing) async =>
      _sketches[drawing.id] ??= await _sketch(drawing.id, '/manage/characters/${drawing.id}/sketch');

  @override
  Future<List<GiftServer>> giftServers() async => switch (await _get('/manage/servers')) {
    List servers => [
      for (final server in servers)
        if (server case {'code': String code, 'speed': bool speed, 'launched': bool launched, 'players': List players})
          GiftServer(
            code: code,
            speed: speed,
            launched: launched,
            players: [
              for (final player in players)
                if (player case {'position': int position, 'name': String name, 'joined': bool joined})
                  (position: position, name: name, joined: joined)
                else
                  throw const FormatException('Unexpected player.'),
            ],
          )
        else
          throw const FormatException('Unexpected server.'),
    ],
    _ => throw const FormatException('Unexpected servers.'),
  };

  @override
  Future<int> sendGift({
    required String message,
    required int pulls,
    int stars = 0,
    String? serverCode,
    List<int>? positions,
  }) async {
    final json = await _post('/manage/gifts', {
      'message': message,
      'pulls': pulls,
      'stars': stars,
      'server_code': ?serverCode,
      'positions': ?positions,
    });
    final sent = switch (json) {
      {'recipients': int recipients} => recipients,
      _ => throw const FormatException('Unexpected gift response.'),
    };
    // You may be one of them.
    if (_phase == GamePhase.daily) await refreshDay();
    return sent;
  }

  int _day = 0;
  bool _promptsToday = true;
  DateTime? _dayEndsAt;
  bool _sessionOver = false;

  @override
  bool get promptsToday => _promptsToday;

  @override
  DateTime? get dayEndsAt => _dayEndsAt;

  @override
  bool get sessionOver => _sessionOver;
  DailyTheme _dayTheme = DailyTheme.forest;
  DailyTheme _promptTheme = DailyTheme.forest;
  String? _promptHint;

  @override
  DailyTheme get promptTheme => _promptTheme;

  @override
  String? get promptHint => _promptHint;
  ChallengerPrompt? _yourPrompt;
  ChallengerPrompt? _promptToDraw;
  CharacterCard? _yourChallenger;
  Set<String> _dayEnded = const {};
  CharacterCard? _fightChallenger;
  Player? _hurrySentTo;
  List<HurryPlan> _incomingHurries = const [];
  FightSetup? _yourFight;
  Set<String> _resting = const {};
  List<BoostTarget> _boostTargets = const [];
  bool _boostForfeited = false;
  WeeklyHero? _weeklyHero;
  List<ChallengerRecord> _challengers = const [];

  @override
  WeeklyHero? get weeklyHero => _weeklyHero;

  @override
  List<ChallengerRecord> get challengers => _challengers;

  Future<void> _setChallengers(ServerSession server, Object? json) async {
    if (json is! List) throw const FormatException('Unexpected challengers response.');
    _challengers = [
      for (final record in json)
        if (record case {'character': final Object character, 'fights': int fights, 'wins': int wins})
          ChallengerRecord(
            card: await _card(server, character),
            fights: fights,
            wins: wins,
            starsToCollect: record['stars_to_collect'] as int? ?? 0,
            starsCollected: record['stars_collected'] as int? ?? 0,
          )
        else
          throw const FormatException('Unexpected challenger.'),
    ];
  }

  @override
  Future<void> buyPullWithStars() async {
    _setGacha(await _post('/servers/${server.code}/stars/pull'));
    notifyListeners();
  }

  @override
  Future<void> collectChallengerStars(ChallengerRecord challenger) async {
    final server = this.server;
    await _setChallengers(server, await _post('/servers/${server.code}/challengers/${challenger.card.id}/stars'));
    _setGacha(await _get('/servers/${server.code}/gacha'));
    notifyListeners();
  }

  /// Drawing, fighting and boosting add to the challengers you encountered.
  Future<void> _reloadChallengers(ServerSession server) async =>
      _setChallengers(server, await _get('/servers/${server.code}/challengers'));

  /// A character from the pool, or loaded if it isn't there (yet).
  Future<CharacterCard> _card(ServerSession server, Object? json) async {
    if (json case {'id': String id}) {
      return _pool.where((c) => c.id == id).firstOrNull ?? await _loadCharacter(server, json);
    }
    throw const FormatException('Unexpected character.');
  }

  /// A fight from the API, decided with the challenger's boost stars.
  Future<FightSetup> _parseFight(ServerSession server, Object? json) async {
    if (json case {
      'id': String id,
      'day': int day,
      'owner_position': int owner,
      'challenger': final challenger,
      'fighters': List fighters,
      'outcome': {'boost_stars': int boostStars, 'challenger_extra_stars': int challengerExtraStars},
    }) {
      return FightSetup(
        id: id,
        owner: _seat(server, owner),
        challenger: await _card(server, challenger),
        fighters: [
          for (final fighter in fighters)
            if (fighter case {
              'character': final character,
              'upgrades': List upgrades,
              'element': String? element,
              'extra_stars': int extraStars,
            })
              FighterEntry(
                card: await _card(server, character),
                effects: [
                  for (final effect in upgrades)
                    UpgradeEffect.values.asNameMap()[effect] ?? (throw FormatException('Unknown upgrade $effect.')),
                ],
                element: element == null ? null : ElementKind.values.asNameMap()[element],
                extraStars: extraStars,
              )
            else
              throw const FormatException('Unexpected fighter.'),
        ],
        day: day,
        boostStars: boostStars,
        challengerExtraStars: challengerExtraStars,
      );
    }
    throw const FormatException('Unexpected fight.');
  }

  /// Today's step 1 and 2 from the API; [known] is the challenger you just drew.
  Future<void> _setToday(ServerSession server, Object? json, {Sketch? known}) async {
    if (json case {'day': int day, 'theme': String theme, 'prompt': final prompt, 'day_ended': List ended}) {
      _day = day;
      _dayTheme = _theme(theme);
      _dayEndsAt = switch (json['ends_at']) {
        final String at => DateTime.parse(at),
        _ => null,
      };
      _sessionOver = server.isSpeed && day > SpeedMode.days.length;
      final you = server.players.firstWhere((p) => p.isYou);
      _promptsToday = prompt != null;
      _yourPrompt = null;
      _promptHint = null;
      if (prompt case {
        'hint': String? hint,
        'theme': String promptTheme,
        'subject_position': int? subject,
        'title': String? title,
      }) {
        _promptTheme = _theme(promptTheme);
        _promptHint = hint;
        _yourPrompt = title == null || subject == null
            ? null
            : ChallengerPrompt(
                id: 'prompt-$day-${you.id}',
                author: you,
                subject: _seat(server, subject),
                theme: _promptTheme,
                title: title,
                day: day,
                hint: hint,
              );
      } else if (prompt != null) {
        throw const FormatException('Unexpected prompt.');
      }
      _promptToDraw = null;
      _yourChallenger = null;
      if (json['to_draw'] case {
        'author_position': int author,
        'subject_position': int drawnSubject,
        'title': String drawnTitle,
        'theme': String drawnTheme,
        'hint': String? drawnHint,
        'premade': bool premade,
        'challenger': final challenger,
      }) {
        _promptToDraw = ChallengerPrompt(
          id: 'prompt-${day - 1}-${_seatId(author)}',
          author: _seat(server, author),
          subject: _seat(server, drawnSubject),
          theme: _theme(drawnTheme),
          title: drawnTitle,
          day: day - 1,
          hint: drawnHint,
          premade: premade,
        );
        if (challenger != null) _yourChallenger = await _loadCharacter(server, challenger, known: known);
      } else if (json['to_draw'] != null) {
        throw const FormatException('Unexpected prompt to draw.');
      }
      _dayEnded = {for (final position in ended) _seat(server, position as int).id};
      _fightChallenger = null;
      _yourFight = null;
      _resting = const {};
      if (json['fight'] case {'challenger': final challenger, 'yours': final yours, 'resting': List resting}) {
        _fightChallenger = await _card(server, challenger);
        _yourFight = yours == null ? null : await _parseFight(server, yours);
        _resting = {for (final id in resting) id as String};
      }
      _boostForfeited = json['boost_forfeited'] == true;
      _boostTargets = switch (json['boost']) {
        null => const [],
        {'targets': List targets} => [
          for (final target in targets)
            if (target case {'challenger': final challenger, 'stars': int stars})
              BoostTarget(challenger: await _card(server, challenger), stars: stars)
            else
              throw const FormatException('Unexpected challenger to boost.'),
        ],
        _ => throw const FormatException('Unexpected boost step.'),
      };
      _hurrySentTo = switch (json['hurry_sent_to']) {
        final int position => _seat(server, position),
        _ => null,
      };
      _incomingHurries = [
        for (final hurry in json['incoming_hurries'] as List? ?? const [])
          if (hurry case {'by_position': int by, 'left_seconds': num left})
            HurryPlan(
              by: _seat(server, by).name,
              left: Duration(microseconds: (left * Duration.microsecondsPerSecond).round()),
            )
          else
            throw const FormatException('Unexpected hurry.'),
      ];
      _weeklyHero = switch (json['weekly_hero']) {
        null => null,
        {'character': final character, 'day': int heroDay, 'stars': int stars} => WeeklyHero(
          card: await _card(server, character),
          day: heroDay,
          stars: stars,
        ),
        _ => throw const FormatException('Unexpected weekly hero.'),
      };
      return;
    }
    throw const FormatException('Unexpected day response.');
  }

  /// Copies, upgrades, element and switched off effects of [owned] from the
  /// API's collection entry.
  static OwnedCard _setOwned(OwnedCard owned, Object? json) {
    if (json case {'copies': int copies, 'upgrades': List upgrades, 'element': String? element}) {
      UpgradeEffect effectOf(Object? name) =>
          UpgradeEffect.values.asNameMap()[name] ?? (throw FormatException('Unknown upgrade $name.'));
      owned
        ..copies = copies
        ..unlocked.clear()
        ..unlocked.addAll(upgrades.map(effectOf))
        ..hidden.clear()
        ..hidden.addAll(switch (json['hidden']) {
          final List hidden => hidden.map(effectOf),
          _ => const <UpgradeEffect>[],
        })
        ..element = element == null
            ? null
            : ElementKind.values.asNameMap()[element] ?? (throw FormatException('Unknown element $element.'));
      return owned;
    }
    throw const FormatException('Unexpected character in collection.');
  }

  void _setGacha(Object? json) {
    if (json case {
      'tickets': int tickets,
      'total_pulls': int totalPulls,
      'pulls_until_legend': int untilLegend,
      'beginner_pulls_left': int? beginnerLeft,
      'rate_up': List rateUp,
    }) {
      _tickets = tickets;
      _stars = json['stars'] as int? ?? 0;
      _rateUp = {for (final id in rateUp) id as String};
      _gachaStatus = GachaStatus(
        totalPulls: totalPulls,
        pullsUntilLegend: untilLegend,
        beginnerPullsLeft: beginnerLeft,
      );
    } else {
      throw const FormatException('Unexpected gacha response.');
    }
  }

  static Player _seat(ServerSession server, int position) => server.players.firstWhere(
    (p) => p.id == _seatId(position),
    orElse: () => throw FormatException('Unknown seat $position.'),
  );

  /// The drawing of character [id]: from an earlier visit, or else
  /// downloaded from [path] and kept for the next one. A character's drawing
  /// never changes.
  Future<Sketch> _sketch(String id, String path) async {
    try {
      if (await _sketchStore.read(id) case final String json) return SketchJson.decode(jsonDecode(json));
    } catch (_) {
      // A broken or unreadable copy: download it again.
    }
    final json = await _getRetrying(path);
    final sketch = SketchJson.decode(json);
    unawaited(_keep(id, json));
    return sketch;
  }

  /// Keeps a drawing for the next visit, if the device lets us.
  Future<void> _keep(String id, Object? json) async {
    try {
      await _sketchStore.write(id, jsonEncode(json));
    } catch (_) {
      // Full or unavailable storage: it's downloaded again next time.
    }
  }

  /// A character from the API, with its sketch loaded unless it is [known].
  Future<CharacterCard> _loadCharacter(ServerSession server, Object? json, {Sketch? known}) async {
    if (json case {
      'id': String id,
      'title': String title,
      'rarity': String rarity,
      'prompt': String prompt,
      'artist_position': int artist,
      'subject_position': int subject,
    }) {
      // What you just drew is kept for the next visit, instead of downloaded.
      if (known != null && !_sketches.containsKey(id)) unawaited(_keep(id, SketchJson.encode(known)));
      final sketch = _sketches[id] = known ?? _sketches[id] ?? await _sketch(id, '/characters/$id/sketch');
      final theme = switch (json['theme']) {
        final String name => _theme(name),
        _ => null,
      };
      return CharacterCard(
        id: id,
        subject: _seat(server, subject).name,
        title: title,
        rarity: Rarity.values.asNameMap()[rarity] ?? (throw FormatException('Unknown rarity $rarity.')),
        prompt: SetupPrompt.values.asNameMap()[prompt]?.label ?? 'Challenger: ${theme?.label ?? ''}',
        artist: _seat(server, artist).name,
        sketch: sketch,
        day: switch (json['day']) {
          final int day => day,
          _ => 0,
        },
        theme: theme,
      );
    }
    throw const FormatException('Unexpected character response.');
  }

  void _setPhase(GamePhase phase) {
    _phase = phase;
    notifyListeners();
  }

  // Implemented --------------------------------------------------------------

  @override
  GamePhase get phase => _phase;

  @override
  bool get isMockup => false;

  @override
  String? get signInProblem => _signInProblem;

  @override
  String get suggestedFirstName => _suggestedFirstName;

  @override
  Player get you =>
      _server?.players.where((p) => p.isYou).firstOrNull ?? _account ?? (throw StateError('Not signed up yet.'));

  @override
  ServerSession get server => _server ?? (throw StateError('Not in a server yet.'));

  @override
  Duration get refreshInterval => const Duration(seconds: 5);

  @override
  Future<void> signIn() async {
    if (_api == null) throw StateError(_signInProblem!);
    await _auth.signIn(fresh: _freshSignInNeeded);
  }

  @override
  Future<void> signOut() async {
    // The next player on this device shouldn't find your drawings. Before
    // Auth0, which may leave the page.
    _sketches.clear();
    try {
      await _sketchStore.clear();
    } catch (_) {
      // Nothing kept, or storage unavailable.
    }
    await _auth.signOut();
    _account = null;
    _canEditContent = false;
    _canManageServers = false;
    _server = null;
    _assignments = const [];
    _setupDrawings = {};
    _pool = const [];
    _collection = const [];
    _challengers = const [];
    _tickets = 0;
    _gifts = const [];
    _suggestedFirstName = '';
    _setPhase(GamePhase.signIn);
  }

  @override
  Future<void> signUp(String firstName) async {
    _setAccount(await _put('/me', {'first_name': firstName.trim()}));
    await _loadServer();
  }

  @override
  String get accountName => (_account ?? (throw StateError('Not signed up yet.'))).name;

  @override
  Future<void> rename(String firstName) async {
    _setAccount(await _put('/me', {'first_name': firstName.trim()}));
    notifyListeners();
  }

  @override
  Future<void> createServer(
    List<String> otherNames, {
    String? yourName,
    bool isTest = false,
    bool speed = false,
  }) async => _enterServer(
    await _post('/servers', {
      'other_names': otherNames,
      if (yourName?.trim() case final name? when name.isNotEmpty) 'your_name': name,
      'is_test': isTest,
      'mode': speed ? 'speed' : 'regular',
    }),
  );

  @override
  Future<ServerSession> previewServer(String code) async {
    final json = await _get('/servers/$code');
    if (json is Map && json['phase'] == 'cancelled') throw const ApiException(410, 'This server was cancelled.');
    return _parseServer(json);
  }

  @override
  Future<void> joinServer(ServerSession server, Player seat) async =>
      _enterServer(await _post('/servers/${server.code}/seats/${_seatPosition(seat)}/claim'));

  @override
  String? get serverNotice => _serverNotice;

  @override
  Future<void> refreshServer() async {
    await _enterServer(await _get('/servers/${server.code}'));
  }

  @override
  Future<void> cancelServer() async {
    await _guard(() => _api!.delete('/servers/${server.code}'));
    _leaveServer(null);
  }

  /// Back to creating or joining a server.
  void _leaveServer(String? notice) {
    _server = null;
    _assignments = const [];
    _setupDrawings = {};
    _pool = const [];
    _collection = const [];
    _challengers = const [];
    _tickets = 0;
    _gifts = const [];
    _serverNotice = notice;
    _setPhase(GamePhase.server);
  }

  @override
  Future<void> startSetup() async => _enterServer(await _post('/servers/${server.code}/setup'));

  @override
  List<DrawingAssignment> get assignments => _assignments;

  @override
  CharacterCard? setupDrawing(DrawingAssignment assignment) => _setupDrawings[assignment.id];

  @override
  Future<void> submitSetupDrawing(DrawingAssignment assignment, Sketch sketch, String title) async {
    final json = await _put('/servers/${server.code}/assignments/${_assignmentKey(assignment)}/drawing', {
      'title': title.trim(),
      'sketch': SketchJson.encode(sketch),
    });
    _setupDrawings[assignment.id] = await _loadCharacter(server, json, known: sketch);
    notifyListeners();
  }

  // Not available yet ------------------------------------------------------------

  @override
  List<String> get suggestedPlayerNames => const [];

  @override
  List<CharacterCard> get pool => _pool;

  @override
  int get tickets => _tickets;

  @override
  int get stars => _stars;

  @override
  GachaStatus get gachaStatus => _gachaStatus;

  @override
  Set<String> get rateUp => _rateUp;

  @override
  List<OwnedCard> get collection => _collection.toList()
    ..sort((a, b) {
      final byRarity = b.card.rarity.stars.compareTo(a.card.rarity.stars);
      return byRarity != 0 ? byRarity : a.card.subject.compareTo(b.card.subject);
    });

  @override
  int get day => _day;

  @override
  DailyTheme get theme => _dayTheme;

  @override
  ChallengerPrompt? get yourPrompt => _yourPrompt;

  @override
  ChallengerPrompt? get promptToDraw => _promptToDraw;

  @override
  CharacterCard? get yourChallenger => _yourChallenger;

  @override
  CharacterCard? get fightChallenger => _fightChallenger;

  @override
  FightSetup? get yourFight => _yourFight;

  @override
  Set<String> get restingCharacterIds => _resting;

  @override
  List<BoostTarget> get boostTargets => _boostTargets;

  @override
  bool get boostForfeited => _boostForfeited;

  @override
  List<HurryPlan> get incomingHurries => _incomingHurries;

  @override
  Player? get hurrySentTo => _hurrySentTo;

  @override
  Future<void> launch() async => _enterServer(await _post('/servers/${server.code}/setup/done'));

  @override
  Future<void> submitPrompt(String title, Player subject) async {
    await _setToday(
      server,
      await _post('/servers/${server.code}/today/prompt', {
        'title': title.trim(),
        'subject_position': _seatPosition(subject),
      }),
    );
    // The title earns stars: show them now, not with the next reward.
    _setGacha(await _get('/servers/${server.code}/gacha'));
    notifyListeners();
  }

  @override
  /// The challenger joins the pool and earns a pull.
  Future<void> submitChallenger(Sketch sketch) async {
    final json = await _put('/servers/${server.code}/today/challenger', {'sketch': SketchJson.encode(sketch)});
    await _setToday(server, json, known: sketch);
    await _reloadChallengers(server);
    _setGacha(await _get('/servers/${server.code}/gacha'));
    notifyListeners();
  }

  @override
  Future<void> submitFighters(List<OwnedCard> fighters) async {
    final json = await _put('/servers/${server.code}/today/fighters', {
      'character_ids': [for (final owned in fighters) owned.card.id],
    });
    await _setToday(server, json);
    await _reloadChallengers(server);
    // A win earns a pull and stars.
    _setGacha(await _get('/servers/${server.code}/gacha'));
    notifyListeners();
  }

  @override
  Future<void> setBoosts(Map<String, int> stars) async {
    final json = await _put('/servers/${server.code}/today/boosts', {
      'boosts': [
        for (final MapEntry(key: id, value: n) in stars.entries) {'challenger_id': id, 'stars': n},
      ],
    });
    await _setToday(server, json);
    await _reloadChallengers(server);
    notifyListeners();
  }

  @override
  Future<WeekRanking?> weekRanking() async {
    final server = this.server;
    return switch (await _get('/servers/${server.code}/ranking')) {
      null => null,
      {'day': int day, 'challengers': List challengers} => WeekRanking(
        day: day,
        challengers: [
          for (final entry in challengers)
            if (entry case {'character': final character, 'stars': int stars, 'fights': int fights, 'wins': int wins})
              RankedChallenger(card: await _card(server, character), stars: stars, fights: fights, wins: wins)
            else
              throw const FormatException('Unexpected ranked challenger.'),
        ],
      ),
      _ => throw const FormatException('Unexpected ranking.'),
    };
  }

  @override
  Future<WeekWinRates?> winRates() async {
    final server = this.server;
    if (server.isSpeed) return null;
    return switch (await _get('/servers/${server.code}/win-rates')) {
      {'from_day': int fromDay, 'to_day': int toDay, 'win_rates': List rates} => WeekWinRates(
        fromDay: fromDay,
        toDay: toDay,
        rates: [
          for (final rate in rates)
            if (rate case {
              'player_position': int player,
              'against_position': int against,
              'fights': int fights,
              'wins': int wins,
            })
              WinRate(player: _seat(server, player), against: _seat(server, against), fights: fights, wins: wins)
            else
              throw const FormatException('Unexpected win rate.'),
        ],
      ),
      _ => throw const FormatException('Unexpected win rates.'),
    };
  }

  @override
  Future<List<FightDay>> fightDays() async => switch (await _get('/servers/${server.code}/fights')) {
    List days => [
      for (final day in days)
        if (day case {'day': int number, 'date': String date})
          FightDay(day: number, date: DateTime.parse('${date}T00:00:00Z'))
        else
          throw const FormatException('Unexpected fight day.'),
    ],
    _ => throw const FormatException('Unexpected fight days.'),
  };

  @override
  Future<List<FightSetup>> fightsOn(int day) async {
    final server = this.server;
    return switch (await _get('/servers/${server.code}/fights/$day')) {
      List fights => [for (final fight in fights) await _parseFight(server, fight)],
      _ => throw const FormatException('Unexpected fights.'),
    };
  }

  @override
  Future<bool> sendHurry(Player target) async {
    final Object? json;
    try {
      json = await _post('/servers/${server.code}/today/hurry', {'target_position': _seatPosition(target)});
    } on ApiException catch (error) {
      if (error.statusCode == 409) return false;
      rethrow;
    }
    await _setToday(server, json);
    notifyListeners();
    return true;
  }

  @override
  Future<List<PullOutcome>> pull(int count, {GachaBanner banner = GachaBanner.standard}) async {
    final json = await _post('/servers/${server.code}/pulls', {'count': count, 'banner': banner.name});
    if (json case {'outcomes': List outcomes, 'gacha': final gacha}) {
      final byId = {for (final card in _pool) card.id: card};
      final results = [
        for (final outcome in outcomes)
          if (outcome case {
            'character': {'id': String id},
            'is_new': bool isNew,
            'copies': int copies,
          } when byId.containsKey(id))
            PullOutcome(card: byId[id]!, isNew: isNew, copies: copies)
          else
            throw const FormatException('Unexpected pull outcome.'),
      ];
      for (final result in results) {
        final owned = _collection.where((o) => o.card.id == result.card.id).firstOrNull;
        if (owned == null) {
          _collection = [..._collection, OwnedCard(result.card)..copies = result.copies];
        } else {
          owned.copies = result.copies;
        }
      }
      _setGacha(gacha);
      notifyListeners();
      return results;
    }
    throw const FormatException('Unexpected pulls response.');
  }

  @override
  Future<void> unlockNextUpgrade(OwnedCard owned, {ElementKind? element}) async {
    final json = await _post('/servers/${server.code}/collection/${owned.card.id}/upgrades', {
      if (element != null) 'element': element.name,
    });
    _setOwned(owned, json);
    notifyListeners();
  }

  @override
  Future<void> changeElement(OwnedCard owned, ElementKind element) async {
    final json = await _put('/servers/${server.code}/collection/${owned.card.id}/element', {'element': element.name});
    _setOwned(owned, json);
    notifyListeners();
  }

  @override
  Future<void> setEffectShown(OwnedCard owned, UpgradeEffect effect, {required bool shown}) async {
    final hidden = {...owned.hidden};
    shown ? hidden.remove(effect) : hidden.add(effect);
    final json = await _put('/servers/${server.code}/collection/${owned.card.id}/effects', {
      'hidden': [
        for (final e in UpgradeEffect.values)
          if (hidden.contains(e)) e.name,
      ],
    });
    _setOwned(owned, json);
    notifyListeners();
  }

  @override
  bool get canAdvanceDay => (_server?.isTest == true || _server?.isSpeed == true) && _server!.isAdmin;

  @override
  Future<void> advanceDay() async {
    await _post('/servers/${server.code}/days/next');
    await refreshDay();
  }

  @override
  bool get canEndDay => _server?.isTest == true || (_server?.isSpeed == true && !sessionOver);

  @override
  Set<String> get dayEnded => _dayEnded;

  @override
  Future<void> endDay() async {
    await _post('/servers/${server.code}/today/end');
    await refreshDay();
  }

  /// A new day brings new challengers to the pool, so everything reloads.
  @override
  Future<void> refreshDay() async {
    await _loadPool(server);
    notifyListeners();
  }
}
