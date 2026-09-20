import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:hermes_android/core/theme/app_theme.dart';
import 'package:hermes_android/core/widgets/hermes_floating_notice.dart';

Widget _host(Widget child, {bool reduceMotion = false}) => MaterialApp(
  theme: AppTheme.fromId('dark'),
  home: MediaQuery(
    data: MediaQueryData(disableAnimations: reduceMotion),
    child: Scaffold(
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: child,
        ),
      ),
    ),
  ),
);

void main() {
  testWidgets('floating notice opens its destination from the whole card', (
    tester,
  ) async {
    var opened = 0;
    await tester.pumpWidget(
      _host(
        HermesFloatingNotice(
          noticeKey: const ValueKey('reply-ready'),
          icon: Icons.check_circle_outline,
          tint: Colors.green,
          title: 'Respuesta lista',
          body: 'Hermes termino el trabajo.',
          actionLabel: 'Ir',
          dismissLabel: 'Descartar',
          onOpen: () => opened++,
          onDismissed: () {},
        ),
        reduceMotion: true,
      ),
    );

    expect(find.text('Respuesta lista'), findsOneWidget);
    expect(find.text('Hermes termino el trabajo.'), findsOneWidget);
    expect(find.text('Ir'), findsOneWidget);
    expect(find.byTooltip('Descartar'), findsOneWidget);

    await tester.tap(
      find
          .ancestor(
            of: find.text('Respuesta lista'),
            matching: find.byType(InkWell),
          )
          .first,
    );
    await tester.pump();
    expect(opened, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('horizontal swipe only dismisses the floating notice', (
    tester,
  ) async {
    var visible = true;
    var dismissed = 0;
    var opened = 0;

    await tester.pumpWidget(
      _host(
        StatefulBuilder(
          builder: (context, setState) => visible
              ? HermesFloatingNotice(
                  noticeKey: const ValueKey('approval-pending'),
                  icon: Icons.verified_user_outlined,
                  tint: Colors.orange,
                  title: 'Necesita tu permiso',
                  actionLabel: 'Ir',
                  dismissLabel: 'Descartar',
                  onOpen: () => opened++,
                  onDismissed: () {
                    dismissed++;
                    setState(() => visible = false);
                  },
                )
              : const SizedBox.shrink(),
        ),
        reduceMotion: true,
      ),
    );

    await tester.drag(
      find.byKey(const ValueKey('approval-pending')),
      const Offset(-600, 0),
    );
    await tester.pumpAndSettle();

    expect(dismissed, 1);
    expect(opened, 0);
    expect(find.text('Necesita tu permiso'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('dismiss is isolated from the open action', (tester) async {
    var opened = 0;
    var dismissed = 0;
    await tester.pumpWidget(
      _host(
        HermesFloatingNotice(
          noticeKey: const ValueKey('isolated-actions'),
          icon: Icons.task_alt,
          tint: Colors.blue,
          title: 'Tarea terminada',
          body: 'El resultado ya esta disponible.',
          actionLabel: 'Ir',
          dismissLabel: 'Descartar',
          onOpen: () => opened++,
          onDismissed: () => dismissed++,
        ),
        reduceMotion: true,
      ),
    );

    final actionRect = tester.getRect(
      find.byKey(const ValueKey('floating-notice-action')),
    );
    final dismissRect = tester.getRect(
      find.byKey(const ValueKey('floating-notice-dismiss')),
    );
    expect(dismissRect.width, greaterThanOrEqualTo(48));
    expect(dismissRect.height, greaterThanOrEqualTo(48));
    expect(actionRect.right, lessThan(dismissRect.left));

    await tester.tap(find.byKey(const ValueKey('floating-notice-dismiss')));
    await tester.pump();
    expect(dismissed, 1);
    expect(opened, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('notice paints only theme tokens: no accent bar or tinted fill', (
    tester,
  ) async {
    const tint = Color(0xFF12AB34);
    await tester.pumpWidget(
      _host(
        HermesFloatingNotice(
          noticeKey: const ValueKey('neutral-style'),
          icon: Icons.check_circle_outline,
          tint: tint,
          title: 'Respuesta lista',
          body: 'Toca para abrir.',
          actionLabel: 'Ir',
          dismissLabel: 'Descartar',
          onOpen: () {},
          onDismissed: () {},
        ),
        reduceMotion: true,
      ),
    );
    final notice = find.byKey(const ValueKey('neutral-style'));
    final colors = Theme.of(tester.element(notice)).hermes;

    // Superficie neutra del tema con filete del token `divider`.
    final material = tester.widget<Material>(
      find.descendant(of: notice, matching: find.byType(Material)).first,
    );
    expect(material.color, colors.surface);
    final borders = find
        .descendant(of: notice, matching: find.byType(DecoratedBox))
        .evaluate()
        .map((e) => (e.widget as DecoratedBox).decoration)
        .whereType<BoxDecoration>();
    final hairline = Border.all(color: colors.divider.withValues(alpha: 0.78));
    expect(borders.any((d) => d.border == hairline), isTrue);

    // Sin barra lateral: ningun bloque de color pintado dentro del aviso, y
    // ningun relleno o fondo con el color de estado.
    expect(
      find.descendant(of: notice, matching: find.byType(ColoredBox)),
      findsNothing,
    );
    for (final decorated
        in find
            .descendant(of: notice, matching: find.byType(DecoratedBox))
            .evaluate()
            .map((e) => e.widget as DecoratedBox)) {
      final decoration = decorated.decoration;
      if (decoration is BoxDecoration && decoration.color != null) {
        expect(decoration.color!.withValues(alpha: 1), isNot(tint));
      }
    }

    // El estado lo lleva solo el glifo; texto y accion salen del tema.
    final glyph = tester.widget<Icon>(
      find.byKey(const ValueKey('floating-notice-icon')),
    );
    expect(glyph.color, tint);
    final action = tester.widget<Text>(find.text('Ir'));
    expect(action.style?.color, colors.textPrimary);
    final arrow = tester.widget<Icon>(find.byIcon(Icons.arrow_forward_rounded));
    expect(arrow.color, colors.textPrimary);
    final title = tester.widget<Text>(find.text('Respuesta lista'));
    expect(title.style?.color, colors.textPrimary);
    final body = tester.widget<Text>(find.text('Toca para abrir.'));
    expect(body.style?.color, colors.textSecondary);
    final close = tester.widget<Icon>(find.byIcon(Icons.close_rounded));
    expect(close.color, colors.textSecondary);
    expect(tester.takeException(), isNull);
  });

  testWidgets('notice keeps a compact footprint and no divider column', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        HermesFloatingNotice(
          noticeKey: const ValueKey('compact'),
          icon: Icons.task_alt,
          tint: Colors.blue,
          title: 'Run terminado',
          body: 'El resultado ya esta disponible.',
          actionLabel: 'Ir',
          dismissLabel: 'Descartar',
          onOpen: () {},
          onDismissed: () {},
        ),
        reduceMotion: true,
      ),
    );
    final size = tester.getSize(find.byKey(const ValueKey('compact')));
    expect(size.height, lessThanOrEqualTo(96));
    // El descarte comparte fila con el texto: no hay columna propia de 52 dp.
    final dismiss = tester.getRect(
      find.byKey(const ValueKey('floating-notice-dismiss')),
    );
    final card = tester.getRect(find.byKey(const ValueKey('compact')));
    expect(dismiss.right, lessThanOrEqualTo(card.right));
    expect(dismiss.width, 48);
  });
}
