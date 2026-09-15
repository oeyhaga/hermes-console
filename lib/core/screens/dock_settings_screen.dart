import 'dart:async';

import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../models/dock_config.dart';
import '../services/dock_preferences_store.dart';
import '../theme/app_theme.dart';
import '../widgets/dock_style.dart';
import '../widgets/hermes_ui.dart';

enum _DockTab { bots, general }

/// Ajustes › Dock: entorno real de personalización de los dos perfiles de
/// dock (Bots/General). Cada perfil guarda su propio orden de elementos,
/// visibilidad, elemento destacado, comportamiento de "Atrás" y estilo
/// (bordes/transparencia/profundidad) — nada se comparte entre perfiles.
class DockSettingsScreen extends StatefulWidget {
  const DockSettingsScreen({super.key});

  @override
  State<DockSettingsScreen> createState() => _DockSettingsScreenState();
}

class _DockSettingsScreenState extends State<DockSettingsScreen> {
  final _controller = DockPreferencesController.instance;
  _DockTab _tab = _DockTab.bots;

  Future<void> _updateProfile(
    DockProfileConfig Function(DockProfileConfig) update,
  ) => _tab == _DockTab.bots
      ? _controller.updateBots(update)
      : _controller.updateGeneral(update);

  Future<void> _reset() => _tab == _DockTab.bots
      ? _controller.resetBots()
      : _controller.resetGeneral();

  @override
  Widget build(BuildContext context) {
    final strings = Strings.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(strings.dockSettingsTitle),
        actions: [
          TextButton(
            onPressed: () => unawaited(_reset()),
            child: Text(strings.dockSettingsReset),
          ),
        ],
      ),
      body: ListenableBuilder(
        listenable: _controller.listenable,
        builder: (context, _) {
          final prefs = _controller.value;
          final profile = _tab == _DockTab.bots ? prefs.bots : prefs.general;
          return _DockSettingsBody(
            tab: _tab,
            profile: profile,
            onTabChanged: (tab) => setState(() => _tab = tab),
            onUpdate: _updateProfile,
          );
        },
      ),
    );
  }
}

class _DockSettingsBody extends StatelessWidget {
  final _DockTab tab;
  final DockProfileConfig profile;
  final ValueChanged<_DockTab> onTabChanged;
  final Future<void> Function(DockProfileConfig Function(DockProfileConfig))
  onUpdate;

  const _DockSettingsBody({
    required this.tab,
    required this.profile,
    required this.onTabChanged,
    required this.onUpdate,
  });

  @override
  Widget build(BuildContext context) {
    final strings = Strings.of(context);
    final colors = Theme.of(context).hermes;
    final visibleCount = profile.items.where((i) => i.visible).length;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
      children: [
        _Segmented<_DockTab>(
          height: 38,
          values: const [_DockTab.bots, _DockTab.general],
          selected: tab,
          labelOf: (t) => t == _DockTab.bots
              ? strings.dockProfileBots
              : strings.dockProfileGeneral,
          onChanged: onTabChanged,
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(2, 8, 2, 0),
          child: Text(
            tab == _DockTab.bots
                ? strings.dockProfileBotsDescription
                : strings.dockProfileGeneralDescription,
            style: TextStyle(fontSize: 12.5, color: colors.textSecondary),
          ),
        ),
        HermesSectionHeader(strings.dockPreviewSectionTitle),
        _DockPreview(profile: profile),
        HermesSectionHeader(
          strings.dockItemsSectionTitle,
          trailing: Text(
            strings.dockItemsVisibleCount(visibleCount, profile.items.length),
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: colors.textSecondary.withValues(alpha: 0.85),
            ),
          ),
        ),
        _DockItemList(profile: profile, tab: tab, onUpdate: onUpdate),
        HermesSectionHeader(strings.dockBehaviorSectionTitle),
        HermesGroup(
          children: [
            HermesSwitchTile(
              controlKey: const ValueKey('dock-settings-show-back'),
              title: strings.dockShowBackTitle,
              subtitle: strings.dockShowBackSubtitle,
              value: profile.showBackOnSubscreens,
              onChanged: (value) => unawaited(
                onUpdate((p) => p.copyWith(showBackOnSubscreens: value)),
              ),
            ),
          ],
        ),
        HermesSectionHeader(strings.dockStyleSectionTitle),
        _DockStyleEditor(profile: profile, onUpdate: onUpdate),
      ],
    );
  }
}

/// Vista previa en vivo: el mismo `DockBar`/`DockItemTile` que usa el dock
/// real, sin acciones, para que el resultado de tocar cualquier control de
/// esta pantalla se vea al instante.
class _DockPreview extends StatelessWidget {
  final DockProfileConfig profile;

  const _DockPreview({required this.profile});

  @override
  Widget build(BuildContext context) {
    final strings = Strings.of(context);
    final colors = Theme.of(context).hermes;
    final visual = resolveDockVisual(colors, profile.style);
    final slots = resolveDockSlots(
      visibleItems: profile.visibleItemIds,
      pinnedItemId: profile.pinnedItemId,
      showBack: false,
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: DockBar(
        style: profile.style,
        children: [
          for (final slot in slots)
            if (slot != null)
              DockItemTile(
                icon: dockItemVisual(slot).icon,
                selectedIcon: dockItemVisual(slot).selectedIcon,
                label: dockItemLabel(strings, slot),
                selected: slot == profile.items.first.id,
                accent: slot == profile.pinnedItemId,
                innerRadius: visual.innerRadius,
              ),
        ],
      ),
    );
  }
}

class _DockItemList extends StatelessWidget {
  final DockProfileConfig profile;
  final _DockTab tab;
  final Future<void> Function(DockProfileConfig Function(DockProfileConfig))
  onUpdate;

  const _DockItemList({
    required this.profile,
    required this.tab,
    required this.onUpdate,
  });

  String? _subtitleFor(Strings strings, DockItemId id) {
    if (id != DockItemId.create) return null;
    return tab == _DockTab.bots
        ? strings.dockCreateBotsSubtitle
        : strings.dockCreateGeneralSubtitle;
  }

  @override
  Widget build(BuildContext context) {
    final strings = Strings.of(context);
    final colors = Theme.of(context).hermes;
    final items = profile.items;
    return HermesGroup(
      children: [
        SizedBox(
          height: 54.0 * items.length,
          child: ReorderableListView.builder(
            buildDefaultDragHandles: false,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: items.length,
            onReorderItem: (oldIndex, newIndex) {
              final next = List<DockItemConfig>.from(items);
              final moved = next.removeAt(oldIndex);
              next.insert(newIndex, moved);
              unawaited(onUpdate((p) => p.copyWith(items: next)));
            },
            itemBuilder: (context, index) {
              final item = items[index];
              final visual = dockItemVisual(item.id);
              final pinned = item.id == profile.pinnedItemId;
              return Container(
                key: ValueKey('dock-item-${item.id.name}'),
                height: 54,
                decoration: index == items.length - 1
                    ? null
                    : BoxDecoration(
                        border: Border(
                          bottom: BorderSide(
                            color: colors.divider.withValues(alpha: 0.6),
                          ),
                        ),
                      ),
                child: Row(
                  children: [
                    ReorderableDragStartListener(
                      index: index,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        child: Icon(
                          Icons.drag_indicator_rounded,
                          size: 20,
                          color: colors.textDisabled,
                        ),
                      ),
                    ),
                    Icon(
                      visual.icon,
                      size: 21,
                      color: item.visible
                          ? colors.textPrimary
                          : colors.textDisabled,
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            dockItemLabel(strings, item.id),
                            style: TextStyle(
                              fontSize: 14.5,
                              fontWeight: FontWeight.w500,
                              color: item.visible
                                  ? colors.textPrimary
                                  : colors.textDisabled,
                            ),
                          ),
                          if (_subtitleFor(strings, item.id) != null)
                            Padding(
                              padding: const EdgeInsets.only(top: 2),
                              child: Text(
                                _subtitleFor(strings, item.id)!,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: colors.textSecondary,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                    Tooltip(
                      message: strings.dockItemPinnedLabel,
                      child: InkWell(
                        customBorder: const CircleBorder(),
                        onTap: () => unawaited(
                          onUpdate(
                            (p) => p.copyWith(
                              pinnedItemId: item.id,
                              items: [
                                for (final it in p.items)
                                  it.id == item.id
                                      ? it.copyWith(visible: true)
                                      : it,
                              ],
                            ),
                          ),
                        ),
                        child: Container(
                          width: 18,
                          height: 18,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: pinned
                                  ? colors.accentText
                                  : colors.textDisabled,
                              width: 1.5,
                            ),
                          ),
                          child: pinned
                              ? Container(
                                  width: 8,
                                  height: 8,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: colors.accentText,
                                  ),
                                )
                              : null,
                        ),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Switch(
                      value: item.visible,
                      // El destacado nunca se retira: no se puede ocultar
                      // desde aquí (hay que quitarle antes el destacado).
                      onChanged: pinned
                          ? null
                          : (value) => unawaited(
                              onUpdate(
                                (p) => p.copyWith(
                                  items: [
                                    for (final it in p.items)
                                      it.id == item.id
                                          ? it.copyWith(visible: value)
                                          : it,
                                  ],
                                ),
                              ),
                            ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _DockStyleEditor extends StatelessWidget {
  final DockProfileConfig profile;
  final Future<void> Function(DockProfileConfig Function(DockProfileConfig))
  onUpdate;

  const _DockStyleEditor({required this.profile, required this.onUpdate});

  @override
  Widget build(BuildContext context) {
    final strings = Strings.of(context);
    final colors = Theme.of(context).hermes;
    final style = profile.style;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          strings.dockStyleBorderLabel,
          style: TextStyle(
            fontSize: 14.5,
            fontWeight: FontWeight.w500,
            color: colors.textPrimary,
          ),
        ),
        const SizedBox(height: 8),
        _Segmented<DockBorderShape>(
          height: 30,
          values: DockBorderShape.values,
          selected: style.borderShape,
          labelOf: (shape) => switch (shape) {
            DockBorderShape.square => strings.dockStyleBorderSquare,
            DockBorderShape.soft => strings.dockStyleBorderSoft,
            DockBorderShape.rounded => strings.dockStyleBorderRounded,
          },
          onChanged: (shape) => unawaited(
            onUpdate(
              (p) => p.copyWith(style: style.copyWith(borderShape: shape)),
            ),
          ),
        ),
        const SizedBox(height: 20),
        Row(
          children: [
            Expanded(
              child: Text(
                strings.dockStyleTransparencyLabel,
                style: TextStyle(
                  fontSize: 14.5,
                  fontWeight: FontWeight.w500,
                  color: colors.textPrimary,
                ),
              ),
            ),
            Text(
              '${(style.transparency * 100).round()} %',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: colors.textSecondary,
              ),
            ),
          ],
        ),
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            activeTrackColor: colors.accentText,
            inactiveTrackColor: colors.divider,
            thumbColor: colors.textPrimary,
            overlayColor: colors.accentText.withValues(alpha: 0.15),
            trackHeight: 4,
          ),
          child: Slider(
            value: style.transparency,
            onChanged: (value) => unawaited(
              onUpdate(
                (p) => p.copyWith(style: style.copyWith(transparency: value)),
              ),
            ),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          strings.dockStyleDepthLabel,
          style: TextStyle(
            fontSize: 14.5,
            fontWeight: FontWeight.w500,
            color: colors.textPrimary,
          ),
        ),
        const SizedBox(height: 8),
        _Segmented<DockDepth>(
          height: 30,
          values: DockDepth.values,
          selected: style.depth,
          labelOf: (depth) => switch (depth) {
            DockDepth.flat => strings.dockStyleDepthFlat,
            DockDepth.elevated => strings.dockStyleDepthElevated,
            DockDepth.floating => strings.dockStyleDepthFloating,
          },
          onChanged: (depth) => unawaited(
            onUpdate((p) => p.copyWith(style: style.copyWith(depth: depth))),
          ),
        ),
      ],
    );
  }
}

/// Control segmentado genérico (perfil / bordes / profundidad): misma
/// píldora con relleno deslizante en las tres pantallas.
class _Segmented<T> extends StatelessWidget {
  final double height;
  final List<T> values;
  final T selected;
  final String Function(T) labelOf;
  final ValueChanged<T> onChanged;

  const _Segmented({
    required this.height,
    required this.values,
    required this.selected,
    required this.labelOf,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).hermes;
    return Container(
      height: height,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: colors.surface,
        border: Border.all(color: colors.divider),
        borderRadius: BorderRadius.circular(9),
      ),
      child: Row(
        children: [
          for (final value in values)
            Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => onChanged(value),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: value == selected ? colors.surfaceVariant : null,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    labelOf(value),
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: value == selected
                          ? FontWeight.w600
                          : FontWeight.w500,
                      color: value == selected
                          ? colors.textPrimary
                          : colors.textSecondary,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
