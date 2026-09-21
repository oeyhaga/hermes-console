import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/models/agent_task_list.dart';
import 'package:hermes_android/core/services/session_reconciler.dart';
import 'package:hermes_android/core/theme/app_theme.dart';
import 'package:hermes_android/core/widgets/agent_task_widgets.dart';
import 'package:hermes_android/core/widgets/chat_event_cards.dart';
import 'package:hermes_android/l10n/app_localizations.dart';

AgentTaskList _list(
  List<(String, String, String)> rows, {
  int revision = 1,
  Map<String, String> parents = const {},
}) => AgentTaskList.tryParse({
  'revision': revision,
  'todos': [
    for (final row in rows)
      {
        'id': row.$1,
        'content': row.$2,
        'status': row.$3,
        if (parents.containsKey(row.$1)) 'parent': parents[row.$1],
      },
  ],
})!;

AgentTaskList _running() => _list([
  ('1', 'Read the failing test', 'completed'),
  ('2', 'Patch the parser', 'in_progress'),
  ('3', 'Add regression test', 'pending'),
  ('4', 'Try the cache flag', 'cancelled'),
  ('5', 'Update the changelog', 'pending'),
]);

AgentTaskList _finished({int revision = 9}) => _list([
  ('1', 'Read the failing test', 'completed'),
  ('2', 'Patch the parser', 'completed'),
  ('3', 'Try the cache flag', 'cancelled'),
], revision: revision);

Widget _host(
  Widget child, {
  ThemeData? theme,
  String locale = 'en',
  double textScale = 1,
  Size size = const Size(320, 640),
  bool disableAnimations = true,
}) => MaterialApp(
  locale: Locale(locale),
  localizationsDelegates: Strings.localizationsDelegates,
  supportedLocales: Strings.supportedLocales,
  theme: theme ?? AppTheme.hermesRedDark,
  home: MediaQuery(
    data: MediaQueryData(
      size: size,
      textScaler: TextScaler.linear(textScale),
      disableAnimations: disableAnimations,
    ),
    child: Scaffold(
      body: Align(alignment: Alignment.bottomCenter, child: child),
    ),
  ),
);

void _narrow(WidgetTester tester) {
  tester.view.physicalSize = const Size(320, 640);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

Finder get _pill => find.byKey(const ValueKey('agent-task-pill'));
Finder get _pillIdle => find.byKey(const ValueKey('agent-task-pill-idle'));

void main() {
  group('AgentTaskPill', () {
    testWidgets('shows counts and the in-progress task as subtitle', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(AgentTaskPill(tasks: _running(), turnActive: true, onTap: () {})),
      );
      await tester.pump();
      expect(_pill, findsOneWidget);
      // cancelled work counts on neither side: 1 of 4
      expect(find.text('Tasks 1/4'), findsOneWidget);
      expect(find.text('Patch the parser'), findsOneWidget);
      final ring = tester.widget<CircularProgressIndicator>(
        find.byKey(const ValueKey('agent-task-pill-ring')),
      );
      expect(ring.value, closeTo(0.25, 1e-9));
    });

    testWidgets('localised to Spanish', (tester) async {
      await tester.pumpWidget(
        _host(
          AgentTaskPill(tasks: _running(), turnActive: true, onTap: () {}),
          locale: 'es',
        ),
      );
      await tester.pump();
      expect(find.text('Tareas 1/4'), findsOneWidget);
    });

    testWidgets('collapses to zero without a live turn, list or open items', (
      tester,
    ) async {
      Future<Size> sizeOf(AgentTaskList tasks, bool active) async {
        await tester.pumpWidget(
          _host(AgentTaskPill(tasks: tasks, turnActive: active, onTap: () {})),
        );
        await tester.pump();
        return tester.getSize(find.byType(AgentTaskPill));
      }

      expect((await sizeOf(_running(), false)).height, 0);
      expect(_pill, findsNothing);
      expect((await sizeOf(AgentTaskList.empty, true)).height, 0);
      expect((await sizeOf(_finished(), false)).height, 0);
      expect((await sizeOf(_running(), true)).height, greaterThan(0));
    });

    testWidgets('tap opens the list', (tester) async {
      var taps = 0;
      await tester.pumpWidget(
        _host(
          AgentTaskPill(
            tasks: _running(),
            turnActive: true,
            onTap: () => taps++,
          ),
        ),
      );
      await tester.pump();
      await tester.tap(_pill);
      expect(taps, 1);
    });

    testWidgets(
      'finishing while visible shows the check, lingers, then leaves',
      (tester) async {
        Widget pill(AgentTaskList tasks, {bool active = true}) => _host(
          AgentTaskPill(
            tasks: tasks,
            turnActive: active,
            onTap: () {},
            lingerAfterFinished: const Duration(seconds: 4),
          ),
        );
        await tester.pumpWidget(pill(_running()));
        await tester.pump();
        expect(
          find.byKey(const ValueKey('agent-task-pill-ring')),
          findsOneWidget,
        );

        await tester.pumpWidget(pill(_finished()));
        await tester.pump();
        expect(
          find.byKey(const ValueKey('agent-task-pill-done')),
          findsOneWidget,
        );
        expect(find.text('Tasks 2/2'), findsOneWidget);
        expect(find.text('All done'), findsOneWidget);

        // The turn ends; the finished pill still lingers its full 4 s.
        await tester.pumpWidget(pill(_finished(), active: false));
        await tester.pump(const Duration(seconds: 3));
        expect(_pill, findsOneWidget);
        await tester.pump(const Duration(seconds: 2));
        expect(_pill, findsNothing);
        expect(_pillIdle, findsOneWidget);

        // A new plan brings it back.
        await tester.pumpWidget(pill(_running(), active: true));
        await tester.pump();
        expect(_pill, findsOneWidget);
      },
    );

    testWidgets('a finished list found on open does not flash a pill', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(
          AgentTaskPill(tasks: _finished(), turnActive: false, onTap: () {}),
        ),
      );
      await tester.pump();
      expect(_pill, findsNothing);
    });

    testWidgets('text scale 2.0 at 320dp stays one line and never overflows', (
      tester,
    ) async {
      _narrow(tester);
      await tester.pumpWidget(
        _host(
          AgentTaskPill(
            tasks: _list([
              (
                '1',
                'A very very long task title that would never fit',
                'in_progress',
              ),
            ]),
            turnActive: true,
            onTap: () {},
          ),
          textScale: 2,
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(
        find.byKey(const ValueKey('agent-task-pill-subtitle')),
        findsNothing,
      );
      final rect = tester.getRect(_pill);
      expect(rect.left, greaterThanOrEqualTo(0));
      expect(rect.right, lessThanOrEqualTo(320));
      expect(rect.height, lessThan(120));
    });

    testWidgets('semantics: one button node naming progress and current task', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(
        _host(AgentTaskPill(tasks: _running(), turnActive: true, onTap: () {})),
      );
      await tester.pump();
      final node = tester.getSemantics(
        find.bySemanticsLabel('Tasks 1/4. Patch the parser'),
      );
      expect(node.label, 'Tasks 1/4. Patch the parser');
      expect(node.hint, 'Show the task list');
      expect(node.flagsCollection.isButton, isTrue);
      handle.dispose();
    });
  });

  group('AgentTaskChecklist', () {
    testWidgets('each status has its own icon and text treatment', (
      tester,
    ) async {
      await tester.pumpWidget(_host(AgentTaskCardBody(tasks: _running())));
      await tester.pump();
      for (final key in const [
        'agent-task-icon-completed',
        'agent-task-icon-in-progress',
        'agent-task-icon-pending',
        'agent-task-icon-cancelled',
      ]) {
        expect(find.byKey(ValueKey(key)), findsWidgets, reason: key);
      }
      TextStyle styleOf(String text) =>
          tester.widget<Text>(find.text(text)).style!;
      expect(
        styleOf('Read the failing test').decoration,
        TextDecoration.lineThrough,
      );
      expect(
        styleOf('Try the cache flag').decoration,
        isNot(TextDecoration.lineThrough),
      );
      expect(styleOf('Try the cache flag').fontStyle, FontStyle.italic);
      expect(styleOf('Patch the parser').fontWeight, FontWeight.w600);
      expect(find.byKey(const ValueKey('agent-task-header')), findsOneWidget);
      final header = tester.widget<Text>(
        find.byKey(const ValueKey('agent-task-header')),
      );
      expect(header.textSpan!.toPlainText(), 'Tasks 1/4 · 1 cancelled');
    });

    testWidgets('reduced motion swaps the spinner for a static mark', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(AgentTaskCardBody(tasks: _running()), disableAnimations: true),
      );
      await tester.pump();
      expect(
        tester.widget(
          find.byKey(const ValueKey('agent-task-icon-in-progress')),
        ),
        isA<Icon>(),
      );
      await tester.pumpWidget(
        _host(AgentTaskCardBody(tasks: _running()), disableAnimations: false),
      );
      await tester.pump();
      expect(
        tester.widget(
          find.byKey(const ValueKey('agent-task-icon-in-progress')),
        ),
        isA<SizedBox>(),
      );
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('subtasks are nested under their parent', (tester) async {
      final tasks = _list(
        [
          ('p', 'Parent', 'in_progress'),
          ('o', 'Other root', 'pending'),
          ('k', 'Kid', 'pending'),
        ],
        parents: {'k': 'p'},
      );
      await tester.pumpWidget(_host(AgentTaskCardBody(tasks: tasks)));
      await tester.pump();
      double top(String id) =>
          tester.getTopLeft(find.byKey(ValueKey('agent-task-row-$id'))).dy;
      double left(String id) => tester
          .getTopLeft(
            find
                .descendant(
                  of: find.byKey(ValueKey('agent-task-row-$id')),
                  matching: find.byType(Icon),
                )
                .first,
          )
          .dx;
      expect(top('p'), lessThan(top('k')));
      expect(top('k'), lessThan(top('o')));
      expect(left('k'), greaterThan(left('p')));
    });

    testWidgets('semantics: one node per row with a status word', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(_host(AgentTaskCardBody(tasks: _running())));
      await tester.pump();
      expect(
        tester
            .getSemantics(find.byKey(const ValueKey('agent-task-row-2')))
            .label,
        'in progress: Patch the parser',
      );
      expect(
        tester
            .getSemantics(find.byKey(const ValueKey('agent-task-row-4')))
            .label,
        'cancelled: Try the cache flag',
      );
      expect(
        tester
            .getSemantics(find.byKey(const ValueKey('agent-task-header')))
            .label,
        '1 of 4 tasks completed, 1 cancelled',
      );
      handle.dispose();
    });

    testWidgets('an empty list says so instead of showing an empty card', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(AgentTaskCardBody(tasks: AgentTaskList.empty)),
      );
      await tester.pump();
      expect(find.text('The agent has no active tasks.'), findsOneWidget);
    });

    testWidgets('text scale 2.0 at 320dp wraps long rows without overflow', (
      tester,
    ) async {
      _narrow(tester);
      final tasks = _list([
        for (var i = 0; i < 8; i++)
          (
            '$i',
            'Task number $i with a really long description ' * 3,
            i == 2 ? 'in_progress' : 'pending',
          ),
      ]);
      await tester.pumpWidget(
        _host(
          SizedBox(height: 600, child: AgentTaskCardBody(tasks: tasks)),
          textScale: 2,
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
      final rect = tester.getRect(find.byType(AgentTaskCardBody));
      expect(rect.right, lessThanOrEqualTo(320));
    });

    testWidgets('omitted items are announced', (tester) async {
      final tasks = AgentTaskList(
        revision: 1,
        items: _running().items,
        omitted: 7,
      );
      await tester.pumpWidget(_host(AgentTaskCardBody(tasks: tasks)));
      await tester.pump();
      expect(find.text('+7 more'), findsOneWidget);
    });
  });

  group('all themes', () {
    double contrast(Color a, Color b) {
      final la = a.computeLuminance();
      final lb = b.computeLuminance();
      final hi = la > lb ? la : lb;
      final lo = la > lb ? lb : la;
      return (hi + 0.05) / (lo + 0.05);
    }

    for (final preset in AppTheme.presets) {
      testWidgets('${preset.id}: icons use theme tokens and stay legible', (
        tester,
      ) async {
        final theme = AppTheme.fromId(preset.id);
        await tester.pumpWidget(
          _host(
            Material(
              color: preset.colors.surface,
              child: SizedBox(
                width: 320,
                child: AgentTaskCardBody(tasks: _running()),
              ),
            ),
            theme: theme,
          ),
        );
        await tester.pump();
        final colors = theme.hermes;
        Color iconColor(String key) =>
            tester.widget<Icon>(find.byKey(ValueKey(key)).first).color!;
        expect(iconColor('agent-task-icon-completed'), colors.success);
        expect(iconColor('agent-task-icon-pending'), colors.textSecondary);
        expect(iconColor('agent-task-icon-cancelled'), colors.textSecondary);
        expect(
          tester
              .widget<Icon>(
                find.byKey(const ValueKey('agent-task-icon-in-progress')),
              )
              .color,
          colors.accent,
        );
        // Non-text UI contrast (WCAG 1.4.11) against the surface they sit on.
        for (final entry in {
          'success': colors.success,
          'accent': colors.accent,
          'textSecondary': colors.textSecondary,
        }.entries) {
          expect(
            contrast(entry.value, colors.surface),
            greaterThanOrEqualTo(3.0),
            reason: '${preset.id}: ${entry.key} vs surface',
          );
        }
        // Row text is readable too.
        expect(
          contrast(colors.textPrimary, colors.surface),
          greaterThanOrEqualTo(4.5),
        );
        expect(tester.takeException(), isNull);
      });
    }
  });

  group('turn activity block integration', () {
    Map<String, dynamic> assistant(
      String stepId, {
      String label = 'todo_list',
    }) => {
      'role': 'assistant',
      'content': 'done',
      assistantActivityTraceKey: [
        {'kind': 'tool', 'label': label, 'status': 'completed', 'id': stepId},
      ],
    };

    test('the checklist belongs to the newest todo_list step', () {
      expect(
        latestAgentTaskStepId([
          {'role': 'assistant', 'content': 'plain'},
          assistant('new'),
          assistant('old'),
        ]),
        'new',
      );
      expect(
        latestAgentTaskStepId([assistant('x', label: 'terminal')]),
        isNull,
      );
      expect(
        latestAgentTaskStepId([assistant('legacy', label: 'todo')]),
        'legacy',
      );
      expect(latestAgentTaskStepId(const []), isNull);
    });

    Widget card(
      List<ChatTraceEvent> events, {
      AgentTaskList? tasks,
      String? owner,
      bool active = false,
      double textScale = 1,
    }) => _host(
      AgentTaskScope(
        tasks: tasks,
        ownerStepId: owner,
        child: SingleChildScrollView(
          child: ThinkingTraceCard(events: events, active: active),
        ),
      ),
      textScale: textScale,
    );

    ChatTraceEvent todoEvent(String id) =>
        ChatTraceEvent(id: id, label: 'todo_list', status: 'completed');

    testWidgets('only the owning turn shows the chip and the list', (
      tester,
    ) async {
      await tester.pumpWidget(
        card([todoEvent('other')], tasks: _running(), owner: 'mine'),
      );
      await tester.pump();
      expect(find.byKey(const ValueKey('agent-task-chip')), findsNothing);

      await tester.pumpWidget(
        card([todoEvent('mine')], tasks: _running(), owner: 'mine'),
      );
      await tester.pump();
      expect(find.byKey(const ValueKey('agent-task-chip')), findsOneWidget);
      expect(find.text('1/4'), findsOneWidget);
      // collapsed by default: the list only appears once expanded
      expect(find.byKey(const ValueKey('agent-task-checklist')), findsNothing);
      await tester.tap(find.byIcon(Icons.expand_more));
      await tester.pump(const Duration(milliseconds: 250));
      expect(
        find.byKey(const ValueKey('agent-task-checklist')),
        findsOneWidget,
      );
      expect(find.text('Patch the parser'), findsOneWidget);
      // the turn ended with open items: flagged incomplete like the TUI archive
      expect(
        tester
            .widget<Text>(find.byKey(const ValueKey('agent-task-header')))
            .textSpan!
            .toPlainText(),
        contains('incomplete'),
      );
    });

    testWidgets('a finished list is not marked incomplete', (tester) async {
      await tester.pumpWidget(
        card([todoEvent('mine')], tasks: _finished(), owner: 'mine'),
      );
      await tester.pump();
      await tester.tap(find.byIcon(Icons.expand_more));
      await tester.pump(const Duration(milliseconds: 250));
      final text = tester
          .widget<Text>(find.byKey(const ValueKey('agent-task-header')))
          .textSpan!
          .toPlainText();
      expect(text, isNot(contains('incomplete')));
      expect(text, startsWith('Tasks 2/2'));
    });

    testWidgets('no scope, no owner or an empty list changes nothing', (
      tester,
    ) async {
      await tester.pumpWidget(card([todoEvent('mine')]));
      await tester.pump();
      expect(find.byKey(const ValueKey('agent-task-chip')), findsNothing);
      await tester.pumpWidget(
        card([todoEvent('mine')], tasks: AgentTaskList.empty, owner: 'mine'),
      );
      await tester.pump();
      expect(find.byKey(const ValueKey('agent-task-chip')), findsNothing);
    });

    testWidgets('copying the trace never includes the task text', (
      tester,
    ) async {
      String? clipboard;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            clipboard = (call.arguments as Map)['text'] as String?;
          }
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      await tester.pumpWidget(
        card([todoEvent('mine')], tasks: _running(), owner: 'mine'),
      );
      await tester.pump();
      await tester.tap(find.byIcon(Icons.expand_more));
      await tester.pump(const Duration(milliseconds: 250));
      await tester.tap(find.byKey(const ValueKey('thinking-trace-copy')));
      await tester.pump();
      expect(clipboard, isNotNull);
      expect(clipboard, contains('todo_list'));
      expect(clipboard, isNot(contains('Patch the parser')));
      expect(clipboard, isNot(contains('changelog')));
    });

    testWidgets('text scale 2.0 at 320dp keeps header, chip and list inside', (
      tester,
    ) async {
      _narrow(tester);
      await tester.pumpWidget(
        card(
          [todoEvent('mine')],
          tasks: _running(),
          owner: 'mine',
          textScale: 2,
        ),
      );
      await tester.pump();
      await tester.tap(find.byIcon(Icons.expand_more));
      await tester.pump(const Duration(milliseconds: 250));
      expect(tester.takeException(), isNull);
      expect(
        tester
            .getRect(find.byKey(const ValueKey('agent-task-checklist')))
            .right,
        lessThanOrEqualTo(320),
      );
    });
  });

  group('showAgentTaskCard', () {
    testWidgets('updates live while open and shows every state', (
      tester,
    ) async {
      var current = _list([
        ('1', 'Plan the work', 'in_progress'),
        ('2', 'Do the work', 'pending'),
      ]);
      final changes = ValueNotifier<int>(0);
      await tester.pumpWidget(
        _host(
          Builder(
            builder: (context) => TextButton(
              onPressed: () => showAgentTaskCard(
                context,
                changes: Stream<Object?>.periodic(
                  const Duration(milliseconds: 50),
                  (n) => n,
                ),
                read: () => current,
              ),
              child: const Text('open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 60));
      expect(find.byKey(const ValueKey('agent-task-card')), findsOneWidget);
      expect(find.text('Tasks 0/2'), findsOneWidget);

      current = _list([
        ('1', 'Plan the work', 'completed'),
        ('2', 'Do the work', 'in_progress'),
      ], revision: 2);
      await tester.pump(const Duration(milliseconds: 60));
      expect(find.text('Tasks 1/2'), findsOneWidget);

      current = _list([
        ('1', 'Plan the work', 'completed'),
        ('2', 'Do the work', 'completed'),
      ], revision: 3);
      await tester.pump(const Duration(milliseconds: 60));
      expect(find.text('Tasks 2/2'), findsOneWidget);
      changes.dispose();
      await tester.pumpWidget(const SizedBox.shrink());
    });
  });
}
