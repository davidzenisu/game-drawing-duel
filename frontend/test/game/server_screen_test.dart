import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/game/game_app.dart';
import 'package:frontend/game/game_session.dart';
import 'package:frontend/game/screens/lobby_screen.dart';
import 'package:frontend/game/screens/server_screen.dart';
import 'package:frontend/mockup/mock_game_session.dart';

void main() {
  testWidgets('joining comes first, under a note on the game for new players', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final controller = MockGameSession(seed: 1);
    await tester.pumpWidget(GameApp(session: controller, splash: false));
    await tester.enterText(find.byType(TextField), 'Pat');
    await tester.pump();
    await tester.tap(find.text('Finish account'));
    await tester.pumpAndSettle();
    expect(find.byType(ServerScreen), findsOneWidget);

    // The tabs: Join, then Create; Join is open.
    final tabs = tester.widgetList<Tab>(find.byType(Tab)).map((t) => t.text).toList();
    expect(tabs, ['Join server', 'Create server']);
    expect(find.widgetWithText(TextField, 'Server code'), findsOneWidget);

    // The note says what the game is, and that it's all explained later.
    expect(find.textContaining('draw each other as heroes and challengers', findRichText: true), findsOneWidget);
    expect(find.textContaining('explained step by step once you join or create', findRichText: true), findsOneWidget);
    expect(tester.takeException(), isNull, reason: 'fits a phone');

    // Dismissed for good.
    await tester.tap(find.text('Got it'));
    await tester.pumpAndSettle();
    expect(find.textContaining('explained step by step', findRichText: true), findsNothing);
    expect(controller.tutorialsSeen, contains(ServerScreen.introKey));
    await tester.pumpWidget(const SizedBox());
  });

  group('several servers', _severalServers);
}

/// The mockup, on other servers too.
class _OnSeveralServers extends MockGameSession {
  _OnSeveralServers(this.others) : super(seed: 1);

  final List<ServerSummary> others;

  @override
  List<ServerSummary> get myServers => [...super.myServers, ...others];
}

Future<void> _openLobby(WidgetTester tester, MockGameSession controller) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await controller.signUp('Pat');
  await controller.createServer(['Sam', 'Robin', 'Kim', 'Jo']);
  await tester.pumpWidget(GameApp(session: controller, splash: false));
  await tester.pumpAndSettle();
  expect(find.byType(LobbyScreen), findsOneWidget);
}

void _severalServers() {
  testWidgets('from a server, create or join another one, and go back to it', (tester) async {
    final controller = MockGameSession(seed: 1);
    await _openLobby(tester, controller);
    final code = controller.server.code;
    final badge = find.descendant(of: find.byTooltip('Account'), matching: find.byType(Badge));
    expect(tester.widget<Badge>(badge).isLabelVisible, isFalse, reason: 'no other server waits on you');

    await tester.tap(find.byTooltip('Account'));
    await tester.pumpAndSettle();
    expect(find.text('Switch server'), findsOneWidget);
    expect(find.text('On server $code'), findsOneWidget);
    await tester.tap(find.text('Create or join a server'));
    await tester.pumpAndSettle();
    expect(find.byType(ServerScreen), findsOneWidget);

    await tester.tap(find.byTooltip('Back to server $code'));
    await tester.pumpAndSettle();
    expect(find.byType(LobbyScreen), findsOneWidget);
    expect(controller.server.code, code);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('the account menu shows a dot while another server waits on you; the picker lists your servers', (
    tester,
  ) async {
    final controller = _OnSeveralServers([
      const ServerSummary(code: '222222', phase: ServerPhase.running, playerCount: 6, waitingOnYou: true),
      const ServerSummary(code: '333333', phase: ServerPhase.lobby, playerCount: 5, isSpeed: true),
    ]);
    await _openLobby(tester, controller);
    final badge = find.descendant(
      of: find.byTooltip('Account: another server waits on you'),
      matching: find.byType(Badge),
    );
    expect(tester.widget<Badge>(badge).isLabelVisible, isTrue);

    await tester.tap(find.byTooltip('Account: another server waits on you'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Switch server'));
    await tester.pumpAndSettle();
    expect(find.text('Your servers'), findsOneWidget);
    expect(find.text('Server ${controller.server.code}'), findsOneWidget);
    expect(find.textContaining('you are here'), findsOneWidget);
    expect(find.text('Server 222222'), findsOneWidget);
    expect(find.text('Running · 6 players'), findsOneWidget);
    expect(find.text('Your turn'), findsOneWidget);
    expect(find.text('Speed session · Lobby · 5 players'), findsOneWidget);
    expect(tester.takeException(), isNull, reason: 'fits a phone');

    // The mockup plays one server at a time.
    await tester.tap(find.text('Server 222222'));
    await tester.pumpAndSettle();
    expect(find.textContaining('one server at a time'), findsOneWidget);
    expect(find.byType(LobbyScreen), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('on three regular servers, only speed sessions can be created', (tester) async {
    final controller = _OnSeveralServers([
      const ServerSummary(code: '222222', phase: ServerPhase.running, playerCount: 6),
      const ServerSummary(code: '333333', phase: ServerPhase.running, playerCount: 6),
      const ServerSummary(code: '444444', phase: ServerPhase.lobby, playerCount: 5, isSpeed: true),
    ]);
    await _openLobby(tester, controller);
    expect(controller.atServerLimit, isTrue);
    await controller.addServer();
    await tester.pumpAndSettle();
    expect(find.textContaining("You're on 3 servers, the most at once"), findsOneWidget);
    await tester.tap(find.text('Create server'));
    await tester.pumpAndSettle();
    final segments = tester.widget<SegmentedButton<bool>>(find.byType(SegmentedButton<bool>));
    expect(segments.selected, {true});
    expect(segments.segments.first.enabled, isFalse);
    await tester.pumpWidget(const SizedBox());
  });
}
