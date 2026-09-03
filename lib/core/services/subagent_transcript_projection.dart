import 'dart:convert';

import '../models/subagent_activity.dart';
import '../utils/chat_turn.dart';
import 'subagent_activity_reducer.dart';

final class SubagentTranscriptProjection {
  final String? turnAnchor;
  final SubagentActivityState? state;

  const SubagentTranscriptProjection({
    required this.turnAnchor,
    required this.state,
  });
}

SubagentTranscriptProjection projectSubagentsFromTranscript({
  required List<Map<String, dynamic>> messagesNewestFirst,
  required SubagentActivityScope scope,
  SubagentActivityState? current,
  String? currentTurnAnchor,
}) {
  final chronological = messagesNewestFirst.reversed
      .map(Map<String, dynamic>.from)
      .toList(growable: false);
  var startIndex = -1;
  String? turnAnchor;
  for (var index = 0; index < chronological.length; index += 1) {
    final message = chronological[index];
    if (!isRealUserTurn(message)) continue;
    startIndex = index;
    turnAnchor = _messageIdentity(message);
  }
  if (startIndex < 0 || turnAnchor == null) {
    return SubagentTranscriptProjection(turnAnchor: null, state: current);
  }

  final currentBelongsToTurn =
      current != null &&
      current.scope == scope &&
      (currentTurnAnchor == null ||
          _messageIdentitiesMatch(currentTurnAnchor, turnAnchor));
  var state = currentBelongsToTurn
      ? current
      : SubagentActivityState.empty(scope);
  final delegateNamesByCallId = <String, String>{};
  var observed = false;

  for (final message in chronological.skip(startIndex + 1)) {
    final role = (message['role'] ?? '').toString().trim().toLowerCase();
    if (role == 'assistant') {
      final toolCalls = _list(message['tool_calls']);
      for (final rawCall in toolCalls) {
        final call = _map(rawCall);
        final function = _map(call?['function']);
        final name = _normalizedToolName(
          function?['name'] ?? call?['name'] ?? message['tool_name'],
        );
        final callId = _opaque(call?['id'] ?? call?['tool_call_id']);
        if (name != 'delegate_task' || callId == null) continue;
        delegateNamesByCallId[callId] = 'delegate_task';
        final event = SubagentActivityEvent.tryParseLegacyDelegateTool(
          type: 'tool.start',
          scope: scope,
          payload: {'name': 'delegate_task', 'tool_id': callId},
          toolName: 'delegate_task',
          toolCallId: callId,
          eventId: _eventIdentity(message, 'delegate-start', callId),
        );
        if (event == null) continue;
        state = SubagentActivityReducer.reduce(state, event);
        observed = true;
      }
      continue;
    }

    if (_isToolRole(role)) {
      final callId = _opaque(
        message['tool_call_id'] ?? message['tool_id'] ?? message['call_id'],
      );
      final name =
          _normalizedToolName(message['tool_name']) ??
          (callId == null ? null : delegateNamesByCallId[callId]);
      if (name != 'delegate_task' || callId == null) continue;
      final result = _decodedMap(message['content']);
      // The durable `delegate_task` result is the only recovery source that
      // carries every child identity. A single aggregate legacy event loses
      // N-1 rows after Console reopens, so replay one event per opaque id.
      final dispatchedIds = _list(result?['subagent_ids'])
          .map(_opaque)
          .whereType<String>()
          .toSet()
          .toList(growable: false);
      final resultStatus = result?['status']?.toString().trim().toLowerCase();
      final isAcceptedDispatch =
          resultStatus == 'dispatched' && dispatchedIds.isNotEmpty;
      final perChildResults = dispatchedIds.isEmpty
          ? <Map<String, dynamic>?>[result]
          : dispatchedIds
              .map(
                (subagentId) => <String, dynamic>{
                  ...?result,
                  'subagent_ids': [subagentId],
                },
              )
              .toList(growable: false);
      for (var index = 0; index < perChildResults.length; index += 1) {
        final childResult = perChildResults[index];
        final eventStableId = dispatchedIds.isEmpty
            ? callId
            : dispatchedIds[index];
        final event = SubagentActivityEvent.tryParseLegacyDelegateTool(
          // Only a confirmed dispatch with a durable child id is a start. A
          // rejected tool result must close the earlier aggregate tool.start;
          // otherwise rehydration leaves a failed delegation running forever.
          type: isAcceptedDispatch ? 'tool.start' : 'tool.complete',
          scope: scope,
          payload: {'name': name, 'tool_id': callId, 'result': ?childResult},
          toolName: name,
          toolCallId: callId,
          eventId: _eventIdentity(
            message,
            'delegate-complete',
            eventStableId,
          ),
        );
        if (event == null) continue;
        state = SubagentActivityReducer.reduce(state, event);
        observed = true;
      }
      continue;
    }

    if (effectiveUserDisplayKind(message) == 'async_delegation_complete') {
      final metadata = _decodedMap(message['display_metadata']);
      // Some persisted Gateway rows carry the authoritative batch id only in
      // the reserved sentinel, not in display_metadata. The sentinel grammar
      // is already fail-closed by effectiveUserDisplayKind; use that exact id
      // before falling back to an aggregate event.
      final delegationId =
          _opaque(metadata?['delegation_id']) ?? _delegationIdFromMarker(message);
      if (delegationId == null) continue;
      final failedCount = _nonNegativeInt(metadata?['failed_count']) ?? 0;
      final taskCount = _positiveInt(metadata?['task_count']);
      // Completion metadata is aggregate. A partial failed_count does not name
      // the child, so never paint every row as failed. Each known child is only
      // known to have finished; the aggregate failure remains represented by
      // the editorial completion card rather than fabricated per-child blame.
      final terminalStatus =
          taskCount != null && failedCount >= taskCount && failedCount > 0
          ? 'failed'
          : 'completed';
      // children. Fan it out only across the durable child ids already proven
      // by this same transcript; otherwise retain the aggregate event.
      final childIds = state.activities
          .where((activity) => activity.delegationId == delegationId)
          .map((activity) => activity.subagentId)
          .whereType<String>()
          .toSet()
          .toList(growable: false);
      final terminalPayloads = childIds.isEmpty
          ? <Map<String, Object?>>[
              {
                'delegation_id': delegationId,
                'status': terminalStatus,
                'task_count': _positiveInt(metadata?['task_count']),
                'duration_seconds': metadata?['duration_seconds'],
              },
            ]
          : childIds
              .map(
                (subagentId) => <String, Object?>{
                  'subagent_id': subagentId,
                  'delegation_id': delegationId,
                  'status': terminalStatus,
                  'task_count': _positiveInt(metadata?['task_count']),
                  'duration_seconds': metadata?['duration_seconds'],
                },
              )
              .toList(growable: false);
      for (final payload in terminalPayloads) {
        final event = SubagentActivityEvent.tryParseNative(
          type: 'subagent.complete',
          scope: scope,
          payload: payload,
          eventId: _eventIdentity(
            message,
            'delegation-complete',
            payload['subagent_id']?.toString() ?? delegationId,
          ),
        );
        if (event == null) continue;
        state = SubagentActivityReducer.reduce(state, event);
        observed = true;
      }
    }
  }

  return SubagentTranscriptProjection(
    turnAnchor: turnAnchor,
    state: observed || currentBelongsToTurn ? state : null,
  );
}

bool _isToolRole(String role) =>
    const {'tool', 'tool_result', 'function', 'function_call'}.contains(role);

String? _delegationIdFromMarker(Map<String, dynamic> message) {
  final content = (message['content'] ?? message['text'] ?? '').toString();
  final match = RegExp(
    r'^\[ASYNC DELEGATION (?:BATCH )?COMPLETE — (deleg_[0-9a-f]{8})\](?:\r?\n|$)',
  ).firstMatch(content);
  return match == null ? null : _opaque(match.group(1));
}

String? _normalizedToolName(Object? value) {
  final text = value?.toString().trim().toLowerCase() ?? '';
  if (text.isEmpty) return null;
  return text.split('.').last;
}

String? _opaque(Object? value) {
  final text = value?.toString().trim() ?? '';
  if (text.isEmpty || text.length > 180) return null;
  return RegExp(r'^[A-Za-z0-9._:-]+$').hasMatch(text) ? text : null;
}

String? _messageIdentity(Map<String, dynamic> message) {
  final identity = canonicalTranscriptIdentity(message);
  if (identity?.messageId != null && identity?.rowId != null) {
    return 'pair:${jsonEncode([identity!.messageId, identity.rowId])}';
  }
  if (identity?.messageId != null) return 'canonical:${identity!.messageId}';
  if (identity?.rowId != null) return 'row:${identity!.rowId}';
  final platform = message['platform_message_id'];
  if (platform != null) {
    final value = platform.toString();
    if (value.isNotEmpty && value.length <= 180) return 'platform:$value';
  }
  return null;
}

TranscriptMessageIdentity? _typedMessageIdentity(String value) {
  if (value.startsWith('canonical:')) {
    final messageId = value.substring('canonical:'.length);
    return messageId.isEmpty
        ? null
        : TranscriptMessageIdentity(messageId: messageId);
  }
  if (value.startsWith('row:')) {
    final rowId = int.tryParse(value.substring('row:'.length));
    return rowId == null || rowId <= 0
        ? null
        : TranscriptMessageIdentity(rowId: rowId);
  }
  if (!value.startsWith('pair:')) return null;
  try {
    final decoded = jsonDecode(value.substring('pair:'.length));
    if (decoded is! List || decoded.length != 2) return null;
    final messageId = decoded[0];
    final rowId = decoded[1];
    if (messageId is! String ||
        messageId.isEmpty ||
        rowId is! int ||
        rowId <= 0) {
      return null;
    }
    return TranscriptMessageIdentity(messageId: messageId, rowId: rowId);
  } catch (_) {
    return null;
  }
}

bool _messageIdentitiesMatch(String left, String right) {
  if (left == right) return true;
  final leftIdentity = _typedMessageIdentity(left);
  final rightIdentity = _typedMessageIdentity(right);
  return leftIdentity != null &&
      rightIdentity != null &&
      leftIdentity.matches(rightIdentity);
}

String _eventIdentity(
  Map<String, dynamic> message,
  String kind,
  String stableId,
) {
  final identity = canonicalTranscriptIdentity(message);
  final row = identity?.rowId != null
      ? 'row:${identity!.rowId}'
      : identity?.messageId != null
      ? 'canonical:${identity!.messageId}'
      : _messageIdentity(message) ?? 'unknown';
  return 'transcript:$row:$kind:$stableId';
}

List<Object?> _list(Object? value) {
  if (value is List) return value;
  if (value is String) {
    try {
      final decoded = jsonDecode(value);
      return decoded is List ? decoded : const [];
    } catch (_) {
      return const [];
    }
  }
  return const [];
}

Map<String, dynamic>? _map(Object? value) {
  if (value is! Map) return null;
  return value.map((key, item) => MapEntry(key.toString(), item));
}

Map<String, dynamic>? _decodedMap(Object? value) {
  final direct = _map(value);
  if (direct != null) return direct;
  if (value is! String || value.trim().isEmpty) return null;
  try {
    return _map(jsonDecode(value));
  } catch (_) {
    return null;
  }
}

int? _nonNegativeInt(Object? value) {
  final parsed = value is int ? value : int.tryParse(value?.toString() ?? '');
  return parsed != null && parsed >= 0 ? parsed : null;
}

int? _positiveInt(Object? value) {
  final parsed = _nonNegativeInt(value);
  return parsed != null && parsed > 0 ? parsed : null;
}
