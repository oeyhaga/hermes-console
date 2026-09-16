// Los tests existentes de `GeneralModeDock`/`BotModeDock` solo cubrían el
// catálogo por defecto de cada perfil (4-5 items). Este archivo recorre el
// catálogo COMPLETO (`DockItemId.values`) con todo visible, para cazar el
// tipo de bug que un catálogo pequeño no expone: un id sin acción real que
// aun así ocupa un hueco en la barra (A5 [media, MEDIDO] — `work` en
// "General" y `settings` en "Bots" contaban en `visibleItemIds` pese a
// pintarse como `SizedBox.shrink()`, estrechando el resto de items y
// alterando qué item se retira al insertar "Atrás").
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/models/dock_config.dart';
import 'package:hermes_android/core/services/dock_preferences_store.dart';
import 'package:hermes_android/core/theme/app_theme.dart';
import 'package:hermes_android/core/widgets/bot_mode_dock.dart';
import 'package:hermes_android/core/widgets/general_mode_dock.dart';
import 'package:hermes_android/l10n/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

Widget _wrap(Widget child) => MaterialApp(
  locale: const Locale('en'),
  localizationsDelegates: Strings.localizationsDelegates,
  supportedLocales: Strings.supportedLocales,
  theme: AppTheme.fromId('dark'),
  home: Scaffold(body: child),
);

/// `GeneralModeDock` se pinta con un `Positioned` propio (ver
/// `general_mode_dock.dart`), pensado para vivir dentro de un `Stack`
/// externo (así lo monta `GeneralDockShell`/`HomeDashboardScreen`) — a
/// diferencia de `BotModeDock`, que ya construye su propio `Stack` interno.
Widget _wrapInStack(Widget child) => _wrap(Stack(children: [child]));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final controller = DockPreferencesController.instance;

  setUp(() => SharedPreferences.setMockInitialValues({}));

  tearDown(() async {
    await controller.resetGeneral();
    await controller.resetBots();
  });

  testWidgets(
    'GeneralModeDock: every catalog item paints a real, tappable tile, '
    'except the documented no-op ("work"), which is fully excluded',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await controller.ensureLoaded();
      await controller.updateGeneral(
        (p) => p.copyWith(
          items: [for (final id in DockItemId.values) DockItemConfig(id: id)],
        ),
      );

      final taps = <DockItemId, int>{};
      void bump(DockItemId id) => taps[id] = (taps[id] ?? 0) + 1;

      await tester.pumpWidget(
        _wrapInStack(
          GeneralModeDock(
            onCreate: () => bump(DockItemId.create),
            onOpenBots: () => bump(DockItemId.bots),
            onOpenSettings: () => bump(DockItemId.settings),
            onOpenHome: () => bump(DockItemId.home),
            onOpenCron: () => bump(DockItemId.cron),
            onOpenTasks: () => bump(DockItemId.tasks),
            onOpenSessions: () => bump(DockItemId.sessions),
            onOpenTools: () => bump(DockItemId.tools),
          ),
        ),
      );
      await tester.pumpAndSettle();

      const actionable = [
        DockItemId.home,
        DockItemId.create,
        DockItemId.bots,
        DockItemId.settings,
        DockItemId.cron,
        DockItemId.tasks,
        DockItemId.sessions,
        DockItemId.tools,
      ];
      for (final id in actionable) {
        final finder = find.byKey(ValueKey('general-mode-dock-${id.name}'));
        expect(finder, findsOneWidget, reason: '$id should paint a real tile');
        await tester.tap(finder);
        await tester.pump();
        expect(
          taps[id],
          greaterThan(0),
          reason: '$id tile should trigger its real action on tap',
        );
      }

      // `work` no tiene acción propia en "General": no debe pintar NINGÚN
      // tile (ni siquiera uno inerte) que pudiera seguir contando para el
      // ancho de la barra.
      expect(
        find.byKey(const ValueKey('general-mode-dock-work')),
        findsNothing,
      );
    },
  );

  testWidgets(
    'BotModeDock: every catalog item paints a real, tappable tile, '
    'except the documented no-op ("settings"), which is fully excluded',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await controller.ensureLoaded();
      await controller.updateBots(
        (p) => p.copyWith(
          items: [for (final id in DockItemId.values) DockItemConfig(id: id)],
        ),
      );

      var destinationSelected = -1;
      final taps = <DockItemId, int>{};
      void bump(DockItemId id) => taps[id] = (taps[id] ?? 0) + 1;

      await tester.pumpWidget(
        _wrap(
          BotModeDock(
            // Ninguno de los dos destinos reales (0 = bots, 1 = work)
            // coincide con el seleccionado, así que tocar cualquiera de
            // los dos dispara `onDestinationSelected` de verdad.
            selectedIndex: -1,
            onDestinationSelected: (index) => destinationSelected = index,
            onOpenHome: () => bump(DockItemId.home),
            onOpenCron: () => bump(DockItemId.cron),
            onOpenTasks: () => bump(DockItemId.tasks),
            onOpenSessions: () => bump(DockItemId.sessions),
            onOpenTools: () => bump(DockItemId.tools),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // "bots"/"work" enrutan a través de `onDestinationSelected`, no de un
      // callback por id.
      await tester.tap(find.byKey(const ValueKey('bot-mode-dock-bots')));
      await tester.pump();
      expect(destinationSelected, 0);

      await tester.tap(find.byKey(const ValueKey('bot-mode-dock-work')));
      await tester.pump();
      expect(destinationSelected, 1);

      // "create" abre el menú de dos órbitas (estado interno del propio
      // dock, no un callback directo): basta con comprobar que el toque
      // realmente lo despliega.
      await tester.tap(find.byKey(const ValueKey('bot-mode-dock-create')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('bot-mode-create-actions')),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const ValueKey('bot-mode-create-outside')));
      await tester.pumpAndSettle();

      const directAction = [
        DockItemId.home,
        DockItemId.cron,
        DockItemId.tasks,
        DockItemId.sessions,
        DockItemId.tools,
      ];
      for (final id in directAction) {
        final finder = find.byKey(ValueKey('bot-mode-dock-${id.name}'));
        expect(finder, findsOneWidget, reason: '$id should paint a real tile');
        await tester.tap(finder);
        await tester.pump();
        expect(
          taps[id],
          greaterThan(0),
          reason: '$id tile should trigger its real action on tap',
        );
      }

      // `settings` no forma parte del catálogo de "Bots": mismo patrón
      // latente que `work` en "General" (ver A5). No debe pintar tile.
      expect(
        find.byKey(const ValueKey('bot-mode-dock-settings')),
        findsNothing,
      );
    },
  );
}
