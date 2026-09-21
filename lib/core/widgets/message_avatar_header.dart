import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Estado que pinta el anillo fino del avatar.
enum AvatarRingState { live, success, warning, error, neutral }

/// Tamaño total del chip (anillo + disco + mascota de 44 dp).
const double kAvatarChipSize = 52;

/// Tamaño de la mascota dentro del chip: el mismo de la cabecera anterior.
const double kAvatarMascotSize = 44;

Color avatarRingColor(HermesThemeColors colors, AvatarRingState state) =>
    switch (state) {
      AvatarRingState.live => colors.accent,
      AvatarRingState.success => colors.success,
      AvatarRingState.warning => colors.warning,
      AvatarRingState.error => colors.error,
      AvatarRingState.neutral => colors.textDisabled,
    };

/// Avatar con identidad: la mascota (o, sin presencia, un monograma) sobre un
/// disco suave con un anillo fino de estado. El anillo es la única señal de
/// estado del avatar: acento y girando mientras el turno vive; éxito / aviso /
/// error / neutro al terminar.
class AvatarChip extends StatelessWidget {
  const AvatarChip({
    required this.name,
    required this.state,
    this.mascot,
    super.key,
  });

  final String name;
  final AvatarRingState state;

  /// La mascota ya construida (44 dp), o `null` con la presencia apagada: en
  /// ese caso se pinta un avatar neutro con la inicial del nombre.
  final Widget? mascot;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).hermes;
    final ring = avatarRingColor(colors, state);
    final reduceMotion = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    final initial = name.trim().isEmpty
        ? 'H'
        : name.trim().substring(0, 1).toUpperCase();
    return SizedBox(
      key: const ValueKey('assistant-avatar-chip'),
      width: kAvatarChipSize,
      height: kAvatarChipSize,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Disco suave.
          DecoratedBox(
            key: const ValueKey('assistant-avatar-ring'),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: colors.surfaceVariant.withValues(alpha: 0.55),
              border: Border.all(
                color: ring.withValues(
                  alpha: state == AvatarRingState.live ? 0.28 : 0.85,
                ),
                width: 1.6,
              ),
            ),
            child: const SizedBox.expand(),
          ),
          // Arco que gira solo mientras el turno vive.
          if (state == AvatarRingState.live && !reduceMotion)
            SizedBox(
              width: kAvatarChipSize,
              height: kAvatarChipSize,
              child: CircularProgressIndicator(
                key: const ValueKey('assistant-avatar-live-arc'),
                strokeWidth: 1.8,
                color: ring,
              ),
            )
          else if (state == AvatarRingState.live)
            DecoratedBox(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: ring, width: 1.8),
              ),
              child: const SizedBox.expand(),
            ),
          if (mascot != null)
            SizedBox(
              width: kAvatarMascotSize,
              height: kAvatarMascotSize,
              child: mascot,
            )
          else
            Text(
              initial,
              key: const ValueKey('assistant-avatar-initial'),
              style: TextStyle(
                fontSize: 19,
                fontWeight: FontWeight.w700,
                color: colors.accentText,
              ),
            ),
        ],
      ),
    );
  }
}

/// Un nombre todo en mayúsculas o todo en minúsculas («HERMES CONSOLE»,
/// «hermes») se muestra en «Hermes Console»; uno con mayúsculas mezcladas se
/// respeta tal cual.
String displayAgentName(String raw) {
  final name = raw.trim();
  if (name.isEmpty) return 'Hermes';
  if (name != name.toLowerCase() && name != name.toUpperCase()) return name;
  return name
      .split(RegExp(r'\s+'))
      .map(
        (word) => word.isEmpty
            ? word
            : '${word[0].toUpperCase()}${word.substring(1).toLowerCase()}',
      )
      .join(' ');
}

/// Cabecera de un mensaje del asistente: avatar-chip con presencia + dos
/// líneas (nombre y «modelo · hora») + acciones a la derecha.
class MessageAvatarHeader extends StatelessWidget {
  const MessageAvatarHeader({
    required this.name,
    required this.state,
    this.model,
    this.time,
    this.mascot,
    this.stateLabel,
    this.actions = const [],
    super.key,
  });

  final String name;
  final AvatarRingState state;
  final String? model;
  final String? time;
  final Widget? mascot;

  /// Palabra de estado solo para lectores de pantalla («en curso»…).
  final String? stateLabel;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).hermes;
    final title = displayAgentName(name);
    final secondary = [
      if (model != null && model!.trim().isNotEmpty) model!.trim(),
      if (time != null && time!.trim().isNotEmpty) time!.trim(),
    ].join(' · ');
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: kAvatarChipSize),
      child: Row(
        children: [
          AvatarChip(name: name, state: state, mascot: mascot),
          const SizedBox(width: 10),
          Expanded(
            child: Semantics(
              container: true,
              label: [
                title,
                ?stateLabel,
                if (secondary.isNotEmpty) secondary,
              ].join(', '),
              excludeSemantics: true,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    key: const ValueKey('assistant-header-name'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w700,
                      color: colors.textPrimary,
                    ),
                  ),
                  if (secondary.isNotEmpty)
                    Text(
                      secondary,
                      key: const ValueKey('assistant-header-subtitle'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11.5,
                        color: colors.textSecondary,
                      ),
                    ),
                ],
              ),
            ),
          ),
          ...actions,
        ],
      ),
    );
  }
}
