import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Aviso breve que flota sobre la pantalla actual sin bloquearla.
///
/// Se usa para eventos que llegan desde otra parte de la app (respuesta lista,
/// run terminado o aprobacion pendiente). El gesto horizontal solo descarta el
/// aviso visible; nunca resuelve ni modifica la accion remota que lo origino.
///
/// Estilo: superficie neutra del tema con filete y sombra suave. [tint] solo
/// colorea el glifo de estado; no hay barra lateral ni relleno de color.
class HermesFloatingNotice extends StatelessWidget {
  const HermesFloatingNotice({
    required this.noticeKey,
    required this.icon,
    required this.tint,
    required this.title,
    required this.actionLabel,
    required this.dismissLabel,
    required this.onOpen,
    required this.onDismissed,
    this.body = '',
    super.key,
  });

  final Key noticeKey;
  final IconData icon;
  final Color tint;
  final String title;
  final String body;
  final String actionLabel;
  final String dismissLabel;
  final VoidCallback onOpen;
  final VoidCallback onDismissed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.hermes;
    final profile = theme.hermesComponents.profile;
    final reduceMotion = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    final radius = profile.shape.cardRadius.clamp(16.0, 22.0);

    final notice = Dismissible(
      key: noticeKey,
      // Solo hacia el borde final: no compite con el gesto Android de volver
      // que nace en el borde inicial de la pantalla.
      direction: DismissDirection.endToStart,
      resizeDuration: reduceMotion
          ? Duration.zero
          : const Duration(milliseconds: 140),
      movementDuration: reduceMotion
          ? Duration.zero
          : const Duration(milliseconds: 180),
      confirmDismiss: (_) async {
        // El propietario retira el OverlayEntry de inmediato. Devolver false
        // evita que Dismissible intente reconstruirse ya marcado como borrado
        // durante el mismo frame en que desaparece el overlay.
        onDismissed();
        return false;
      },
      child: Semantics(
        container: true,
        button: true,
        label: body.trim().isEmpty ? title : '$title. $body',
        hint: actionLabel,
        child: Material(
          // Misma familia que las pastillas de actividad del chat: superficie
          // neutra, sombra suave y un filete del token `divider`. El estado
          // lo lleva solo el glifo; sin barra lateral ni relleno de color.
          color: colors.surface,
          surfaceTintColor: Colors.transparent,
          elevation: 10,
          shadowColor: Colors.black.withValues(alpha: 0.45),
          borderRadius: BorderRadius.circular(radius),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onOpen,
            child: DecoratedBox(
              decoration: BoxDecoration(
                border: Border.all(
                  color: colors.divider.withValues(alpha: 0.78),
                ),
                borderRadius: BorderRadius.circular(radius),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Glifo desnudo, como el icono de estado del toast de
                  // Desktop: el único color del aviso es el de este glifo.
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 13, 0, 0),
                    child: Icon(
                      icon,
                      key: const ValueKey('floating-notice-icon'),
                      color: tint,
                      size: 20,
                    ),
                  ),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(12, 11, 4, 12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.titleSmall?.copyWith(
                              color: colors.textPrimary,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 0,
                            ),
                          ),
                          if (body.trim().isNotEmpty) ...[
                            const SizedBox(height: 2),
                            Text(
                              body,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: colors.textSecondary,
                                height: 1.3,
                              ),
                            ),
                          ],
                          const SizedBox(height: 6),
                          Row(
                            key: const ValueKey('floating-notice-action'),
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                actionLabel,
                                style: theme.textTheme.labelMedium?.copyWith(
                                  color: colors.textPrimary,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(width: 2),
                              Icon(
                                Icons.arrow_forward_rounded,
                                color: colors.textPrimary,
                                size: 16,
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                  IconButton(
                    key: const ValueKey('floating-notice-dismiss'),
                    onPressed: onDismissed,
                    tooltip: dismissLabel,
                    constraints: const BoxConstraints.tightFor(
                      width: 48,
                      height: 48,
                    ),
                    icon: Icon(
                      Icons.close_rounded,
                      color: colors.textSecondary,
                      size: 18,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    if (reduceMotion) return notice;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      child: notice,
      builder: (context, value, child) => Opacity(
        opacity: value,
        child: Transform.translate(
          offset: Offset(0, -12 * (1 - value)),
          child: child,
        ),
      ),
    );
  }
}
