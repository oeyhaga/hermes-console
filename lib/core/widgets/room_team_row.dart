import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../models/agent_profile.dart';
import '../theme/app_theme.dart';
import 'mission_profile_avatar.dart';

/// A single member in a room team, shared by local and hosted room surfaces.
class RoomTeamRow extends StatelessWidget {
  final String profileName;
  final String handle;
  final String displayName;
  final AgentProfile? profile;
  final MissionProfileAvatarCache? avatarCache;
  final bool manager;
  final String? roleLabel;
  final String? statusLabel;
  final Color? statusColor;
  final String? subtitle;
  final bool needsYou;
  final bool unavailable;
  final VoidCallback? onTap;
  final VoidCallback? onSecondaryAction;
  final IconData? secondaryActionIcon;

  const RoomTeamRow({
    required this.profileName,
    required this.handle,
    required this.displayName,
    this.profile,
    required this.avatarCache,
    this.manager = false,
    this.roleLabel,
    this.statusLabel,
    this.statusColor,
    this.subtitle,
    this.needsYou = false,
    this.unavailable = false,
    this.onTap,
    this.onSecondaryAction,
    this.secondaryActionIcon,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).hermes;
    final handleLabel = handle.startsWith('@') ? handle : '@$handle';
    final semanticsLabel = [
      displayName,
      handleLabel,
      ?roleLabel,
      ?statusLabel,
    ].join(', ');
    final row = ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 48),
      child: Padding(
        padding: const EdgeInsetsDirectional.fromSTEB(4, 6, 0, 6),
        child: Row(
          children: [
            KeyedSubtree(
              key: ValueKey('room-team-avatar-$profileName'),
              child: _avatar(),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          displayName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 15.5,
                            fontWeight: FontWeight.w700,
                            letterSpacing: -0.1,
                          ),
                        ),
                      ),
                      if (roleLabel != null) ...[
                        const SizedBox(width: 7),
                        _RoomTeamPill(
                          key: ValueKey('room-team-role-$profileName'),
                          label: roleLabel!,
                          color: manager ? colors.warning : colors.accentText,
                        ),
                      ],
                      if (needsYou) ...[
                        const SizedBox(width: 7),
                        _RoomTeamPill(
                          key: ValueKey('room-team-needs-you-$profileName'),
                          label: Strings.of(context).slActivityWaiting,
                          color: colors.warning,
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle == null ? handleLabel : '$handleLabel · $subtitle',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: colors.textSecondary,
                      fontSize: 12.5,
                    ),
                  ),
                ],
              ),
            ),
            if (statusLabel != null) ...[
              const SizedBox(width: 10),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 112),
                child: _RoomTeamPill(
                  key: ValueKey('room-team-status-$profileName'),
                  label: statusLabel!,
                  color: statusColor ?? colors.accentText,
                ),
              ),
            ] else if (onSecondaryAction != null)
              IconButton(
                key: ValueKey('room-team-secondary-action-$profileName'),
                onPressed: onSecondaryAction,
                icon: Icon(
                  secondaryActionIcon ?? Icons.message_outlined,
                  size: 20,
                ),
                color: colors.textSecondary,
                constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
              ),
          ],
        ),
      ),
    );
    final visibleRow = unavailable
        ? Opacity(
            key: ValueKey('room-team-unavailable-$profileName'),
            opacity: 0.55,
            child: ColorFiltered(
              colorFilter: const ColorFilter.mode(
                Colors.grey,
                BlendMode.saturation,
              ),
              child: row,
            ),
          )
        : row;
    final actionableRow = onTap == null
        ? visibleRow
        : Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: onTap,
              excludeFromSemantics: true,
              borderRadius: BorderRadius.circular(12),
              child: visibleRow,
            ),
          );
    return Semantics(
      key: ValueKey('room-team-member-$profileName'),
      container: true,
      button: onTap != null,
      label: semanticsLabel,
      onTap: onTap,
      excludeSemantics: true,
      child: actionableRow,
    );
  }

  Widget _avatar() {
    final resolvedProfile = profile;
    if (resolvedProfile == null) {
      return _NeutralRoomTeamAvatar(profileName: profileName, manager: manager);
    }
    return MissionProfileAvatar(
      profileName: profileName,
      hasAvatar: resolvedProfile.hasAvatar,
      cache: avatarCache,
      size: 42,
      manager: manager,
      shape: resolvedProfile.botShape,
      colorHex: resolvedProfile.botColorHex,
      imageKind: resolvedProfile.botImageKind,
      privacySafeElementKeys: true,
    );
  }
}

class _RoomTeamPill extends StatelessWidget {
  final String label;
  final Color color;

  const _RoomTeamPill({required this.label, required this.color, super.key});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.14),
      borderRadius: BorderRadius.circular(999),
      border: Border.all(color: color.withValues(alpha: 0.4)),
    ),
    child: Text(
      label,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        color: color,
        fontSize: 10.5,
        fontWeight: FontWeight.w700,
      ),
    ),
  );
}

class _NeutralRoomTeamAvatar extends StatelessWidget {
  final String profileName;
  final bool manager;

  const _NeutralRoomTeamAvatar({
    required this.profileName,
    required this.manager,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).hermes;
    var hash = 0x811c9dc5;
    for (final unit in profileName.codeUnits) {
      hash = (hash ^ unit) * 0x01000193;
    }
    final hue = (hash & 0x7fffffff) % 360;
    final color = HSLColor.fromAHSL(1, hue.toDouble(), 0.38, 0.54).toColor();
    return ExcludeSemantics(
      child: Container(
        width: 42,
        height: 42,
        padding: manager ? const EdgeInsets.all(2) : EdgeInsets.zero,
        decoration: manager
            ? BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: colors.warning.withValues(alpha: 0.82),
                  width: 1.25,
                ),
              )
            : null,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.84),
            shape: BoxShape.circle,
          ),
          child: const Center(
            child: Icon(Icons.circle_outlined, size: 16, color: Colors.white70),
          ),
        ),
      ),
    );
  }
}
