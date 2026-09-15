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
class GeneralModeDock extends StatelessWidget {
  final VoidCallback? onCreate;
  final VoidCallback? onOpenBots;
  final VoidCallback? onOpenSettings;

  /// Igual que en [BotModeDock]: true cuando hay una subpantalla abierta
  /// encima de este dock.
  final bool showBackContext;
  final VoidCallback? onBack;

  const GeneralModeDock({
    this.onCreate,
    this.onOpenBots,
    this.onOpenSettings,
    this.showBackContext = false,
    this.onBack,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    unawaited(DockPreferencesController.instance.ensureLoaded());
    return ListenableBuilder(
      listenable: DockPreferencesController.instance.listenable,
      builder: (context, _) =>
          _build(context, DockPreferencesController.instance.value.general),
    );
  }

  Widget _build(BuildContext context, DockProfileConfig profile) {
    final strings = Strings.of(context);
    final colors = Theme.of(context).hermes;
    final compact = MediaQuery.textScalerOf(context).scale(14) > 17;
    final visual = resolveDockVisual(colors, profile.style);
    final showBack =
        showBackContext && profile.showBackOnSubscreens && onBack != null;
    final slots = resolveDockSlots(
      visibleItems: profile.visibleItemIds,
      pinnedItemId: profile.pinnedItemId,
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
        onTap: onBack,
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
          // Este dock solo vive hoy en la pantalla de Inicio: mientras se
          // ve, "Inicio" es siempre la sección activa.
          selected: true,
          innerRadius: innerRadius,
          compact: compact,
        );
      case DockItemId.create:
        return DockItemTile(
          controlKey: const ValueKey('general-mode-dock-create'),
          icon: Icons.add_rounded,
          label: dockItemLabel(strings, DockItemId.create),
          accent: true,
          innerRadius: innerRadius,
          compact: compact,
          onTap: onCreate,
        );
      case DockItemId.bots:
        final meta = dockItemVisual(DockItemId.bots);
        return DockItemTile(
          controlKey: const ValueKey('general-mode-dock-bots'),
          icon: meta.icon,
          selectedIcon: meta.selectedIcon,
          label: dockItemLabel(strings, DockItemId.bots),
          innerRadius: innerRadius,
          compact: compact,
          onTap: onOpenBots,
        );
      case DockItemId.settings:
        final meta = dockItemVisual(DockItemId.settings);
        return DockItemTile(
          controlKey: const ValueKey('general-mode-dock-settings'),
          icon: meta.icon,
          selectedIcon: meta.selectedIcon,
          label: dockItemLabel(strings, DockItemId.settings),
          innerRadius: innerRadius,
          compact: compact,
          onTap: onOpenSettings,
        );
      case DockItemId.work:
        // Fuera de catálogo por defecto en "general" (oculto de fábrica);
        // si el usuario lo hace visible sin tener una acción que ofrecerle
        // en este perfil todavía, se omite en vez de romper el layout.
        return const SizedBox.shrink();
    }
  }
}
