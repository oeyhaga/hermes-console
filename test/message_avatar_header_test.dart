import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/companion/render/companion_status_indicator.dart';
import 'package:hermes_android/core/theme/app_theme.dart';
import 'package:hermes_android/core/widgets/hermes_spark_mascot.dart';
import 'package:hermes_android/core/widgets/message_avatar_header.dart';
import 'package:hermes_android/l10n/app_localizations.dart';

Widget _app(
  Widget child, {
  ThemeData? theme,
  double textScale = 1,
  bool reduceMotion = true,
}) => MaterialApp(
  locale: const Locale('es'),
  localizationsDelegates: const [
    Strings.delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
  ],
  supportedLocales: Strings.supportedLocales,
  theme: theme ?? AppTheme.hermesRedDark,
  builder: (context, home) => MediaQuery(
    data: MediaQuery.of(context).copyWith(
      disableAnimations: reduceMotion,
      textScaler: TextScaler.linear(textScale),
    ),
    child: home!,
  ),
  home: Scaffold(
    body: Padding(padding: const EdgeInsets.all(12), child: child),
  ),
);

Widget _header({
  AvatarRingState state = AvatarRingState.live,
  bool mascot = true,
  String? model = 'gpt-5.5',
  String? time = '12:04',
  List<Widget> actions = const [],
}) => MessageAvatarHeader(
  name: 'hermes',
  state: state,
  model: model,
  time: time,
  mascot: mascot
      ? const CompanionStatusIndicator(
          key: ValueKey('assistant-header-companion'),
          companion: null,
          mood: HermesSparkMood.thinking,
          size: kAvatarMascotSize,
          animate: false,
        )
      : null,
  actions: actions,
);

Color _ringColor(WidgetTester tester) {
  final box = tester.widget<DecoratedBox>(
    find.byKey(const ValueKey('assistant-avatar-ring')),
  );
  final border = (box.decoration as BoxDecoration).border! as Border;
  return border.top.color;
}

void main() {
  testWidgets('la mascota va dentro del chip con anillo en cada estado', (
    tester,
  ) async {
    final theme = AppTheme.hermesRedDark;
    final colors = theme.hermes;
    for (final entry in {
      AvatarRingState.live: colors.accent,
      AvatarRingState.success: colors.success,
      AvatarRingState.warning: colors.warning,
      AvatarRingState.error: colors.error,
      AvatarRingState.neutral: colors.textDisabled,
    }.entries) {
      await tester.pumpWidget(_app(_header(state: entry.key), theme: theme));
      await tester.pump();
      expect(
        find.byKey(const ValueKey('assistant-header-companion')),
        findsOneWidget,
        reason: '${entry.key}',
      );
      // La mascota queda dentro del chip circular.
      final chip = tester.getRect(
        find.byKey(const ValueKey('assistant-avatar-chip')),
      );
      final mascot = tester.getRect(
        find.byKey(const ValueKey('assistant-header-companion')),
      );
      expect(chip.contains(mascot.topLeft), isTrue);
      expect(chip.contains(mascot.bottomRight), isTrue);
      expect(chip.size, const Size(kAvatarChipSize, kAvatarChipSize));
      expect(mascot.size, const Size(kAvatarMascotSize, kAvatarMascotSize));
      final ring = _ringColor(tester);
      // Vivo: raíl suave + arco; el resto: anillo casi opaco del color de estado.
      expect(
        ring.toARGB32() & 0x00FFFFFF,
        entry.value.toARGB32() & 0x00FFFFFF,
        reason: '${entry.key}',
      );
    }
  });

  testWidgets('el arco vivo solo existe mientras el turno vive', (
    tester,
  ) async {
    await tester.pumpWidget(_app(_header(), reduceMotion: false));
    await tester.pump();
    expect(
      find.byKey(const ValueKey('assistant-avatar-live-arc')),
      findsOneWidget,
    );
    await tester.pumpWidget(
      _app(_header(state: AvatarRingState.success), reduceMotion: false),
    );
    await tester.pump();
    expect(
      find.byKey(const ValueKey('assistant-avatar-live-arc')),
      findsNothing,
    );
    // Movimiento reducido: sin arco animado.
    await tester.pumpWidget(_app(_header()));
    await tester.pump();
    expect(
      find.byKey(const ValueKey('assistant-avatar-live-arc')),
      findsNothing,
    );
  });

  testWidgets('sin presencia: avatar neutro con el mismo anillo y la misma '
      'geometría', (tester) async {
    await tester.pumpWidget(_app(_header()));
    await tester.pump();
    final withMascot = tester.getRect(find.byType(MessageAvatarHeader));
    final chipWith = tester.getRect(
      find.byKey(const ValueKey('assistant-avatar-chip')),
    );
    final nameWith = tester.getTopLeft(
      find.byKey(const ValueKey('assistant-header-name')),
    );

    await tester.pumpWidget(_app(_header(mascot: false)));
    await tester.pump();
    expect(
      find.byKey(const ValueKey('assistant-header-companion')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('assistant-avatar-initial')),
      findsOneWidget,
    );
    expect(find.text('H'), findsOneWidget);
    expect(tester.getRect(find.byType(MessageAvatarHeader)), withMascot);
    expect(
      tester.getRect(find.byKey(const ValueKey('assistant-avatar-chip'))),
      chipWith,
    );
    expect(
      tester.getTopLeft(find.byKey(const ValueKey('assistant-header-name'))),
      nameWith,
    );
    expect(find.byKey(const ValueKey('assistant-avatar-ring')), findsOneWidget);
  });

  testWidgets('nombre y «modelo · hora»; sin modelo solo la hora', (
    tester,
  ) async {
    await tester.pumpWidget(_app(_header()));
    await tester.pump();
    expect(
      tester
          .widget<Text>(find.byKey(const ValueKey('assistant-header-name')))
          .data,
      'Hermes',
    );
    expect(
      tester
          .widget<Text>(find.byKey(const ValueKey('assistant-header-subtitle')))
          .data,
      'gpt-5.5 · 12:04',
    );
    await tester.pumpWidget(_app(_header(model: null)));
    await tester.pump();
    expect(
      tester
          .widget<Text>(find.byKey(const ValueKey('assistant-header-subtitle')))
          .data,
      '12:04',
    );
    await tester.pumpWidget(_app(_header(model: null, time: null)));
    await tester.pump();
    expect(
      find.byKey(const ValueKey('assistant-header-subtitle')),
      findsNothing,
    );
    // Ya no hay el «>_ HERMES» monoespaciado.
    expect(find.textContaining('>_'), findsNothing);
    expect(displayAgentName('Hermes Console'), 'Hermes Console');
    expect(displayAgentName('HERMES CONSOLE'), 'Hermes Console');
    expect(displayAgentName('MyBot'), 'MyBot');
    expect(displayAgentName('hermes'), 'Hermes');
    expect(displayAgentName('  '), 'Hermes');
  });

  testWidgets('las acciones quedan a la derecha', (tester) async {
    await tester.pumpWidget(
      _app(
        _header(
          state: AvatarRingState.success,
          actions: const [
            SizedBox(key: ValueKey('act-copy'), width: 48, height: 48),
          ],
        ),
      ),
    );
    await tester.pump();
    final name = tester.getRect(
      find.byKey(const ValueKey('assistant-header-name')),
    );
    final action = tester.getRect(find.byKey(const ValueKey('act-copy')));
    expect(action.left, greaterThan(name.right));
    expect(
      action.right,
      closeTo(tester.getRect(find.byType(MessageAvatarHeader)).right, 0.5),
    );
  });

  testWidgets('320 dp con escala 2 sin desbordes y en los 26 temas', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    for (final preset in AppTheme.presets) {
      await tester.pumpWidget(
        _app(
          _header(
            model: 'un-modelo-con-un-id-larguisimo-que-no-cabe',
            actions: const [SizedBox(width: 48, height: 48)],
          ),
          theme: AppTheme.fromId(preset.id),
          textScale: 2,
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull, reason: preset.id);
    }
  });
}
