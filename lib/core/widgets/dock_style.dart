import 'dart:ui';

import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../models/dock_config.dart';
import '../theme/app_theme.dart';

/// Metadatos visuales de un elemento de catálogo, compartidos por el dock de
/// Bots, el de General y la lista de la pantalla de personalización, para
/// que los tres pinten siempre el mismo icono/etiqueta para un mismo id.
class DockItemVisual {
  final IconData icon;
  final IconData? selectedIcon;

  const DockItemVisual({required this.icon, this.selectedIcon});
}

const Map<DockItemId, DockItemVisual> _dockItemVisuals = {
  DockItemId.bots: DockItemVisual(
    icon: Icons.smart_toy_outlined,
    selectedIcon: Icons.smart_toy_rounded,
  ),
  DockItemId.work: DockItemVisual(
    icon: Icons.work_outline_rounded,
    selectedIcon: Icons.work_rounded,
  ),
  DockItemId.create: DockItemVisual(icon: Icons.add_rounded),
  DockItemId.home: DockItemVisual(
    icon: Icons.home_outlined,
    selectedIcon: Icons.home_rounded,
  ),
  DockItemId.settings: DockItemVisual(
    icon: Icons.settings_outlined,
    selectedIcon: Icons.settings_rounded,
  ),
};

DockItemVisual dockItemVisual(DockItemId id) =>
    _dockItemVisuals[id] ?? const DockItemVisual(icon: Icons.circle_outlined);

/// Icono del elemento contextual "Atrás": no vive en el catálogo (ver
/// [DockItemId]), así que no tiene entrada en [dockItemVisual].
const IconData dockBackIcon = Icons.arrow_back_rounded;

String dockItemLabel(Strings strings, DockItemId id) => switch (id) {
  DockItemId.bots => strings.missionBotsLabel,
  DockItemId.work => strings.missionWorkLabel,
  DockItemId.create => strings.missionCreateLabel,
  DockItemId.home => strings.dockHomeLabel,
  DockItemId.settings => strings.dockSettingsLabel,
};

/// Valores resueltos de un [DockStyle] listos para pintar: colores,
/// radios, sombras y desenfoque. Centraliza la traducción "ajuste →
/// píxeles" para que el dock de Bots y el de General (y la vista previa de
/// Ajustes › Dock) pinten exactamente lo mismo a partir del mismo estilo.
class DockVisual {
  final Color background;
  final Color border;
  final double outerRadius;
  final double innerRadius;
  final List<BoxShadow> shadows;
  final double blurSigma;

  /// Separación extra respecto al borde inferior que añade la profundidad
  /// "Flotante" (el dock se despega un poco más del filo de la pantalla).
  final double lift;

  const DockVisual({
    required this.background,
    required this.border,
    required this.outerRadius,
    required this.innerRadius,
    required this.shadows,
    required this.blurSigma,
    required this.lift,
  });
}

DockVisual resolveDockVisual(HermesThemeColors colors, DockStyle style) {
  final transparency = style.transparency.clamp(0.0, 1.0);
  final bgAlpha = (1 - transparency).clamp(0.0, 1.0);
  final borderAlpha = (1 - transparency / 3).clamp(0.0, 1.0);

  var background = colors.surface;
  var border = colors.divider;
  List<BoxShadow> shadows;
  var lift = 0.0;

  switch (style.depth) {
    case DockDepth.flat:
      shadows = const [];
    case DockDepth.elevated:
      shadows = [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.28),
          blurRadius: 18,
          offset: const Offset(0, 6),
        ),
      ];
    case DockDepth.floating:
      // Superficie/borde ligeramente más claros: en tema oscuro la sombra
      // por sí sola apenas se distingue, así que la profundidad "Flotante"
      // también se lee por contraste de superficie, no solo por sombra.
      background = Color.lerp(colors.surface, Colors.white, 0.03)!;
      border = Color.lerp(colors.divider, Colors.white, 0.06)!;
      lift = 6;
      shadows = [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.7),
          blurRadius: 40,
          offset: const Offset(0, 16),
        ),
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.45),
          blurRadius: 6,
          offset: const Offset(0, 2),
        ),
      ];
  }

  return DockVisual(
    background: background.withValues(alpha: background.a * bgAlpha),
    border: border.withValues(alpha: border.a * borderAlpha),
    outerRadius: style.borderShape.outerRadius,
    innerRadius: style.borderShape.innerRadius,
    shadows: shadows,
    blurSigma: transparency > 0 ? 14 : 0,
    lift: lift,
  );
}

/// Contenedor plano de la barra del dock: aplica [DockVisual] (color, borde,
/// radio, sombra y, si hay transparencia, desenfoque de fondo) a [children]
/// dispuestos en una fila a ras de borde a borde.
class DockBar extends StatelessWidget {
  final DockStyle style;
  final List<Widget> children;

  const DockBar({required this.style, required this.children, super.key});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).hermes;
    final visual = resolveDockVisual(colors, style);
    final radius = BorderRadius.circular(visual.outerRadius);
    Widget bar = DecoratedBox(
      decoration: BoxDecoration(
        color: visual.background,
        border: Border.all(color: visual.border),
        borderRadius: radius,
        boxShadow: visual.shadows,
      ),
      child: SizedBox(
        height: 48,
        child: Padding(
          // Solo inset horizontal: el vertical se deja a 0 para que cada
          // elemento pueda ocupar los 48dp de alto completos (objetivo
          // táctil mínimo de accesibilidad) en vez de encogerse a ~40dp.
          // `stretch` fuerza esa altura completa en cada item de la fila.
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: children,
          ),
        ),
      ),
    );
    if (visual.blurSigma > 0) {
      bar = ClipRRect(
        borderRadius: radius,
        child: BackdropFilter(
          filter: ImageFilter.blur(
            sigmaX: visual.blurSigma,
            sigmaY: visual.blurSigma,
          ),
          child: bar,
        ),
      );
    }
    return bar;
  }
}

/// Un elemento dentro de la barra: icono + etiqueta, a peso igual con el
/// resto (sin FAB elevado ni tamaños especiales). El elemento de acento
/// (el "+") se distingue solo por color, nunca por tamaño o elevación.
class DockItemTile extends StatelessWidget {
  final Key? controlKey;
  final Key? semanticsKey;
  final IconData icon;
  final IconData? selectedIcon;
  final String label;
  final bool selected;
  final bool accent;
  final double innerRadius;
  final bool compact;
  final bool? toggled;
  final VoidCallback? onTap;
  final FocusNode? focusNode;

  const DockItemTile({
    required this.icon,
    required this.label,
    required this.innerRadius,
    this.controlKey,
    this.semanticsKey,
    this.selectedIcon,
    this.selected = false,
    this.accent = false,
    this.compact = false,
    this.toggled,
    this.onTap,
    this.focusNode,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).hermes;
    final color = accent
        ? colors.accentText
        : selected
        ? colors.textPrimary
        : colors.textSecondary;
    final displayIcon = selected && selectedIcon != null ? selectedIcon! : icon;
    return Expanded(
      child: Semantics(
        key: semanticsKey,
        button: true,
        selected: selected,
        toggled: toggled,
        label: label,
        onTap: onTap,
        excludeSemantics: true,
        child: Tooltip(
          message: label,
          child: InkWell(
            key: controlKey,
            focusNode: focusNode,
            onTap: onTap,
            borderRadius: BorderRadius.circular(innerRadius),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: selected && !accent ? colors.surfaceVariant : null,
                borderRadius: BorderRadius.circular(innerRadius),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(displayIcon, size: 21, color: color),
                  if (!compact) ...[
                    const SizedBox(width: 7),
                    Flexible(
                      child: Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: color,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
