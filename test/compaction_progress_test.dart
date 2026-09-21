import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/models/activity_snapshot.dart';
import 'package:hermes_android/core/models/compaction_progress.dart';
import 'package:hermes_android/core/services/compaction_tracker.dart';
import 'package:hermes_android/core/theme/app_theme.dart';
import 'package:hermes_android/core/widgets/activity_panel.dart';
import 'package:hermes_android/core/widgets/activity_pill.dart';
import 'package:hermes_android/l10n/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

final DateTime _t0 = DateTime(2026, 9, 21, 12);

class _Clock {
  _Clock(this.now);
  DateTime now;
  void advance(Duration d) => now = now.add(d);
}

CompactionSample _sample(int seconds, [int? tokens]) =>
    CompactionSample(durationMs: seconds * 1000, tokensBefore: tokens);

void main() {
  group('CompactionProgress', () {
    test(
      'sin estimación solo hay tiempo transcurrido: nunca un porcentaje',
      () {
        final progress = CompactionProgress(startedAt: _t0, manual: false);
        final now = _t0.add(const Duration(seconds: 23));
        expect(progress.elapsed(now), const Duration(seconds: 23));
        expect(progress.fraction(now), isNull);
        expect(progress.remaining(now), isNull);
      },
    );

    test('con estimación: fracción = transcurrido/típico, tope 95 %', () {
      final progress = CompactionProgress(
        startedAt: _t0,
        manual: true,
        estimate: const Duration(seconds: 40),
      );
      expect(progress.fraction(_t0.add(const Duration(seconds: 10))), 0.25);
      expect(
        progress.fraction(_t0.add(const Duration(seconds: 500))),
        CompactionProgress.maxFraction,
      );
      expect(
        progress.remaining(_t0.add(const Duration(seconds: 30))),
        const Duration(seconds: 10),
      );
      expect(
        progress.remaining(_t0.add(const Duration(seconds: 90))),
        Duration.zero,
      );
    });

    test('terminada: sin fracción, duración fija y resumen exacto', () {
      final done = CompactionProgress(
        startedAt: _t0,
        manual: true,
        estimate: const Duration(seconds: 40),
        tokensBefore: 180000,
        tokensAfter: 42000,
        finishedAt: _t0.add(const Duration(seconds: 38)),
      );
      expect(done.isFinished, isTrue);
      expect(done.duration, const Duration(seconds: 38));
      expect(done.fraction(_t0.add(const Duration(hours: 1))), isNull);
      expect(formatCompactTokens(180000), '180k');
      expect(formatCompactTokens(42000), '42k');
      expect(formatCompactTokens(12400), '12.4k');
      expect(formatCompactTokens(842), '842');
      expect(formatCompactTokens(1200000), '1.2M');
    });
  });

  group('CompactionHistory', () {
    test('mediana de las mediciones; sin historial no hay estimación', () {
      expect(CompactionHistory.empty.estimate(), isNull);
      final history = CompactionHistory([
        _sample(10),
        _sample(30),
        _sample(20),
      ]);
      expect(history.estimate(), const Duration(seconds: 20));
      expect(
        CompactionHistory([_sample(10), _sample(20)]).estimate(),
        const Duration(seconds: 15),
      );
    });

    test('escala por tokens de partida acotada a 0.5x–3x', () {
      final history = CompactionHistory([
        _sample(20, 100000),
        _sample(20, 100000),
        _sample(20, 100000),
      ]);
      expect(
        history.estimate(tokensBefore: 200000),
        const Duration(seconds: 40),
      );
      expect(
        history.estimate(tokensBefore: 1000),
        const Duration(seconds: 10),
        reason: 'no baja de 0.5x',
      );
      expect(
        history.estimate(tokensBefore: 5000000),
        const Duration(seconds: 60),
        reason: 'no sube de 3x',
      );
      // Sin tamaños conocidos no se escala.
      expect(
        CompactionHistory([_sample(20)]).estimate(tokensBefore: 999999),
        const Duration(seconds: 20),
      );
    });

    test(
      'conserva solo las 10 últimas y sobrevive a codificar/decodificar',
      () {
        var history = CompactionHistory.empty;
        for (var i = 1; i <= 14; i++) {
          history = history.add(_sample(i, i * 1000));
        }
        expect(history.samples, hasLength(CompactionHistory.capacity));
        expect(history.samples.first.durationMs, 5000);
        final round = CompactionHistory.decode(history.encode());
        expect(round.samples.map((s) => s.durationMs), [
          for (final s in history.samples) s.durationMs,
        ]);
        expect(CompactionHistory.decode('no json').isEmpty, isTrue);
        expect(
          CompactionHistory.decode('[{"d":-4},{"d":"x"},3]').isEmpty,
          isTrue,
        );
      },
    );
  });

  group('CompactionTracker', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    test('la clave es corta y por conexión+modelo', () {
      expect(
        CompactionHistoryStore.keyFor('conn1', 'openai/gpt-5.5'),
        'hc.compact.v1.conn1.openai/gpt-5.5',
      );
      expect(CompactionHistoryStore.keyFor('c', ''), 'hc.compact.v1.c.-');
    });

    testWidgets(
      'automática: mide, termina y conserva el resumen unos segundos',
      (tester) async {
        final clock = _Clock(_t0);
        final tracker = CompactionTracker(clock: () => clock.now);
        addTearDown(tracker.dispose);
        expect(tracker.current, isNull);
        tracker.sync(
          active: true,
          manual: false,
          historyKey: 'k',
          startedAt: _t0,
          tokensBefore: 180000,
        );
        expect(tracker.running, isTrue);
        expect(tracker.current!.manual, isFalse);
        clock.advance(const Duration(seconds: 38));
        tracker.sync(active: false, manual: false, historyKey: 'k');
        expect(tracker.running, isFalse);
        expect(tracker.current!.isFinished, isTrue);
        expect(tracker.current!.duration, const Duration(seconds: 38));
        // «Después» de una automática: el uso de contexto observado tras el fin.
        tracker.observeContextTokens(42000);
        expect(tracker.current!.tokensAfter, 42000);
        // Un valor que no baja no es evidencia de compactación.
        tracker.observeContextTokens(null);
        await tester.pump(const Duration(seconds: 7));
        expect(tracker.current, isNull, reason: 'se oculta pasado el linger');
      },
    );

    testWidgets('manual: espera el resultado del RPC y lo publica exacto', (
      tester,
    ) async {
      final clock = _Clock(_t0);
      final tracker = CompactionTracker(clock: () => clock.now);
      addTearDown(tracker.dispose);
      tracker.sync(
        active: true,
        manual: true,
        historyKey: 'k',
        startedAt: _t0,
        tokensBefore: 90000,
        messagesBefore: 240,
      );
      clock.advance(const Duration(seconds: 20));
      // La bandera se apaga un instante ANTES de que llegue el resultado.
      tracker.sync(active: false, manual: true, historyKey: 'k');
      expect(tracker.running, isTrue, reason: 'aún se espera el resultado');
      tracker.reportResult(
        tokensBefore: 91234,
        tokensAfter: 20500,
        messagesBefore: 240,
        messagesAfter: 40,
      );
      final done = tracker.current!;
      expect(done.isFinished, isTrue);
      expect(done.tokensBefore, 91234);
      expect(done.tokensAfter, 20500);
      expect(done.messagesAfter, 40);
      expect(done.duration, const Duration(seconds: 20));
      await tester.pump(const Duration(seconds: 7));
      expect(tracker.current, isNull);
    });

    testWidgets('manual sin resultado (abortada, lock, incierta): la barra se '
        'retira sola', (tester) async {
      final tracker = CompactionTracker(clock: () => _t0);
      addTearDown(tracker.dispose);
      tracker.sync(active: true, manual: true, historyKey: 'k');
      tracker.sync(active: false, manual: true, historyKey: 'k');
      expect(tracker.running, isTrue);
      await tester.pump(const Duration(seconds: 4));
      expect(tracker.current, isNull, reason: 'sin barra colgada');
      // Y un resultado tardío ya no resucita nada.
      tracker.reportResult(tokensBefore: 1, tokensAfter: 1);
      expect(tracker.current, isNull);
    });

    testWidgets(
      'aprende la mediana: se guarda y se carga por conexión+modelo',
      (tester) async {
        final clock = _Clock(_t0);
        Future<void> run(CompactionTracker tracker, int seconds) async {
          tracker.sync(
            active: true,
            manual: false,
            historyKey: 'hc.compact.v1.c.m',
            startedAt: clock.now,
            tokensBefore: 100000,
          );
          clock.advance(Duration(seconds: seconds));
          tracker.sync(
            active: false,
            manual: false,
            historyKey: 'hc.compact.v1.c.m',
          );
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 30)),
          );
          await tester.pump(const Duration(seconds: 7));
        }

        final first = CompactionTracker(clock: () => clock.now);
        addTearDown(first.dispose);
        for (final seconds in [10, 30, 20]) {
          await run(first, seconds);
        }
        final prefs = await SharedPreferences.getInstance();
        final stored = prefs.getString('hc.compact.v1.c.m');
        expect(stored, isNotNull);
        expect(CompactionHistory.decode(stored).samples, hasLength(3));

        // Otro tracker (otra sesión de la app) carga el historial y estima.
        final second = CompactionTracker(clock: () => clock.now);
        addTearDown(second.dispose);
        second.sync(
          active: true,
          manual: false,
          historyKey: 'hc.compact.v1.c.m',
          startedAt: clock.now,
          tokensBefore: 100000,
        );
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 30)),
        );
        expect(second.current!.estimate, const Duration(seconds: 20));
        // Otra conexión/modelo no hereda nada.
        final third = CompactionTracker(clock: () => clock.now);
        addTearDown(third.dispose);
        third.sync(
          active: true,
          manual: false,
          historyKey: 'hc.compact.v1.c.other',
          startedAt: clock.now,
        );
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 30)),
        );
        expect(third.current!.estimate, isNull);
      },
    );

    testWidgets('el historial no pisa el tamaño de partida', (tester) async {
      final tracker = CompactionTracker(clock: () => _t0);
      addTearDown(tracker.dispose);
      tracker.sync(
        active: true,
        manual: false,
        historyKey: 'k',
        tokensBefore: 180000,
      );
      tracker.sync(
        active: true,
        manual: false,
        historyKey: 'k',
        tokensBefore: 180000,
      );
      expect(tracker.current!.tokensBefore, 180000);
      tracker.reset();
      expect(tracker.current, isNull);
    });
  });

  group('pastilla y panel de compactación', () {
    Widget app(ActivitySnapshot snapshot, _Clock clock) => MaterialApp(
      locale: const Locale('es'),
      localizationsDelegates: const [
        Strings.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: Strings.supportedLocales,
      theme: AppTheme.hermesRedDark,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(disableAnimations: true),
        child: child!,
      ),
      home: Scaffold(
        body: Align(
          alignment: Alignment.bottomCenter,
          child: ActivityPillHost(snapshot: snapshot, clock: () => clock.now),
        ),
      ),
    );

    String action(WidgetTester tester) => tester
        .widget<Text>(find.byKey(const ValueKey('activity-pill-text')))
        .textSpan!
        .toPlainText();

    testWidgets('sin historial: tiempo + barra indeterminada, sin porcentaje', (
      tester,
    ) async {
      final clock = _Clock(_t0.add(const Duration(seconds: 23)));
      await tester.pumpWidget(
        app(
          ActivitySnapshot(
            compaction: CompactionProgress(startedAt: _t0, manual: false),
          ),
          clock,
        ),
      );
      expect(action(tester), 'Compactando conversación');
      expect(find.textContaining('%'), findsNothing);
      expect(find.textContaining('≈'), findsNothing);
      expect(
        tester
            .widget<Text>(find.byKey(const ValueKey('activity-pill-elapsed')))
            .data,
        '0:23',
      );
      final bar = tester.widget<LinearProgressIndicator>(
        find.byKey(const ValueKey('compaction-bar')),
      );
      // Movimiento reducido: raíl vacío, nunca un relleno inventado.
      expect(bar.value, 0);
      // La barra se superpone: no ensancha la pastilla a todo el ancho.
      expect(
        tester.getSize(find.byKey(const ValueKey('activity-pill'))).width,
        tester.getSize(find.byType(ActivityPillRow)).width,
      );
    });

    testWidgets('con estimación: «≈%» vivo y resto estimado en el panel', (
      tester,
    ) async {
      final clock = _Clock(_t0.add(const Duration(seconds: 30)));
      await tester.pumpWidget(
        app(
          ActivitySnapshot(
            compaction: CompactionProgress(
              startedAt: _t0,
              manual: true,
              tokensBefore: 180000,
              messagesBefore: 240,
              estimate: const Duration(seconds: 60),
            ),
          ),
          clock,
        ),
      );
      expect(action(tester), 'Compactando · ≈50 %');
      expect(
        tester
            .widget<LinearProgressIndicator>(
              find.byKey(const ValueKey('compaction-bar')),
            )
            .value,
        0.5,
      );
      await tester.tap(find.byKey(const ValueKey('activity-pill')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(
        find.byKey(const ValueKey('activity-compaction-title')),
        findsOneWidget,
      );
      expect(find.text('Transcurrido 0:30'), findsOneWidget);
      expect(find.text('≈ 0:30 restante'), findsOneWidget);
      expect(
        find.text('Manual · 240 mensajes · Antes: ~180k tokens'),
        findsOneWidget,
      );
      // El porcentaje jamás llega al 100 % por estimación.
      clock.advance(const Duration(hours: 1));
      await tester.pump(const Duration(seconds: 1));
      expect(find.textContaining('≈95 %'), findsWidgets);
    });

    testWidgets('resultado: «Compactado: 180k → 42k tokens · 38 s»', (
      tester,
    ) async {
      final clock = _Clock(_t0.add(const Duration(seconds: 39)));
      await tester.pumpWidget(
        app(
          ActivitySnapshot(
            compaction: CompactionProgress(
              startedAt: _t0,
              manual: true,
              tokensBefore: 180000,
              tokensAfter: 42000,
              finishedAt: _t0.add(const Duration(seconds: 38)),
            ),
          ),
          clock,
        ),
      );
      expect(action(tester), 'Compactado: 180k → 42k tokens · 38 s');
      // Terminada: sin cronómetro y con la barra llena.
      expect(find.byKey(const ValueKey('activity-pill-elapsed')), findsNothing);
      expect(
        tester
            .widget<LinearProgressIndicator>(
              find.byKey(const ValueKey('compaction-bar')),
            )
            .value,
        1,
      );
      // Sin cifras (automática): solo la duración.
      await tester.pumpWidget(
        app(
          ActivitySnapshot(
            compaction: CompactionProgress(
              startedAt: _t0,
              manual: false,
              finishedAt: _t0.add(const Duration(seconds: 38)),
            ),
          ),
          clock,
        ),
      );
      expect(action(tester), 'Contexto compactado · 38 s');
    });

    testWidgets('mezclada con un turno de fondo: la compactación manda', (
      tester,
    ) async {
      final clock = _Clock(_t0.add(const Duration(seconds: 5)));
      await tester.pumpWidget(
        app(
          ActivitySnapshot(
            turnActive: true,
            turnStartedAt: _t0,
            noActivityHint: true,
            compaction: CompactionProgress(startedAt: _t0, manual: false),
          ),
          clock,
        ),
      );
      expect(action(tester), 'Compactando conversación');
      expect(find.textContaining('Sigo trabajando'), findsNothing);
    });
  });
}
