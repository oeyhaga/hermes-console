import 'dart:async';

import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../models/agent_task_list.dart';
import '../services/session_reconciler.dart';
import '../theme/app_theme.dart';
import 'hermes_premium_ui.dart';

/// Etiquetas con las que el gateway nombra la herramienta de lista de tareas
/// (`todo_list`; `todo` en transcripts anteriores al renombrado).
bool isAgentTaskToolLabel(String label) {
  final normalized = label.trim().toLowerCase();
  return normalized == 'todo_list' || normalized == 'todo';
}

/// Id del paso `todo_list` más reciente del transcript, o `null`.
///
/// La lista de tareas de la sesión es UNA (la última que escribió el agente);
/// se cuelga del bloque de actividad del turno que la escribió. Los mensajes
/// llegan más nuevo primero (`ActiveChat.messages`).
String? latestAgentTaskStepId(List<Map<String, dynamic>> messagesNewestFirst) {
  for (final message in messagesNewestFirst) {
    if (message['role'] != 'assistant') continue;
    final trace = message[assistantActivityTraceKey];
    if (trace is! List) continue;
    for (var i = trace.length - 1; i >= 0; i--) {
      final step = trace[i];
      if (step is! Map || step['kind'] != 'tool') continue;
      if (!isAgentTaskToolLabel('${step['label'] ?? ''}')) continue;
      final id = step['id']?.toString().trim();
      return id == null || id.isEmpty ? null : id;
    }
  }
  return null;
}

/// Entrega la lista de tareas de la sesión y el paso que la posee a los
/// bloques de actividad del transcript, sin añadir parámetros a los tres
/// envoltorios de mensaje del chat.
class AgentTaskScope extends InheritedWidget {
  const AgentTaskScope({
    required this.tasks,
    required this.ownerStepId,
    required super.child,
    super.key,
  });

  final AgentTaskList? tasks;
  final String? ownerStepId;

  static AgentTaskScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AgentTaskScope>();

  /// La lista, únicamente si [eventIds] contiene el paso `todo_list` que la
  /// posee. Así solo UN bloque de actividad la muestra.
  static AgentTaskList? ownedBy(
    BuildContext context,
    Iterable<({String id, String label})> steps,
  ) {
    final scope = maybeOf(context);
    final tasks = scope?.tasks;
    final owner = scope?.ownerStepId;
    if (tasks == null || tasks.isEmpty || owner == null) return null;
    for (final step in steps) {
      if (step.id == owner && isAgentTaskToolLabel(step.label)) return tasks;
    }
    return null;
  }

  @override
  bool updateShouldNotify(AgentTaskScope oldWidget) =>
      oldWidget.ownerStepId != ownerStepId ||
      !identical(oldWidget.tasks, tasks);
}

double _textScale(BuildContext context) =>
    MediaQuery.textScalerOf(context).scale(13) / 13;

String _statusWord(Strings s, AgentTaskStatus status) => switch (status) {
  AgentTaskStatus.pending => s.agentTasksStatusPending,
  AgentTaskStatus.inProgress => s.agentTasksStatusInProgress,
  AgentTaskStatus.completed => s.agentTasksStatusCompleted,
  AgentTaskStatus.cancelled => s.agentTasksStatusCancelled,
};

// ─────────────────────────────────────────────────────────────────────────────
// Píldora «Tareas 3/7»
// ─────────────────────────────────────────────────────────────────────────────

/// Píldora flotante de la lista de tareas del agente.
///
/// Sigue el lenguaje de `TurnActivityPill`/`SubagentActivityCard`: vive en la
/// columna de píldoras sobre el compositor (dentro del stack del transcript,
/// nunca encima del input) y colapsa a cero cuando no hay nada que contar.
///
/// Ciclo de vida (mismas reglas que Desktop, `store/todos.ts`):
///  * visible mientras la lista tiene elementos abiertos Y hay un turno vivo;
///  * al terminar el turno con la lista a medias desaparece (la lista sigue en
///    el bloque de actividad del turno, marcada «incompleta»);
///  * al completarse mientras se ve, muestra el check y se queda
///    [lingerAfterFinished] para que se vea cómo cae la última marca.
class AgentTaskPill extends StatefulWidget {
  const AgentTaskPill({
    required this.tasks,
    required this.turnActive,
    required this.onTap,
    this.lingerAfterFinished = const Duration(seconds: 4),
    super.key,
  });

  final AgentTaskList tasks;
  final bool turnActive;
  final VoidCallback onTap;
  final Duration lingerAfterFinished;

  @override
  State<AgentTaskPill> createState() => _AgentTaskPillState();
}

class _AgentTaskPillState extends State<AgentTaskPill> {
  Timer? _lingerTimer;
  bool _lingering = false;

  bool _shown(AgentTaskList tasks, bool turnActive, bool lingering) =>
      tasks.isNotEmpty &&
      ((tasks.hasOpen && turnActive) || (tasks.isFinished && lingering));

  @override
  void initState() {
    super.initState();
    if (widget.tasks.isFinished && widget.turnActive) _startLinger();
  }

  @override
  void didUpdateWidget(AgentTaskPill oldWidget) {
    super.didUpdateWidget(oldWidget);
    final tasks = widget.tasks;
    if (!tasks.isFinished) {
      _cancelLinger();
      return;
    }
    if (!oldWidget.tasks.isFinished &&
        (widget.turnActive ||
            _shown(oldWidget.tasks, oldWidget.turnActive, _lingering))) {
      _startLinger();
    }
  }

  void _startLinger() {
    _lingerTimer?.cancel();
    _lingering = true;
    _lingerTimer = Timer(widget.lingerAfterFinished, () {
      _lingerTimer = null;
      if (!mounted) return;
      setState(() => _lingering = false);
    });
  }

  void _cancelLinger() {
    _lingerTimer?.cancel();
    _lingerTimer = null;
    _lingering = false;
  }

  @override
  void dispose() {
    _lingerTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tasks = widget.tasks;
    final visible = _shown(tasks, widget.turnActive, _lingering);
    final reduceMotion = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    return AnimatedSwitcher(
      duration: reduceMotion
          ? Duration.zero
          : const Duration(milliseconds: 180),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      layoutBuilder: (current, previous) => Stack(
        alignment: Alignment.bottomCenter,
        children: [...previous, ?current],
      ),
      transitionBuilder: (child, animation) => FadeTransition(
        opacity: animation,
        child: SizeTransition(sizeFactor: animation, child: child),
      ),
      child: visible
          ? _PillBody(
              key: const ValueKey('agent-task-pill'),
              tasks: tasks,
              onTap: widget.onTap,
            )
          : const SizedBox.shrink(key: ValueKey('agent-task-pill-idle')),
    );
  }
}

class _PillBody extends StatelessWidget {
  const _PillBody({required this.tasks, required this.onTap, super.key});

  final AgentTaskList tasks;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).hermes;
    final s = Strings.of(context);
    final finished = tasks.isFinished;
    final title = s.agentTasksPillTitle(tasks.done, tasks.total);
    final currentItem =
        tasks.current ??
        tasks.rows.map((row) => row.item).where((i) => i.isOpen).firstOrNull;
    final subtitle = finished ? s.agentTasksAllDone : currentItem?.content;
    // A escala de texto grande la píldora se queda en UNA línea: el subtítulo
    // sigue disponible para lectores de pantalla en la etiqueta semántica.
    final showSubtitle =
        subtitle != null && subtitle.isNotEmpty && _textScale(context) < 1.6;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
      child: Semantics(
        button: true,
        container: true,
        label: [title, ?subtitle].join('. '),
        hint: s.agentTasksShowList,
        onTap: onTap,
        excludeSemantics: true,
        child: Material(
          color: colors.surface,
          shape: StadiumBorder(
            side: BorderSide(color: colors.divider, width: 0.8),
          ),
          clipBehavior: Clip.antiAlias,
          elevation: 10,
          shadowColor: Colors.black.withValues(alpha: 0.45),
          child: InkWell(
            onTap: onTap,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 48, maxWidth: 320),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 6, 10, 6),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: 22,
                      height: 22,
                      child: finished
                          ? Icon(
                              Icons.check_circle_rounded,
                              key: const ValueKey('agent-task-pill-done'),
                              size: 22,
                              color: colors.success,
                            )
                          : CircularProgressIndicator(
                              key: const ValueKey('agent-task-pill-ring'),
                              value: tasks.progress,
                              strokeWidth: 2.6,
                              backgroundColor: colors.divider,
                              color: colors.accent,
                            ),
                    ),
                    const SizedBox(width: 10),
                    Flexible(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            key: const ValueKey('agent-task-pill-title'),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: colors.textPrimary,
                            ),
                          ),
                          if (showSubtitle)
                            Text(
                              subtitle,
                              key: const ValueKey('agent-task-pill-subtitle'),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 12,
                                color: colors.textSecondary,
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 4),
                    Icon(
                      Icons.chevron_right_rounded,
                      size: 18,
                      color: colors.textSecondary,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Lista + tarjeta
// ─────────────────────────────────────────────────────────────────────────────

/// Cabecera «Tareas 3/7 · 1 cancelada» con barra de progreso fina.
class AgentTaskHeader extends StatelessWidget {
  const AgentTaskHeader({
    required this.tasks,
    this.incomplete = false,
    this.dense = false,
    super.key,
  });

  final AgentTaskList tasks;

  /// Turno terminado con elementos abiertos: se anota «incompleta» (igual que
  /// el archivo de la TUI).
  final bool incomplete;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).hermes;
    final s = Strings.of(context);
    final cancelled = tasks.cancelledCount;
    final extras = [
      if (cancelled > 0) s.agentTasksCancelledCount(cancelled),
      if (incomplete) s.agentTasksIncomplete,
    ];
    return Semantics(
      container: true,
      header: true,
      label: [
        s.agentTasksSummary(tasks.done, tasks.total),
        ...extras,
      ].join(', '),
      excludeSemantics: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text.rich(
            key: const ValueKey('agent-task-header'),
            TextSpan(
              children: [
                TextSpan(
                  text: s.agentTasksPillTitle(tasks.done, tasks.total),
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: colors.textPrimary,
                  ),
                ),
                if (extras.isNotEmpty)
                  TextSpan(
                    text: ' · ${extras.join(' · ')}',
                    style: TextStyle(color: colors.textSecondary),
                  ),
              ],
            ),
            style: TextStyle(fontSize: dense ? 12 : 14),
          ),
          SizedBox(height: dense ? 4 : 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(2),
            child: LinearProgressIndicator(
              key: const ValueKey('agent-task-progress'),
              value: tasks.progress,
              minHeight: 4,
              backgroundColor: colors.divider,
              color: tasks.isFinished ? colors.success : colors.accent,
            ),
          ),
        ],
      ),
    );
  }
}

/// Filas de la lista en orden de árbol. Sin scroll propio: el contenedor
/// (tarjeta flotante o bloque de actividad) decide el alto.
class AgentTaskChecklist extends StatelessWidget {
  const AgentTaskChecklist({
    required this.tasks,
    this.dense = false,
    super.key,
  });

  final AgentTaskList tasks;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final s = Strings.of(context);
    final colors = Theme.of(context).hermes;
    return Column(
      key: const ValueKey('agent-task-checklist'),
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final row in tasks.rows)
          _TaskRow(
            key: ValueKey('agent-task-row-${row.item.id}'),
            item: row.item,
            depth: row.depth,
            dense: dense,
          ),
        if (tasks.omitted > 0)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              s.agentTasksMore(tasks.omitted),
              style: TextStyle(fontSize: 12, color: colors.textSecondary),
            ),
          ),
      ],
    );
  }
}

class _TaskRow extends StatelessWidget {
  const _TaskRow({
    required this.item,
    required this.depth,
    required this.dense,
    super.key,
  });

  final AgentTaskItem item;
  final int depth;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).hermes;
    final s = Strings.of(context);
    final reduceMotion = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    final iconSize = dense ? 14.0 : 18.0;
    final Widget icon = switch (item.status) {
      AgentTaskStatus.completed => Icon(
        Icons.check_circle_rounded,
        key: const ValueKey('agent-task-icon-completed'),
        size: iconSize,
        color: colors.success,
      ),
      AgentTaskStatus.inProgress =>
        reduceMotion
            // Movimiento reducido: marca estática, sin spinner animado.
            ? Icon(
                Icons.play_circle_outline_rounded,
                key: const ValueKey('agent-task-icon-in-progress'),
                size: iconSize,
                color: colors.accent,
              )
            : SizedBox(
                key: const ValueKey('agent-task-icon-in-progress'),
                width: iconSize - 2,
                height: iconSize - 2,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: colors.accent,
                ),
              ),
      AgentTaskStatus.pending => Icon(
        Icons.radio_button_unchecked_rounded,
        key: const ValueKey('agent-task-icon-pending'),
        size: iconSize,
        color: colors.textSecondary,
      ),
      AgentTaskStatus.cancelled => Icon(
        Icons.block_rounded,
        key: const ValueKey('agent-task-icon-cancelled'),
        size: iconSize,
        color: colors.textSecondary,
      ),
    };
    final textStyle = switch (item.status) {
      AgentTaskStatus.inProgress => TextStyle(
        fontWeight: FontWeight.w600,
        color: colors.textPrimary,
      ),
      AgentTaskStatus.pending => TextStyle(color: colors.textPrimary),
      AgentTaskStatus.completed => TextStyle(
        color: colors.textSecondary,
        decoration: TextDecoration.lineThrough,
        decorationColor: colors.textSecondary,
      ),
      AgentTaskStatus.cancelled => TextStyle(
        color: colors.textSecondary,
        fontStyle: FontStyle.italic,
      ),
    };
    final indent = (depth > 3 ? 3 : depth) * (dense ? 12.0 : 16.0);
    return Semantics(
      container: true,
      label: '${_statusWord(s, item.status)}: ${item.content}',
      excludeSemantics: true,
      child: Padding(
        padding: EdgeInsets.only(
          left: indent,
          top: dense ? 2 : 4,
          bottom: dense ? 2 : 4,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: iconSize + 2,
              height: (dense ? 12.0 : 14.0) * 1.35 + 2,
              child: Center(child: icon),
            ),
            SizedBox(width: dense ? 6 : 8),
            Expanded(
              child: Text(
                item.content,
                style: textStyle.copyWith(
                  fontSize: dense ? 12 : 14,
                  height: 1.35,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Contenido de la tarjeta flotante: cabecera + lista, con scroll propio.
class AgentTaskCardBody extends StatelessWidget {
  const AgentTaskCardBody({required this.tasks, super.key});

  final AgentTaskList tasks;

  @override
  Widget build(BuildContext context) {
    final s = Strings.of(context);
    final colors = Theme.of(context).hermes;
    return ListView(
      shrinkWrap: true,
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
      children: [
        if (tasks.isEmpty)
          Text(
            s.agentTasksEmpty,
            style: TextStyle(fontSize: 14, color: colors.textSecondary),
          )
        else ...[
          AgentTaskHeader(tasks: tasks),
          const SizedBox(height: 12),
          AgentTaskChecklist(tasks: tasks),
        ],
      ],
    );
  }
}

/// Abre la tarjeta flotante. Se actualiza en vivo con [changes] (los eventos
/// del chat) leyendo la lista actual con [read].
Future<void> showAgentTaskCard(
  BuildContext context, {
  required Stream<Object?> changes,
  required AgentTaskList Function() read,
}) {
  return showHermesFloatingSurface<void>(
    context: context,
    surfaceKey: const ValueKey('agent-task-card'),
    maxWidth: 480,
    builder: (_) => StreamBuilder<Object?>(
      stream: changes,
      builder: (context, _) => AgentTaskCardBody(tasks: read()),
    ),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Dentro del bloque de actividad del turno
// ─────────────────────────────────────────────────────────────────────────────

/// Chip «3/7» que acompaña al chevron del bloque de actividad plegado.
class AgentTaskChip extends StatelessWidget {
  const AgentTaskChip({required this.tasks, super.key});

  final AgentTaskList tasks;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).hermes;
    final finished = tasks.isFinished;
    final color = finished ? colors.success : colors.textSecondary;
    return Container(
      key: const ValueKey('agent-task-chip'),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.35), width: 0.8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            finished ? Icons.check_rounded : Icons.checklist_rounded,
            size: 12,
            color: color,
          ),
          const SizedBox(width: 3),
          Text(
            '${tasks.done}/${tasks.total}',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: color,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}

/// Lista dentro del bloque de actividad desplegado del turno.
class AgentTaskActivitySection extends StatelessWidget {
  const AgentTaskActivitySection({
    required this.tasks,
    required this.turnActive,
    super.key,
  });

  final AgentTaskList tasks;
  final bool turnActive;

  @override
  Widget build(BuildContext context) {
    return Padding(
      key: const ValueKey('agent-task-activity-section'),
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          AgentTaskHeader(
            tasks: tasks,
            dense: true,
            incomplete: !turnActive && tasks.hasOpen,
          ),
          const SizedBox(height: 6),
          AgentTaskChecklist(tasks: tasks, dense: true),
        ],
      ),
    );
  }
}
