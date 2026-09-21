import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:hermes_android/core/companion/render/companion_status_indicator.dart';
import 'package:hermes_android/core/theme/app_theme.dart';
import 'package:hermes_android/core/widgets/chat_event_cards.dart';
import 'package:hermes_android/core/widgets/hermes_pill.dart';
import 'package:hermes_android/l10n/app_localizations.dart';

void main() {
  testWidgets('actividad muestra el estado limpio sin puntos ni LIVE', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: Strings.localizationsDelegates,
        supportedLocales: Strings.supportedLocales,
        theme: AppTheme.hermesRedDark,
        home: const MediaQuery(
          data: MediaQueryData(disableAnimations: true),
          child: Scaffold(
            body: ThinkingTraceCard(
              events: [],
              active: true,
              headline: 'Pensando…',
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Pensando'), findsOneWidget);
    expect(find.text('Pensando…'), findsNothing);
    expect(find.text('LIVE'), findsNothing);
    expect(find.byKey(const ValueKey('thinking-shimmer')), findsOneWidget);
    expect(find.byKey(const ValueKey('search-wave-indicator')), findsNothing);
    final companion = tester.widget<CompanionStatusIndicator>(
      find.byType(CompanionStatusIndicator),
    );
    expect(companion.size, ThinkingTraceCard.activeCompanionSize);
    final status = tester.widget<Text>(find.text('Pensando'));
    expect(status.style?.fontSize, 12);
    expect(status.style?.letterSpacing, 0.35);
  });

  testWidgets('el shimmer sustituye el estado anterior sin duplicar texto', (
    tester,
  ) async {
    Widget host(String headline) => MaterialApp(
      locale: const Locale('en'),
      localizationsDelegates: Strings.localizationsDelegates,
      supportedLocales: Strings.supportedLocales,
      theme: AppTheme.hermesRedDark,
      home: MediaQuery(
        data: const MediaQueryData(disableAnimations: false),
        child: Scaffold(
          body: ThinkingTraceCard(
            events: const [],
            active: true,
            headline: headline,
          ),
        ),
      ),
    );

    await tester.pumpWidget(host('Conectando…'));
    await tester.pump();
    expect(find.text('Conectando'), findsOneWidget);

    await tester.pumpWidget(host('Respondiendo…'));
    await tester.pump(const Duration(milliseconds: 120));
    expect(find.byKey(const ValueKey('thinking-shimmer')), findsOneWidget);
    expect(find.text('Conectando'), findsNothing);
    expect(find.text('Respondiendo'), findsOneWidget);
  });

  testWidgets('la mascota sigue destacando cuando ya hay herramientas', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: Strings.localizationsDelegates,
        supportedLocales: Strings.supportedLocales,
        theme: AppTheme.hermesRedDark,
        home: MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: Scaffold(
            body: ThinkingTraceCard(
              events: [
                ChatTraceEvent(
                  id: 'tool-1',
                  label: 'Terminal',
                  status: 'running',
                  preview: 'pwd && ls',
                ),
              ],
              active: true,
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    final companion = tester.widget<CompanionStatusIndicator>(
      find.byType(CompanionStatusIndicator),
    );
    expect(find.text('Running tool'), findsOneWidget);
    expect(find.text('Terminal'), findsNothing);
    expect(find.text('TERMINAL'), findsNothing);
    expect(find.text('Running tools · 0 completed'), findsNothing);
    expect(companion.size, ThinkingTraceCard.activeWithEventsCompanionSize);
    expect(find.text('pwd && ls'), findsNothing);

    final status = tester.widget<Text>(find.text('Running tool'));
    expect(status.style?.fontSize, 12);
    expect(status.style?.letterSpacing, 0.35);

    await tester.tap(find.text('Running tool'));
    await tester.pump(const Duration(milliseconds: 220));
    expect(find.text('Terminal · running'), findsOneWidget);
    expect(find.text('pwd && ls'), findsOneWidget);
  });

  testWidgets('una skill activa usa el titular localizado', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('es'),
        localizationsDelegates: Strings.localizationsDelegates,
        supportedLocales: Strings.supportedLocales,
        theme: AppTheme.hermesRedDark,
        home: Scaffold(
          body: ThinkingTraceCard(
            events: [
              ChatTraceEvent(
                id: 'skill-1',
                label: 'review_changes',
                status: 'running',
                kind: ChatTraceEventKind.skill,
              ),
            ],
            active: true,
          ),
        ),
      ),
    );

    expect(find.text('Ejecutando skill'), findsOneWidget);
    expect(find.text('review_changes'), findsNothing);
  });

  testWidgets('razonamiento terminado queda plegado en la misma tarjeta', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('es'),
        localizationsDelegates: Strings.localizationsDelegates,
        supportedLocales: Strings.supportedLocales,
        theme: AppTheme.hermesRedDark,
        home: Scaffold(
          body: ThinkingTraceCard(
            events: [
              ChatTraceEvent(
                id: 'reasoning-1',
                label: 'Razonamiento',
                status: 'completed',
                preview: 'Primero inspecciono. Luego verifico.',
                kind: ChatTraceEventKind.reasoning,
              ),
            ],
            active: false,
          ),
        ),
      ),
    );

    expect(find.text('Razonamiento'), findsOneWidget);
    expect(find.textContaining('Primero inspecciono'), findsNothing);

    await tester.tap(find.text('Razonamiento'));
    await tester.pumpAndSettle();
    expect(find.text('Primero inspecciono. Luego verifico.'), findsOneWidget);
  });

  testWidgets('duración conocida usa el resumen localizado', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: Strings.localizationsDelegates,
        supportedLocales: Strings.supportedLocales,
        theme: AppTheme.hermesRedDark,
        home: Scaffold(
          body: ThinkingTraceCard(
            events: [
              ChatTraceEvent(
                id: 'reasoning-1',
                label: 'Reasoning',
                status: 'completed',
                preview: 'Checked the inputs.',
                kind: ChatTraceEventKind.reasoning,
              ),
            ],
            active: false,
            duration: Duration(seconds: 12),
          ),
        ),
      ),
    );

    expect(find.text('Thought for 12s'), findsOneWidget);
    expect(find.text('Checked the inputs.'), findsNothing);
  });

  testWidgets('el cargador por defecto respeta locale=en', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: Strings.localizationsDelegates,
        supportedLocales: Strings.supportedLocales,
        theme: AppTheme.hermesRedDark,
        home: const Scaffold(body: TuiLoader()),
      ),
    );

    expect(find.text('Loading…'), findsOneWidget);
    expect(find.text('cargando…'), findsNothing);
  });
}
