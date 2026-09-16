import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Abre una superficie modal anclada a la posición actual de [anchorKey], en
/// vez de centrada como [showHermesFloatingSurface] (`hermes_premium_ui.dart`).
///
/// Pensado para el "+" contextual del dock flotante en Cron y Tareas: en vez
/// de navegar a una pantalla aparte, la superficie de creación rápida debe
/// sentir que "sale" del propio botón. [builder] recibe el `BuildContext` de
/// la ruta y debe aportar su propia decoración (Material/Dialog con su
/// sombra y forma) — este helper solo resuelve el posicionamiento, no
/// decora, para poder alojar tanto un `Dialog` ya existente (que trae su
/// propio Material) como un formulario a medida sin duplicar chrome.
///
/// Si el `RenderBox` de [anchorKey] no está disponible (p. ej. el dock quedó
/// oculto entre frames), cae a una posición por defecto cerca de donde vive
/// el dock en vez de fallar.
Future<T?> showDockAnchoredPopover<T>({
  required BuildContext context,
  required GlobalKey anchorKey,
  required WidgetBuilder builder,
  double maxWidth = 360,
  bool barrierDismissible = true,
}) {
  final renderObject = anchorKey.currentContext?.findRenderObject();
  final anchorBox = renderObject is RenderBox && renderObject.attached
      ? renderObject
      : null;
  final reduceMotion = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
  return Navigator.of(context).push<T>(
    PageRouteBuilder<T>(
      opaque: false,
      barrierDismissible: barrierDismissible,
      barrierColor: Colors.black.withValues(alpha: 0.4),
      barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
      transitionDuration: reduceMotion
          ? Duration.zero
          : const Duration(milliseconds: 200),
      reverseTransitionDuration: reduceMotion
          ? Duration.zero
          : const Duration(milliseconds: 150),
      pageBuilder: (routeContext, animation, secondaryAnimation) =>
          _DockAnchoredPopoverFrame(
            anchor: anchorBox,
            maxWidth: maxWidth,
            child: Builder(builder: builder),
          ),
      transitionsBuilder: (routeContext, animation, secondaryAnimation, child) {
        if (reduceMotion) return child;
        final curved = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
          reverseCurve: Curves.easeInCubic,
        );
        return FadeTransition(
          opacity: curved,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.85, end: 1).animate(curved),
            alignment: Alignment.bottomCenter,
            child: child,
          ),
        );
      },
    ),
  );
}

class _DockAnchoredPopoverFrame extends StatelessWidget {
  const _DockAnchoredPopoverFrame({
    required this.anchor,
    required this.maxWidth,
    required this.child,
  });

  final RenderBox? anchor;
  final double maxWidth;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final screen = media.size;
    // Sin RenderBox (caso borde): asume el "+" cerca del centro inferior,
    // que es donde vive el dock en las tres pantallas que lo usan.
    final anchorTopLeft =
        anchor?.localToGlobal(Offset.zero) ??
        Offset(screen.width / 2 - 24, screen.height - 96);
    final anchorSize = anchor?.size ?? const Size(48, 48);

    final width = maxWidth > screen.width - 24 ? screen.width - 24 : maxWidth;
    var left = anchorTopLeft.dx + anchorSize.width / 2 - width / 2;
    left = left.clamp(12.0, screen.width - width - 12.0);

    // Todo el cálculo vive en coordenadas GLOBALES de pantalla completa —
    // el mismo espacio en el que `localToGlobal` ya nos dio `anchorTopLeft`
    // — y este widget ya NO se envuelve en un `SafeArea`: mezclar ambos
    // espacios (coordenadas globales para el ancla, locales-tras-SafeArea
    // para el `Positioned`) desalineaba el popover del botón exactamente
    // por el inset inferior del sistema (medido: 44dp de separación en vez
    // de los 10dp buscados — bug A6). El inset inferior/superior del
    // sistema se aplica ahora a mano, una sola vez, vía `media.padding`.
    final desiredGap = screen.height - anchorTopLeft.dy + 10;
    // Suelo del popover: nunca por debajo del borde del sistema (gesto/nav
    // bar) NI por debajo del teclado cuando está visible — antes este
    // cálculo ignoraba `viewInsets.bottom` por completo y el popover
    // quedaba casi entero tapado al abrir un `TextField(autofocus: true)`
    // dentro (medido: 216 de 220px tapados — bug A1).
    final minBottom = math.max(
      media.padding.bottom + 12,
      media.viewInsets.bottom + 8,
    );
    // `math.max` evita que el clamp reciba un límite superior menor que el
    // inferior (pantalla pequeña + teclado alto): en ese caso el popover
    // simplemente se pega al suelo ya calculado en vez de fallar.
    final maxBottom = math.max(minBottom, screen.height - 96);
    final bottom = desiredGap.clamp(minBottom, maxBottom);
    final availableHeight = screen.height - bottom - media.padding.top - 24;

    return Stack(
      children: [
        Positioned(
          left: left,
          bottom: bottom,
          width: width,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: availableHeight <= 0 ? 0 : availableHeight,
            ),
            child: child,
          ),
        ),
      ],
    );
  }
}
