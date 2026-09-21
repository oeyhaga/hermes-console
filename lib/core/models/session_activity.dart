enum SessionActivityKind {
  idle,
  preparing,
  generating,
  usingTools,
  responding,
  waitingForUser,
  compacting,
  delegated,
  backgroundProcess,
}

final class SessionActivityProcess {
  const SessionActivityProcess({
    required this.id,
    required this.command,
    required this.notifyOnComplete,
    required this.startedAt,
    this.watchPatterns = const [],
    this.watchHit = false,
  });

  final String id;
  final String command;
  final bool notifyOnComplete;
  final DateTime? startedAt;
  final List<String> watchPatterns;
  final bool watchHit;
}

enum SessionActivityScheduleKind { loop, heartbeat }

final class SessionActivitySchedule {
  const SessionActivitySchedule({
    required this.kind,
    required this.status,
    required this.interval,
    required this.lastRunAt,
    required this.nextDueAt,
    required this.runCount,
    this.awaitingResponse = false,
    this.deferredByGoal = false,
  });

  final SessionActivityScheduleKind kind;
  final String status;
  final Duration interval;
  final DateTime? lastRunAt;
  final DateTime? nextDueAt;
  final int runCount;
  final bool awaitingResponse;
  final bool deferredByGoal;
}

final class SessionActivityGoal {
  const SessionActivityGoal({required this.title, required this.status});

  final String title;
  final String status;
}

enum SessionActivityTaskStatus { pending, inProgress, completed, cancelled }

final class SessionActivityTask {
  const SessionActivityTask({
    required this.id,
    required this.content,
    required this.status,
  });

  final String id;
  final String content;
  final SessionActivityTaskStatus status;

  bool get pending =>
      status == SessionActivityTaskStatus.pending ||
      status == SessionActivityTaskStatus.inProgress;
}

final class SessionActivity {
  const SessionActivity({
    required this.foregroundTurn,
    required this.rosterTurn,
    required this.subagentCount,
    required this.processes,
    required this.foregroundKind,
    required this.observedAt,
    this.schedules = const [],
    this.goal,
    this.tasks = const [],
    this.stale = false,
  });

  const SessionActivity.idle()
    : foregroundTurn = false,
      rosterTurn = false,
      subagentCount = 0,
      processes = const [],
      schedules = const [],
      goal = null,
      tasks = const [],
      foregroundKind = SessionActivityKind.idle,
      observedAt = null,
      stale = false;

  final bool foregroundTurn;
  final bool rosterTurn;
  final int subagentCount;
  final List<SessionActivityProcess> processes;
  final List<SessionActivitySchedule> schedules;
  final SessionActivityGoal? goal;
  final List<SessionActivityTask> tasks;
  final SessionActivityKind foregroundKind;
  final DateTime? observedAt;
  final bool stale;

  List<SessionActivityTask> get pendingTasks =>
      tasks.where((task) => task.pending).toList(growable: false);

  int get backgroundItemCount =>
      processes.length +
      schedules.length +
      (goal == null ? 0 : 1) +
      pendingTasks.length;

  bool get active =>
      foregroundTurn ||
      rosterTurn ||
      subagentCount > 0 ||
      backgroundItemCount > 0;

  bool get willNotifyLater => processes.any((process) => process.notifyOnComplete);

  SessionActivityKind get kind {
    if (foregroundTurn) return foregroundKind;
    if (subagentCount > 0) return SessionActivityKind.delegated;
    if (backgroundItemCount > 0) return SessionActivityKind.backgroundProcess;
    if (rosterTurn) return SessionActivityKind.generating;
    return SessionActivityKind.idle;
  }

  String? get processCommand {
    for (final process in processes) {
      final command = process.command.trim();
      if (command.isNotEmpty) return command;
    }
    return null;
  }

  DateTime? get startedAt {
    if (processes.isEmpty) return null;
    DateTime? earliest;
    for (final process in processes) {
      final candidate = process.startedAt;
      if (candidate != null && (earliest == null || candidate.isBefore(earliest))) {
        earliest = candidate;
      }
    }
    return earliest ?? observedAt;
  }
}
