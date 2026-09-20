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
  });

  final String id;
  final String command;
  final bool notifyOnComplete;
  final DateTime? startedAt;
}

final class SessionActivity {
  const SessionActivity({
    required this.foregroundTurn,
    required this.rosterTurn,
    required this.subagentCount,
    required this.processes,
    required this.foregroundKind,
    required this.observedAt,
    this.stale = false,
  });

  const SessionActivity.idle()
    : foregroundTurn = false,
      rosterTurn = false,
      subagentCount = 0,
      processes = const [],
      foregroundKind = SessionActivityKind.idle,
      observedAt = null,
      stale = false;

  final bool foregroundTurn;
  final bool rosterTurn;
  final int subagentCount;
  final List<SessionActivityProcess> processes;
  final SessionActivityKind foregroundKind;
  final DateTime? observedAt;
  final bool stale;

  bool get active =>
      foregroundTurn || rosterTurn || subagentCount > 0 || processes.isNotEmpty;

  bool get willNotifyLater => processes.any((process) => process.notifyOnComplete);

  SessionActivityKind get kind {
    if (foregroundTurn) return foregroundKind;
    if (subagentCount > 0) return SessionActivityKind.delegated;
    if (processes.isNotEmpty) return SessionActivityKind.backgroundProcess;
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
