import 'dart:async';

import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../models/dock_config.dart';
import '../services/dock_preferences_store.dart';
import '../theme/app_theme.dart';
import 'dock_style.dart';

/// Dock flotante del perfil "General": la parte de la app fuera de Bots
/// (por ahora, la pantalla de Inicio). Mismo motor visual que
/// [BotModeDock] (`DockBar`/`DockItemTile`, estilo y personalización por
/// perfil), pero sin el menú de creación de dos órbitas: "Crear" aquí es
/// una acción única (nueva conversación).
class GeneralModeDock extends StatefulWidget {
  final VoidCallback? onCreate;
  final VoidCallback? onOpenBots;
  final VoidCallback? onOpenSettings;

  /// Igual que en [BotModeDock]: true cuando hay una subpantalla abierta
  /// encima de este dock.
  final bool showBackContext;
  final VoidCallback? onBack;

  /// Navega al dashboard de Inicio. Null cuando este dock YA vive en Inicio
  /// (caso histórico/por defecto): entonces "Inicio" se muestra como sección
  /// activa sin acción propia. Al integrar este dock en otras pantallas
  /// (Ajustes, lista de sesiones, ...) se pasa una acción real de vuelta.
  final VoidCallback? onOpenHome;

  // Accesos directos opcionales del catálogo (ocultos por defecto): solo se
  // pintan con una acción real si el perfil los tiene visibles.
  final VoidCallback? onOpenCron;
  final VoidCallback? onOpenTasks;
  final VoidCallback? onOpenSessions;
  final VoidCallback? onOpenTools;

  /// Cuando no es null, el tile de "Crear" se envuelve en un [KeyedSubtree]
  /// con esta key: permite a quien construye este dock (ver
  /// [GeneralDockShell]) localizar el `RenderBox` del botón "+" para anclar
  /// ahí un popover contextual en vez de navegar (Cron, Tareas).
  final GlobalKey? createAnchorKey;

  /// Id del item que representa la pantalla donde vive este dock ahora
  /// mismo (Ajustes/Sesiones/Cron/Tareas/Herramientas): se pinta como
  /// sección activa (`selected: true`) en vez de sin marcar. Quien
  /// construye este dock ya se encarga de no pasarle una acción de
  /// navegación a ese mismo item (ver [GeneralDockShell]); esto solo añade
  /// la señal visual que le faltaba (ver B3).
  final DockItemId? currentDestination;

  const GeneralModeDock({
    this.onCreate,
    this.onOpenBots,
    this.onOpenSettings,
    this.showBackContext = false,
    this.onBack,
    this.onOpenHome,
    this.onOpenCron,
    this.onOpenTasks,
    this.onOpenSessions,
    this.onOpenTools,
    this.createAnchorKey,
    this.currentDestination,
    super.key,
  });

  @override
  State<GeneralModeDock> createState() => _GeneralModeDockState();
}

class _GeneralModeDockState extends State<GeneralModeDock> {
  @override
  void initState() {
    super.initState();
    // Carga en `initState`, no en `build()`: `BotModeDock` ya lo hace así
    // (`bot_mode_dock.dart`); hacerlo en `build()` repetía la llamada (sin
    // coste real por el guard de `ensureLoaded`, pero) en cada
    // reconstrucción del padre, y sobre todo dejaba un parpadeo
    // config-por-defecto → config-real en frío de 100-300ms en el primer
    // frame (bug confirmado: C7).
    unawaited(DockPreferencesController.instance.ensureLoaded());
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: DockPreferencesController.instance.listenable,
      builder: (context, _) {
        final prefs = DockPreferencesController.instance.value;
        // Interruptor global "Usar dock flotante" (Ajustes): con él
        // apagado este widget no pinta nada, sin dejar hueco reservado.
        // Guarda propia (además de la de `GeneralDockShell`) porque
        // `HomeDashboardScreen` monta este dock directamente, sin pasar
        // por el shell.
        if (!prefs.useDock) return const SizedBox.shrink();
        return _build(context, prefs.general);
      },
    );
  }

  Widget _build(BuildContext context, DockProfileConfig profile) {
    final strings = Strings.of(context);
    final colors = Theme.of(context).hermes;
    // Mismo criterio que en BotModeDock: el dock real siempre apila icono
    // arriba y etiqueta debajo (ver comentario equivalente en
    // bot_mode_dock.dart).
    const compact = true;
    final visual = resolveDockVisual(colors, profile.style);
    final showBack =
        widget.showBackContext &&
        profile.showBackOnSubscreens &&
        widget.onBack != null;
    // `work` vive oculto en el catálogo de "general" (sin acción propia en
    // este perfil: se pinta como `SizedBox.shrink()` más abajo) pero SÍ
    // contaba en `visibleItemIds` si el usuario lo activaba desde Ajustes,
    // estrechando el resto de items y alterando qué item se retira al
    // insertar "Atrás" sin que hubiera nada visible que lo justificara (bug
    // confirmado, MEDIDO: A5). Se excluye aquí, en el punto donde de verdad
    // importa (qué ocupa un hueco real en la barra), sin tocar el catálogo
    // genérico del modelo.
    final visibleItems = [
      for (final id in profile.visibleItemIds)
        if (id != DockItemId.work) id,
    ];
    final slots = resolveDockSlots(
      visibleItems: visibleItems,
      showBack: showBack,
    );
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    return Positioned(
      left: 16,
      right: 16,
      bottom: 12 + bottomInset + visual.lift,
      child: DockBar(
        key: const ValueKey('general-mode-floating-dock'),
        style: profile.style,
        children: [
          for (final slot in slots)
            _tileForSlot(
              slot,
              innerRadius: visual.innerRadius,
              compact: compact,
              strings: strings,
            ),
        ],
      ),
    );
  }

  Widget _tileForSlot(
    DockItemId? slot, {
    required double innerRadius,
    required bool compact,
    required Strings strings,
  }) {
    if (slot == null) {
      return DockItemTile(
        controlKey: const ValueKey('general-mode-dock-back'),
        icon: dockBackIcon,
        label: strings.dockBackLabel,
        innerRadius: innerRadius,
        compact: compact,
        onTap: widget.onBack,
      );
    }
    switch (slot) {
      case DockItemId.home:
        final meta = dockItemVisual(DockItemId.home);
        return DockItemTile(
          controlKey: const ValueKey('general-mode-dock-home'),
          icon: meta.icon,
          selectedIcon: meta.selectedIcon,
          label: dockItemLabel(strings, DockItemId.home),
          // Sin `onOpenHome` este dock vive en la propia pantalla de Inicio
          // (caso histórico): "Inicio" se pinta como sección activa sin
          // acción propia. Con `onOpenHome` (dock integrado en otra
          // pantalla) deja de estar "seleccionado" y navega de vuelta.
          selected: widget.onOpenHome == null,
          innerRadius: innerRadius,
          compact: compact,
          onTap: widget.onOpenHome,
        );
      case DockItemId.create:
        final tile = DockItemTile(
          controlKey: const ValueKey('general-mode-dock-create'),
          icon: Icons.add_rounded,
          label: dockItemLabel(strings, DockItemId.create),
          accent: true,
          innerRadius: innerRadius,
          compact: compact,
          onTap: widget.onCreate,
        );
        return widget.createAnchorKey == null
            ? tile
            : KeyedSubtree(key: widget.createAnchorKey, child: tile);
      case DockItemId.bots:
        final meta = dockItemVisual(DockItemId.bots);
        return DockItemTile(
          controlKey: const ValueKey('general-mode-dock-bots'),
          icon: meta.icon,
          selectedIcon: meta.selectedIcon,
          label: dockItemLabel(strings, DockItemId.bots),
          innerRadius: innerRadius,
          compact: compact,
          onTap: widget.onOpenBots,
        );
      case DockItemId.settings:
        final meta = dockItemVisual(DockItemId.settings);
        return DockItemTile(
          controlKey: const ValueKey('general-mode-dock-settings'),
          icon: meta.icon,
          selectedIcon: meta.selectedIcon,
          label: dockItemLabel(strings, DockItemId.settings),
          selected: widget.currentDestination == DockItemId.settings,
          innerRadius: innerRadius,
          compact: compact,
          onTap: widget.onOpenSettings,
        );
      case DockItemId.work:
        // Fuera de catálogo por defecto en "general" (oculto de fábrica);
        // si el usuario lo hace visible sin tener una acción que ofrecerle
        // en este perfil todavía, se omite en vez de romper el layout.
        return const SizedBox.shrink();
      case DockItemId.cron:
        final meta = dockItemVisual(DockItemId.cron);
        return DockItemTile(
          controlKey: const ValueKey('general-mode-dock-cron'),
          icon: meta.icon,
          selectedIcon: meta.selectedIcon,
          label: dockItemLabel(strings, DockItemId.cron),
          selected: widget.currentDestination == DockItemId.cron,
          innerRadius: innerRadius,
          compact: compact,
          onTap: widget.onOpenCron,
        );
      case DockItemId.tasks:
        final meta = dockItemVisual(DockItemId.tasks);
        return DockItemTile(
          controlKey: const ValueKey('general-mode-dock-tasks'),
          icon: meta.icon,
          selectedIcon: meta.selectedIcon,
          label: dockItemLabel(strings, DockItemId.tasks),
          selected: widget.currentDestination == DockItemId.tasks,
          innerRadius: innerRadius,
          compact: compact,
          onTap: widget.onOpenTasks,
        );
      case DockItemId.sessions:
        final meta = dockItemVisual(DockItemId.sessions);
        return DockItemTile(
          controlKey: const ValueKey('general-mode-dock-sessions'),
          icon: meta.icon,
          selectedIcon: meta.selectedIcon,
          label: dockItemLabel(strings, DockItemId.sessions),
          selected: widget.currentDestination == DockItemId.sessions,
          innerRadius: innerRadius,
          compact: compact,
          onTap: widget.onOpenSessions,
        );
      case DockItemId.tools:
        final meta = dockItemVisual(DockItemId.tools);
        return DockItemTile(
          controlKey: const ValueKey('general-mode-dock-tools'),
          icon: meta.icon,
          selectedIcon: meta.selectedIcon,
          label: dockItemLabel(strings, DockItemId.tools),
          selected: widget.currentDestination == DockItemId.tools,
          innerRadius: innerRadius,
          compact: compact,
          onTap: widget.onOpenTools,
        );
    }
  }
}
