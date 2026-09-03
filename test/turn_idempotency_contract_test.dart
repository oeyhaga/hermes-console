import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:hermes_android/core/models/attachment_draft.dart';
import 'package:hermes_android/core/models/desktop_session_snapshot.dart';
import 'package:hermes_android/core/models/prepared_turn.dart';
import 'package:hermes_android/core/services/active_chat_service.dart';
import 'package:hermes_android/core/services/connection_manager.dart';
import 'package:hermes_android/core/services/connection_diagnostics.dart';
import 'package:hermes_android/core/services/tui_gateway_client.dart';
import 'package:hermes_android/core/services/turn_outbox_store.dart';

class _MemoryOutbox implements TurnOutboxPersistence {
  _MemoryOutbox({this.beforeSave});

  final Future<void> Function(PreparedTurn turn, int attempt)? beforeSave;
  final List<PreparedTurn> writes = [];
  final List<PreparedTurn> deletes = [];

  @override
  Future<void> save(PreparedTurn turn) async {
    await beforeSave?.call(turn, writes.length + 1);
    writes.add(turn);
  }

  @override
  Future<void> delete(PreparedTurn turn) async => deletes.add(turn);
}

class _LegacyGateway implements HermesDesktopGateway {
  final _events = StreamController<TuiGatewayEvent>.broadcast();
  final List<(String, String)> submissions = [];

  @override
  Stream<TuiGatewayEvent> get events => _events.stream;

  @override
  bool get isConnected => true;

  @override
  Future<void> connect() async {}

  @override
  Future<DesktopSessionBinding> resumeSession(
    String storedSessionId, {
    String profile = '',
    List<Map<String, dynamic>> seedMessages = const [],
    String model = '',
  }) async => DesktopSessionBinding(
    runtimeSessionId: 'runtime-legacy',
    storedSessionId: storedSessionId,
    created: false,
  );

  @override
  Future<void> submitPrompt(String runtimeSessionId, String text) async {
    submissions.add((runtimeSessionId, text));
  }

  void emit(String type, {Map<String, dynamic> payload = const {}}) {
    _events.add(
      TuiGatewayEvent(
        type: type,
        sessionId: 'runtime-legacy',
        payload: payload,
      ),
    );
  }

  void emitError(Object error) => _events.addError(error);

  @override
  Future<void> close() => _events.close();

  @override
  Future<void> interrupt(String runtimeSessionId) async {}

  @override
  Future<void> resolveApproval(
    String runtimeSessionId,
    String choice, {
    bool resolveAll = false,
    String? requestId,
  }) async {}

  @override
  Future<void> steer(String runtimeSessionId, String text) async {}
}

class _ModernGateway extends _LegacyGateway
    implements HermesDesktopIdempotentGateway {
  final List<(String, String, String)> idempotentSubmissions = [];
  int statusCalls = 0;
  Object? submissionError;
  bool duplicate = false;
  DesktopTurnState ackState = DesktopTurnState.accepted;
  DesktopTurnStatus? nextStatus;

  @override
  Future<DesktopTurnAck> submitPromptIdempotent(
    String runtimeSessionId,
    String text,
    String clientTurnId,
  ) async {
    idempotentSubmissions.add((runtimeSessionId, text, clientTurnId));
    if (submissionError case final error?) throw error;
    return DesktopTurnAck(
      accepted: true,
      clientTurnId: clientTurnId,
      serverTurnId: 'server-turn-1',
      state: ackState,
      duplicate: duplicate,
    );
  }

  @override
  Future<DesktopTurnStatus> getTurnStatus(
    String sessionId,
    String clientTurnId,
  ) async {
    statusCalls++;
    return nextStatus ??
        DesktopTurnStatus(known: false, clientTurnId: clientTurnId);
  }
}

class _OwnershipGateway extends _ModernGateway
    implements
        HermesDesktopSessionLifecycleGateway,
        HermesDesktopAttachmentGateway {
  _OwnershipGateway({
    required this.resumeRuntimeIds,
    this.idempotentSubmissionErrors = const [],
    this.normalSubmissionErrors = const [],
    this.onResumeExisting,
    this.onIdempotentSubmit,
  });

  final List<String> resumeRuntimeIds;
  final List<TuiGatewayRpcError?> idempotentSubmissionErrors;
  final List<TuiGatewayRpcError?> normalSubmissionErrors;
  final Future<void> Function(int call)? onResumeExisting;
  final Future<void> Function(int call)? onIdempotentSubmit;
  final List<(String, String)> resumes = [];
  final List<(String, String)> imageAttachments = [];
  final List<(String, String)> fileAttachments = [];
  int _resumeIndex = 0;

  @override
  Future<DesktopSessionSnapshot> resumeExisting(
    String storedSessionId, {
    String profile = '',
    bool omitMessages = false,
    bool deferHistory = false,
  }) async {
    resumes.add((storedSessionId, profile));
    final resumeIndex = _resumeIndex;
    _resumeIndex += 1;
    await onResumeExisting?.call(resumes.length);
    final runtimeId =
        resumeRuntimeIds[resumeIndex.clamp(0, resumeRuntimeIds.length - 1)];
    return DesktopSessionSnapshot(
      runtimeSessionId: runtimeId,
      storedSessionId: storedSessionId,
      created: false,
    );
  }

  @override
  Future<DesktopSessionSnapshot> createForFirstSubmit({
    String profile = '',
    List<Map<String, dynamic>> seedMessages = const [],
    String model = '',
  }) => throw StateError('ownership recovery must never create a session');

  @override
  Future<DesktopAttachmentResult> attachImageBytes(
    String runtimeSessionId, {
    required String filename,
    required String contentBase64,
  }) async {
    imageAttachments.add((runtimeSessionId, filename));
    return DesktopAttachmentResult(path: '/remote/$filename');
  }

  @override
  Future<DesktopAttachmentResult> attachFileBytes(
    String runtimeSessionId, {
    required String filename,
    required String mimeType,
    required String contentBase64,
  }) async {
    fileAttachments.add((runtimeSessionId, filename));
    return DesktopAttachmentResult(
      path: '/remote/$filename',
      refText: '@file:.hermes/$filename',
    );
  }

  @override
  Future<void> detachImage(String runtimeSessionId, String path) async {}

  @override
  Future<DesktopTurnAck> submitPromptIdempotent(
    String runtimeSessionId,
    String text,
    String clientTurnId,
  ) async {
    idempotentSubmissions.add((runtimeSessionId, text, clientTurnId));
    await onIdempotentSubmit?.call(idempotentSubmissions.length);
    final attempt = idempotentSubmissions.length - 1;
    if (attempt < idempotentSubmissionErrors.length) {
      final error = idempotentSubmissionErrors[attempt];
      if (error != null) throw error;
    }
    return DesktopTurnAck(
      accepted: true,
      clientTurnId: clientTurnId,
      serverTurnId: 'server-turn-1',
      state: DesktopTurnState.accepted,
      duplicate: false,
    );
  }

  @override
  Future<void> submitPrompt(String runtimeSessionId, String text) async {
    submissions.add((runtimeSessionId, text));
    final attempt = submissions.length - 1;
    if (attempt < normalSubmissionErrors.length) {
      final error = normalSubmissionErrors[attempt];
      if (error != null) throw error;
    }
  }
}

({ActiveChat chat, ActiveTurnDelivery delivery, _MemoryOutbox store}) _fixture(
  HermesDesktopGateway gateway, {
  Future<bool> Function()? capability,
  String profile = '',
  List<AttachmentDraft> attachments = const [],
  _MemoryOutbox? outbox,
}) {
  final api = ApiClient(
    baseUrl: 'https://example.invalid',
    apiKey: 'test-only',
    httpClient: MockClient((_) async => http.Response('unused', 500)),
  );
  final chat = ActiveChat(
    connection: SavedConnection(
      id: 'conn-modern',
      label: 'Modern',
      host: 'example.invalid',
      port: 443,
      apiKey: 'test-only',
      useHttps: true,
    ),
    sessionId: 'session-modern',
    sessionTitle: 'Modern',
    notifications: null,
    onTerminal: () {},
    api: api,
    desktopGateway: gateway,
    turnIdempotencyCapability: capability,
  );
  final now = DateTime.now().millisecondsSinceEpoch;
  final store = outbox ?? _MemoryOutbox();
  return (
    chat: chat,
    delivery: ActiveTurnDelivery(
      prepared: PreparedTurn(
        connectionId: 'conn-modern',
        sessionId: 'session-modern',
        clientTurnId: 'client-turn-1',
        createdAtMs: now,
        updatedAtMs: now,
        text: 'mensaje moderno',
        attachments: attachments,
        model: 'hermes-agent',
        profile: profile,
      ),
      store: store,
    ),
    store: store,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'sin capability usa prompt heredado exacto y no consulta status',
    () async {
      final gateway = _LegacyGateway();
      final api = ApiClient(
        baseUrl: 'https://example.invalid',
        apiKey: 'test-only',
        httpClient: MockClient((_) async => http.Response('unused', 500)),
      );
      final chat = ActiveChat(
        connection: SavedConnection(
          id: 'conn-legacy',
          label: 'Legacy',
          host: 'example.invalid',
          port: 443,
          apiKey: 'test-only',
          useHttps: true,
        ),
        sessionId: 'session-legacy',
        sessionTitle: 'Legacy',
        notifications: null,
        onTerminal: () {},
        api: api,
        desktopGateway: gateway,
      );
      addTearDown(chat.dispose);
      final now = DateTime.now().millisecondsSinceEpoch;
      final delivery = ActiveTurnDelivery(
        prepared: PreparedTurn(
          connectionId: 'conn-legacy',
          sessionId: 'session-legacy',
          clientTurnId: 'client-turn-must-stay-local',
          createdAtMs: now,
          updatedAtMs: now,
          text: 'mensaje heredado',
          attachments: const [],
          model: 'hermes-agent',
          profile: '',
        ),
        store: _MemoryOutbox(),
      );

      final accepted = await chat.send(
        fullText: 'mensaje heredado',
        model: 'hermes-agent',
        history: const [],
        delivery: delivery,
      );

      expect(accepted, isTrue);
      expect(gateway.submissions, [('runtime-legacy', 'mensaje heredado')]);
      expect(gateway.submissions.single.$2, isNot(contains('client-turn')));
      expect(delivery.current.state, PreparedTurnState.running);
    },
  );

  test('ACK idempotente valida eco, estado e identidad opaca', () {
    final ack = DesktopTurnAck.fromJson(const {
      'accepted': true,
      'client_turn_id': 'client-turn-1',
      'server_turn_id': 'server-opaque',
      'state': 'accepted',
      'duplicate': false,
    }, expectedClientTurnId: 'client-turn-1');

    expect(ack.accepted, isTrue);
    expect(ack.serverTurnId, 'server-opaque');
    expect(ack.state, DesktopTurnState.accepted);
    expect(ack.duplicate, isFalse);
  });

  test('ACK idempotente rechaza eco o estado que rompen contrato', () {
    expect(
      () => DesktopTurnAck.fromJson(const {
        'accepted': true,
        'client_turn_id': 'otro',
        'state': 'accepted',
      }, expectedClientTurnId: 'client-turn-1'),
      throwsA(isA<TuiGatewayRpcError>()),
    );
    expect(
      () => DesktopTurnAck.fromJson(const {
        'accepted': true,
        'client_turn_id': 'client-turn-1',
        'state': 'inventado',
      }, expectedClientTurnId: 'client-turn-1'),
      throwsA(isA<TuiGatewayRpcError>()),
    );
  });

  test('status unknown es tipado y no equivale a permiso para reenviar', () {
    final status = DesktopTurnStatus.fromJson(const {
      'known': false,
      'client_turn_id': 'client-turn-1',
    }, expectedClientTurnId: 'client-turn-1');

    expect(status.known, isFalse);
    expect(status.state, isNull);
    expect(status.serverTurnId, isNull);
  });

  test(
    'capability autenticada se deriva y persiste sin probe mutante',
    () async {
      final caps = ServerCapabilities.tryParse(
        jsonEncode({
          'object': 'hermes.api_server.capabilities',
          'features': {'turn_idempotency_v1': true},
          'endpoints': <String, Object?>{},
        }),
      );
      final diagnostics = ConnectionDiagnostics(
        httpClient: MockClient((_) async => http.Response('unused', 500)),
      );
      addTearDown(diagnostics.close);

      final matrix = diagnostics.buildMatrix(
        const [],
        const [],
        null,
        serverCaps: caps,
      );

      expect(matrix.turnIdempotency, CapState.yes);
      expect(matrix.isServerSourced('turnIdempotency'), isTrue);
      SharedPreferences.setMockInitialValues({
        'capabilities_conn-modern': jsonEncode(matrix.toJson()),
      });
      expect(
        await ConnectionManager.isTurnIdempotencySupported('conn-modern'),
        isTrue,
      );
    },
  );

  test('capability ausente o corrupta conserva contrato heredado', () async {
    SharedPreferences.setMockInitialValues({
      'capabilities_corrupt': '{no-json',
    });

    expect(
      await ConnectionManager.isTurnIdempotencySupported('missing'),
      isFalse,
    );
    expect(
      await ConnectionManager.isTurnIdempotencySupported('corrupt'),
      isFalse,
    );
  });

  test(
    'capability solo habilita idempotencia si es reciente y server-sourced',
    () async {
      final now = DateTime.now().millisecondsSinceEpoch;
      SharedPreferences.setMockInitialValues({
        'capabilities_legacy': jsonEncode({'turn_idempotency': 'yes'}),
        'capabilities_inferred': jsonEncode({
          'turn_idempotency': 'yes',
          'server_sourced': <String>[],
          'checked_at_ms': now,
        }),
        'capabilities_stale': jsonEncode({
          'turn_idempotency': 'yes',
          'server_sourced': ['turnIdempotency'],
          'checked_at_ms': now - const Duration(hours: 25).inMilliseconds,
        }),
        'capabilities_future': jsonEncode({
          'turn_idempotency': 'yes',
          'server_sourced': ['turnIdempotency'],
          'checked_at_ms': now + const Duration(minutes: 5).inMilliseconds,
        }),
        'capabilities_recent': jsonEncode({
          'turn_idempotency': 'yes',
          'server_sourced': ['turnIdempotency'],
          'checked_at_ms': now - const Duration(minutes: 5).inMilliseconds,
        }),
      });

      expect(
        await ConnectionManager.isTurnIdempotencySupported('legacy'),
        isFalse,
      );
      expect(
        await ConnectionManager.isTurnIdempotencySupported('inferred'),
        isFalse,
      );
      expect(
        await ConnectionManager.isTurnIdempotencySupported('stale'),
        isFalse,
      );
      expect(
        await ConnectionManager.isTurnIdempotencySupported('future'),
        isFalse,
      );
      expect(
        await ConnectionManager.isTurnIdempotencySupported('recent'),
        isTrue,
      );
    },
  );

  test(
    'capability positiva envía client_turn_id sin tocar camino base',
    () async {
      final gateway = _ModernGateway();
      final fixture = _fixture(gateway, capability: () async => true);
      addTearDown(fixture.chat.dispose);

      final accepted = await fixture.chat.send(
        fullText: 'mensaje moderno',
        model: 'hermes-agent',
        history: const [],
        delivery: fixture.delivery,
      );

      expect(accepted, isTrue);
      expect(gateway.submissions, isEmpty);
      expect(gateway.idempotentSubmissions, [
        ('runtime-legacy', 'mensaje moderno', 'client-turn-1'),
      ]);
      expect(gateway.statusCalls, 0);
    },
  );

  test('el fence no permite limpiar un runtime que ya fue reemplazado', () {
    expect(
      activeChatRejectedRuntimeStillCurrent(
        expectedSessionEpoch: 4,
        currentSessionEpoch: 4,
        expectedBindEpoch: 8,
        currentBindEpoch: 9,
        rejectedRuntimeId: 'runtime-old',
        currentRuntimeId: 'runtime-new',
      ),
      isFalse,
    );
    expect(
      activeChatRejectedRuntimeStillCurrent(
        expectedSessionEpoch: 4,
        currentSessionEpoch: 4,
        expectedBindEpoch: 8,
        currentBindEpoch: 8,
        rejectedRuntimeId: 'runtime-old',
        currentRuntimeId: 'runtime-old',
      ),
      isTrue,
    );
  });

  test('el rechazo no resucita tombstones de adjuntos', () async {
    final fixture = _fixture(
      _ModernGateway(),
      attachments: const [
        AttachmentDraft(
          localId: 'removed-image',
          type: AttachmentType.image,
          name: 'removed.png',
          mimeType: 'image/png',
          sizeBytes: 3,
          localPath: '/tmp/removed.png',
          uploadState: AttachmentUploadState.removed,
          remoteRef: '/remote/removed.png',
          remoteSessionId: 'runtime-old',
          remoteTransport: AttachmentRemoteTransport.desktop,
        ),
      ],
    );
    addTearDown(fixture.chat.dispose);

    await fixture.delivery.markRejectedBeforeAcceptance(
      invalidateRemoteSessionId: 'runtime-old',
      invalidateTransport: AttachmentRemoteTransport.desktop,
    );

    expect(
      fixture.delivery.current.attachments.single.uploadState,
      AttachmentUploadState.removed,
    );
    expect(
      fixture.delivery.current.state,
      PreparedTurnState.failedBeforeAcceptance,
    );
  });

  test(
    'SESSION_NOT_OWNED reanuda el durable y reenvía una vez al runtime dueño',
    () async {
      const rejection = TuiGatewayRpcError(
        'prompt.submit',
        'private ownership detail',
        code: 4090,
        data: {'reason': 'SESSION_NOT_OWNED'},
      );
      final gateway = _OwnershipGateway(
        resumeRuntimeIds: ['runtime-old', 'runtime-owner'],
        idempotentSubmissionErrors: [rejection, null],
      );
      final fixture = _fixture(
        gateway,
        capability: () async => true,
        profile: 'owner-profile',
      );
      addTearDown(fixture.chat.dispose);

      await fixture.chat.loadMessages(profile: 'owner-profile');
      expect(fixture.chat.desktopRuntimeSessionId, 'runtime-old');

      final accepted = await fixture.chat.send(
        fullText: 'mensaje moderno',
        model: 'hermes-agent',
        history: const [],
        profile: 'owner-profile',
        delivery: fixture.delivery,
      );

      expect(accepted, isTrue);
      expect(gateway.resumes, [
        ('session-modern', 'owner-profile'),
        ('session-modern', 'owner-profile'),
      ]);
      expect(gateway.idempotentSubmissions, [
        ('runtime-old', 'mensaje moderno', 'client-turn-1'),
        ('runtime-owner', 'mensaje moderno', 'client-turn-1'),
      ]);
      expect(fixture.chat.desktopRuntimeSessionId, 'runtime-owner');
      expect(fixture.chat.state, ChatPipelineState.waiting);
      expect(fixture.chat.turnIdempotencyInvalid, isFalse);
      expect(fixture.delivery.current.state, PreparedTurnState.running);
      expect(
        fixture.store.writes.map((turn) => turn.state),
        containsAllInOrder(const [
          PreparedTurnState.failedBeforeAcceptance,
          PreparedTurnState.submitting,
          PreparedTurnState.accepted,
          PreparedTurnState.running,
        ]),
      );
      expect(
        fixture.chat.messages.where((message) => message['role'] == 'user'),
        hasLength(1),
      );
      expect(
        fixture.chat.messages.where(
          (message) =>
              message['role'] == 'assistant' && message['_pipeline'] == true,
        ),
        hasLength(1),
      );
      expect(
        fixture.chat.messages.where(
          (message) => message['role'] == 'assistant_error',
        ),
        isEmpty,
      );
    },
  );

  test(
    '4001 session not found reanuda el durable y reintenta una vez',
    () async {
      const rejection = TuiGatewayRpcError(
        'prompt.submit',
        'session not found',
        code: 4001,
      );
      final gateway = _OwnershipGateway(
        resumeRuntimeIds: ['runtime-stale', 'runtime-resumed'],
        idempotentSubmissionErrors: [rejection, null],
      );
      final fixture = _fixture(
        gateway,
        capability: () async => true,
        profile: 'owner-profile',
      );
      addTearDown(fixture.chat.dispose);

      await fixture.chat.loadMessages(profile: 'owner-profile');
      final accepted = await fixture.chat.send(
        fullText: 'mensaje moderno',
        model: 'hermes-agent',
        history: const [],
        profile: 'owner-profile',
        delivery: fixture.delivery,
      );

      expect(accepted, isTrue);
      expect(gateway.resumes, [
        ('session-modern', 'owner-profile'),
        ('session-modern', 'owner-profile'),
      ]);
      expect(gateway.idempotentSubmissions, [
        ('runtime-stale', 'mensaje moderno', 'client-turn-1'),
        ('runtime-resumed', 'mensaje moderno', 'client-turn-1'),
      ]);
      expect(fixture.chat.desktopRuntimeSessionId, 'runtime-resumed');
      expect(fixture.delivery.current.state, PreparedTurnState.running);
    },
  );

  test('4001 reintenta tras confirmar incluso el mismo runtime', () async {
    const rejection = TuiGatewayRpcError(
      'prompt.submit',
      'session not found',
      code: 4001,
    );
    final gateway = _OwnershipGateway(
      resumeRuntimeIds: ['runtime-stale', 'runtime-stale'],
      idempotentSubmissionErrors: [rejection],
    );
    final fixture = _fixture(gateway, capability: () async => true);
    addTearDown(fixture.chat.dispose);

    await fixture.chat.loadMessages();
    final accepted = await fixture.chat.send(
      fullText: 'mensaje moderno',
      model: 'hermes-agent',
      history: const [],
      delivery: fixture.delivery,
    );

    expect(accepted, isTrue);
    expect(gateway.resumes, hasLength(2));
    expect(gateway.idempotentSubmissions, [
      ('runtime-stale', 'mensaje moderno', 'client-turn-1'),
      ('runtime-stale', 'mensaje moderno', 'client-turn-1'),
    ]);
    expect(fixture.chat.turnIdempotencyInvalid, isFalse);
    expect(fixture.delivery.current.state, PreparedTurnState.running);
  });

  test('un segundo 4001 termina sin bucle', () async {
    const rejection = TuiGatewayRpcError(
      'prompt.submit',
      'session not found',
      code: 4001,
    );
    final gateway = _OwnershipGateway(
      resumeRuntimeIds: ['runtime-stale', 'runtime-resumed'],
      idempotentSubmissionErrors: [rejection, rejection],
    );
    final fixture = _fixture(gateway, capability: () async => true);
    addTearDown(fixture.chat.dispose);

    await fixture.chat.loadMessages();
    final accepted = await fixture.chat.send(
      fullText: 'mensaje moderno',
      model: 'hermes-agent',
      history: const [],
      delivery: fixture.delivery,
    );

    expect(accepted, isFalse);
    expect(gateway.resumes, hasLength(2));
    expect(gateway.idempotentSubmissions, [
      ('runtime-stale', 'mensaje moderno', 'client-turn-1'),
      ('runtime-resumed', 'mensaje moderno', 'client-turn-1'),
    ]);
    expect(
      fixture.delivery.current.state,
      PreparedTurnState.failedBeforeAcceptance,
    );
  });

  test('4001 de otro método y otros códigos no recuperan runtime', () async {
    const cases = [
      (
        label: 'otro método',
        error: TuiGatewayRpcError(
          'session.resume',
          'session not found',
          code: 4001,
        ),
      ),
      (
        label: 'otro código',
        error: TuiGatewayRpcError(
          'prompt.submit',
          'session not found',
          code: 4007,
        ),
      ),
    ];
    for (final testCase in cases) {
      final gateway = _OwnershipGateway(
        resumeRuntimeIds: ['runtime-stale', 'runtime-resumed'],
        idempotentSubmissionErrors: [testCase.error],
      );
      final fixture = _fixture(gateway, capability: () async => true);
      addTearDown(fixture.chat.dispose);

      await fixture.chat.loadMessages();
      final accepted = await fixture.chat.send(
        fullText: 'mensaje moderno',
        model: 'hermes-agent',
        history: const [],
        delivery: fixture.delivery,
      );

      expect(accepted, isFalse, reason: testCase.label);
      expect(gateway.resumes, hasLength(1), reason: testCase.label);
      expect(
        gateway.idempotentSubmissions,
        hasLength(1),
        reason: testCase.label,
      );
    }
  });

  test(
    'persiste el rechazo antes de esperar la reanudación y luego reintenta',
    () async {
      const rejection = TuiGatewayRpcError(
        'prompt.submit',
        'private ownership detail',
        code: 4090,
        data: {'reason': 'SESSION_NOT_OWNED'},
      );
      final recoveryStarted = Completer<void>();
      final allowRecovery = Completer<void>();
      final gateway = _OwnershipGateway(
        resumeRuntimeIds: const ['runtime-stale', 'runtime-owner'],
        idempotentSubmissionErrors: const [rejection, null],
        onResumeExisting: (call) async {
          if (call == 2) {
            recoveryStarted.complete();
            await allowRecovery.future;
          }
        },
      );
      final fixture = _fixture(
        gateway,
        capability: () async => true,
        profile: 'owner-profile',
      );
      addTearDown(() async {
        if (!allowRecovery.isCompleted) allowRecovery.complete();
        fixture.chat.dispose();
      });

      await fixture.chat.loadMessages(profile: 'owner-profile');
      expect(fixture.chat.desktopRuntimeSessionId, 'runtime-stale');

      final sendFuture = fixture.chat.send(
        fullText: 'mensaje moderno',
        model: 'hermes-agent',
        history: const [],
        profile: 'owner-profile',
        delivery: fixture.delivery,
      );
      await recoveryStarted.future.timeout(
        const Duration(seconds: 5),
        onTimeout: () => throw StateError(
          'recovery did not start: resumes=${gateway.resumes.length}, '
          'submits=${gateway.idempotentSubmissions.length}',
        ),
      );

      final stateWhileRecoveryWasBlocked = fixture.delivery.current.state;

      allowRecovery.complete();
      final accepted = await sendFuture.timeout(
        const Duration(seconds: 5),
        onTimeout: () => throw StateError(
          'send did not finish: resumes=${gateway.resumes.length}, '
          'submits=${gateway.idempotentSubmissions.length}',
        ),
      );

      expect(
        stateWhileRecoveryWasBlocked,
        PreparedTurnState.failedBeforeAcceptance,
      );
      expect(accepted, isTrue);
      expect(gateway.idempotentSubmissions, hasLength(2));
      expect(fixture.delivery.current.state, PreparedTurnState.running);
    },
  );

  test(
    'el retry reconciliado no cruza un rebind durante la persistencia',
    () async {
      const rejection = TuiGatewayRpcError(
        'prompt.submit',
        'private ownership detail',
        code: 4090,
        data: {'reason': 'SESSION_NOT_OWNED'},
      );
      final retryPersistenceStarted = Completer<void>();
      final allowRetryPersistence = Completer<void>();
      var submittingSaves = 0;
      final outbox = _MemoryOutbox(
        beforeSave: (turn, _) async {
          if (turn.state != PreparedTurnState.submitting) return;
          submittingSaves += 1;
          if (submittingSaves == 2) {
            retryPersistenceStarted.complete();
            await allowRetryPersistence.future;
          }
        },
      );
      final gateway = _OwnershipGateway(
        resumeRuntimeIds: const [
          'runtime-stale',
          'runtime-owner',
          'runtime-rebound-again',
        ],
        idempotentSubmissionErrors: const [rejection, null],
      );
      final fixture = _fixture(
        gateway,
        capability: () async => true,
        profile: 'owner-profile',
        outbox: outbox,
      );
      addTearDown(() async {
        if (!allowRetryPersistence.isCompleted) {
          allowRetryPersistence.complete();
        }
        fixture.chat.dispose();
      });

      await fixture.chat.loadMessages(profile: 'owner-profile');
      final sendFuture = fixture.chat.send(
        fullText: 'mensaje moderno',
        model: 'hermes-agent',
        history: const [],
        profile: 'owner-profile',
        delivery: fixture.delivery,
      );
      await retryPersistenceStarted.future.timeout(const Duration(seconds: 5));
      await fixture.chat.loadMessages(profile: 'owner-profile');
      expect(fixture.chat.desktopRuntimeSessionId, 'runtime-rebound-again');

      allowRetryPersistence.complete();
      final accepted = await sendFuture.timeout(const Duration(seconds: 5));

      expect(accepted, isFalse);
      expect(gateway.idempotentSubmissions, [
        ('runtime-stale', 'mensaje moderno', 'client-turn-1'),
      ]);
      expect(fixture.chat.desktopRuntimeSessionId, 'runtime-rebound-again');
      expect(
        fixture.delivery.current.state,
        PreparedTurnState.failedBeforeAcceptance,
      );
    },
  );

  test(
    'un fallo no retira el runtime adoptado mientras persiste el rechazo',
    () async {
      const rejection = TuiGatewayRpcError(
        'prompt.submit',
        'capacity detail',
        code: 4090,
        data: {'reason': 'MAX_CONCURRENT_SESSIONS'},
      );
      final rejectionPersistenceStarted = Completer<void>();
      final allowRejectionPersistence = Completer<void>();
      final outbox = _MemoryOutbox(
        beforeSave: (turn, _) async {
          if (turn.state != PreparedTurnState.failedBeforeAcceptance ||
              rejectionPersistenceStarted.isCompleted) {
            return;
          }
          rejectionPersistenceStarted.complete();
          await allowRejectionPersistence.future;
        },
      );
      final gateway = _OwnershipGateway(
        resumeRuntimeIds: const ['runtime-stale', 'runtime-rebound'],
        idempotentSubmissionErrors: const [rejection],
      );
      final fixture = _fixture(
        gateway,
        capability: () async => true,
        profile: 'owner-profile',
        outbox: outbox,
      );
      addTearDown(() async {
        if (!allowRejectionPersistence.isCompleted) {
          allowRejectionPersistence.complete();
        }
        fixture.chat.dispose();
      });

      await fixture.chat.loadMessages(profile: 'owner-profile');
      final sendFuture = fixture.chat.send(
        fullText: 'mensaje moderno',
        model: 'hermes-agent',
        history: const [],
        profile: 'owner-profile',
        delivery: fixture.delivery,
      );
      await rejectionPersistenceStarted.future.timeout(
        const Duration(seconds: 5),
      );
      await fixture.chat.loadMessages(profile: 'owner-profile');
      expect(fixture.chat.desktopRuntimeSessionId, 'runtime-rebound');

      allowRejectionPersistence.complete();
      final accepted = await sendFuture.timeout(const Duration(seconds: 5));

      expect(accepted, isFalse);
      expect(fixture.chat.desktopRuntimeSessionId, 'runtime-rebound');
      expect(gateway.idempotentSubmissions, [
        ('runtime-stale', 'mensaje moderno', 'client-turn-1'),
      ]);
    },
  );

  test(
    'un fallo tardío no retira un rebind que reutiliza el mismo runtime',
    () async {
      const rejection = TuiGatewayRpcError(
        'prompt.submit',
        'private capacity detail',
        code: 4090,
        data: {'reason': 'MAX_CONCURRENT_SESSIONS'},
      );
      final submitStarted = Completer<void>();
      final allowSubmitFailure = Completer<void>();
      final gateway = _OwnershipGateway(
        resumeRuntimeIds: ['runtime-same', 'runtime-same'],
        idempotentSubmissionErrors: const [rejection],
        onIdempotentSubmit: (call) async {
          if (call != 1) return;
          submitStarted.complete();
          await allowSubmitFailure.future;
        },
      );
      final fixture = _fixture(
        gateway,
        capability: () async => true,
        profile: 'owner-profile',
      );
      addTearDown(() {
        if (!allowSubmitFailure.isCompleted) allowSubmitFailure.complete();
        fixture.chat.dispose();
      });

      await fixture.chat.loadMessages(profile: 'owner-profile');
      final send = fixture.chat.send(
        fullText: 'hola',
        model: 'model',
        history: const [],
        profile: 'owner-profile',
        delivery: fixture.delivery,
      );
      await submitStarted.future.timeout(const Duration(seconds: 5));

      gateway.emitError(StateError('simulated disconnect'));
      await Future<void>.delayed(Duration.zero);
      expect(fixture.chat.desktopRuntimeSessionId, isNull);
      await fixture.chat.loadMessages(profile: 'owner-profile');
      expect(fixture.chat.desktopRuntimeSessionId, 'runtime-same');

      allowSubmitFailure.complete();
      expect(await send.timeout(const Duration(seconds: 5)), isFalse);
      expect(fixture.chat.desktopRuntimeSessionId, 'runtime-same');
      expect(gateway.idempotentSubmissions, hasLength(1));
    },
  );

  test(
    'rechazo recuperable no cruza un rebind que reutiliza el runtime',
    () async {
      const rejection = TuiGatewayRpcError(
        'prompt.submit',
        'private ownership detail',
        code: 4090,
        data: {'reason': 'SESSION_NOT_OWNED'},
      );
      final rejectionPersistenceStarted = Completer<void>();
      final allowRejectionPersistence = Completer<void>();
      final outbox = _MemoryOutbox(
        beforeSave: (turn, _) async {
          if (turn.state != PreparedTurnState.failedBeforeAcceptance ||
              rejectionPersistenceStarted.isCompleted) {
            return;
          }
          rejectionPersistenceStarted.complete();
          await allowRejectionPersistence.future;
        },
      );
      final gateway = _OwnershipGateway(
        resumeRuntimeIds: const [
          'runtime-same',
          'runtime-same',
          'runtime-same',
        ],
        idempotentSubmissionErrors: const [rejection, null],
      );
      final fixture = _fixture(
        gateway,
        capability: () async => true,
        profile: 'owner-profile',
        outbox: outbox,
      );
      addTearDown(() {
        if (!allowRejectionPersistence.isCompleted) {
          allowRejectionPersistence.complete();
        }
        fixture.chat.dispose();
      });

      await fixture.chat.loadMessages(profile: 'owner-profile');
      final send = fixture.chat.send(
        fullText: 'hola',
        model: 'model',
        history: const [],
        profile: 'owner-profile',
        delivery: fixture.delivery,
      );
      await rejectionPersistenceStarted.future.timeout(
        const Duration(seconds: 5),
      );

      gateway.emitError(StateError('simulated disconnect'));
      await Future<void>.delayed(Duration.zero);
      await fixture.chat.loadMessages(profile: 'owner-profile');
      expect(fixture.chat.desktopRuntimeSessionId, 'runtime-same');
      final resumesBeforeAllowingRejectedTurn = gateway.resumes.length;

      allowRejectionPersistence.complete();
      expect(await send.timeout(const Duration(seconds: 5)), isFalse);
      expect(gateway.idempotentSubmissions, [
        ('runtime-same', 'hola', 'client-turn-1'),
      ]);
      expect(gateway.resumes, hasLength(resumesBeforeAllowingRejectedTurn));
    },
  );

  test(
    '4001 tras image.attach_bytes invalida la asociación remota sin reenviar',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'hermes-turn-ownership-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final image = File('${directory.path}/evidence.png');
      await image.writeAsBytes(const [1, 2, 3]);
      const rejection = TuiGatewayRpcError(
        'prompt.submit',
        'session not found',
        code: 4001,
      );
      final gateway = _OwnershipGateway(
        resumeRuntimeIds: ['runtime-stale', 'runtime-resumed'],
        idempotentSubmissionErrors: [rejection, null],
      );
      final fixture = _fixture(
        gateway,
        capability: () async => true,
        attachments: [
          AttachmentDraft(
            localId: 'image-evidence',
            type: AttachmentType.image,
            name: 'evidence.png',
            mimeType: 'image/png',
            sizeBytes: 3,
            localPath: image.path,
          ),
        ],
      );
      addTearDown(fixture.chat.dispose);

      await fixture.chat.loadMessages();
      final accepted = await fixture.chat.send(
        fullText: 'mensaje moderno',
        model: 'hermes-agent',
        history: const [],
        delivery: fixture.delivery,
      );

      expect(accepted, isFalse);
      expect(gateway.imageAttachments, [('runtime-stale', 'evidence.png')]);
      expect(gateway.resumes, [('session-modern', 'default')]);
      expect(gateway.idempotentSubmissions, [
        ('runtime-stale', 'mensaje moderno', 'client-turn-1'),
      ]);
      expect(
        fixture.delivery.current.state,
        PreparedTurnState.failedBeforeAcceptance,
      );
      expect(
        fixture.delivery.current.attachments.single.uploadState,
        AttachmentUploadState.pending,
      );
      expect(
        fixture.delivery.current.attachments.single.remoteSessionId,
        isNull,
      );
      expect(fixture.delivery.current.attachments.single.remoteRef, isNull);
      final attachedWriteIndex = fixture.store.writes.indexWhere(
        (turn) =>
            turn.attachments.single.uploadState ==
            AttachmentUploadState.attached,
      );
      expect(attachedWriteIndex, isNonNegative);
      expect(
        fixture.store.writes
            .skip(attachedWriteIndex + 1)
            .where(
              (turn) =>
                  turn.state == PreparedTurnState.submitting &&
                  turn.attachments.single.uploadState ==
                      AttachmentUploadState.pending,
            ),
        isEmpty,
        reason: 'el rechazo y la invalidación deben persistirse atómicamente',
      );
    },
  );

  test('SESSION_NOT_OWNED también recupera el submit normal', () async {
    const rejection = TuiGatewayRpcError(
      'prompt.submit',
      'private ownership detail',
      code: 4090,
      data: {'reason': 'SESSION_NOT_OWNED'},
    );
    final gateway = _OwnershipGateway(
      resumeRuntimeIds: ['runtime-old', 'runtime-owner'],
      normalSubmissionErrors: [rejection, null],
    );
    final fixture = _fixture(gateway, capability: () async => false);
    addTearDown(fixture.chat.dispose);

    await fixture.chat.loadMessages();
    final accepted = await fixture.chat.send(
      fullText: 'mensaje moderno',
      model: 'hermes-agent',
      history: const [],
      delivery: fixture.delivery,
    );

    expect(accepted, isTrue);
    expect(gateway.resumes, [
      ('session-modern', 'default'),
      ('session-modern', 'default'),
    ]);
    expect(gateway.submissions, [
      ('runtime-old', 'mensaje moderno'),
      ('runtime-owner', 'mensaje moderno'),
    ]);
    expect(gateway.idempotentSubmissions, isEmpty);
    expect(fixture.chat.desktopRuntimeSessionId, 'runtime-owner');
    expect(fixture.delivery.current.state, PreparedTurnState.running);
  });

  test('SESSION_NOT_OWNED no reintenta contra el mismo runtime', () async {
    const rejection = TuiGatewayRpcError(
      'prompt.submit',
      'private ownership detail',
      code: 4090,
      data: {'reason': 'SESSION_NOT_OWNED'},
    );
    final gateway = _OwnershipGateway(
      resumeRuntimeIds: ['runtime-old', 'runtime-old'],
      idempotentSubmissionErrors: [rejection],
    );
    final fixture = _fixture(gateway, capability: () async => true);
    addTearDown(fixture.chat.dispose);

    await fixture.chat.loadMessages();
    final accepted = await fixture.chat.send(
      fullText: 'mensaje moderno',
      model: 'hermes-agent',
      history: const [],
      delivery: fixture.delivery,
    );

    expect(accepted, isFalse);
    expect(gateway.resumes, hasLength(2));
    expect(gateway.idempotentSubmissions, [
      ('runtime-old', 'mensaje moderno', 'client-turn-1'),
    ]);
    expect(fixture.chat.state, ChatPipelineState.failed);
    expect(
      fixture.delivery.current.state,
      PreparedTurnState.failedBeforeAcceptance,
    );
  });

  test('un segundo SESSION_NOT_OWNED termina sin bucle', () async {
    const rejection = TuiGatewayRpcError(
      'prompt.submit',
      'private ownership detail',
      code: 4090,
      data: {'reason': 'SESSION_NOT_OWNED'},
    );
    final gateway = _OwnershipGateway(
      resumeRuntimeIds: ['runtime-old', 'runtime-owner'],
      idempotentSubmissionErrors: [rejection, rejection],
    );
    final fixture = _fixture(gateway, capability: () async => true);
    addTearDown(fixture.chat.dispose);

    await fixture.chat.loadMessages();
    final accepted = await fixture.chat.send(
      fullText: 'mensaje moderno',
      model: 'hermes-agent',
      history: const [],
      delivery: fixture.delivery,
    );

    expect(accepted, isFalse);
    expect(gateway.resumes, hasLength(2));
    expect(gateway.idempotentSubmissions, [
      ('runtime-old', 'mensaje moderno', 'client-turn-1'),
      ('runtime-owner', 'mensaje moderno', 'client-turn-1'),
    ]);
    expect(fixture.chat.state, ChatPipelineState.failed);
    expect(
      fixture.delivery.current.state,
      PreparedTurnState.failedBeforeAcceptance,
    );
    expect(
      fixture.chat.messages.where((message) => message['role'] == 'user'),
      hasLength(1),
    );
    expect(
      fixture.chat.messages.singleWhere(
        (message) => message['role'] == 'assistant_error',
      )['content'],
      'Esta conversación está abierta en otra ventana o dispositivo. '
      'Ciérrala allí y vuelve a intentarlo.',
    );
  });

  test('otros reasons 4090 no recuperan ownership', () async {
    for (final reason in const [
      'MAX_CONCURRENT_SESSIONS',
      'SESSION_COORDINATION_UNAVAILABLE',
      'UNKNOWN_COORDINATION_REASON',
    ]) {
      final gateway = _OwnershipGateway(
        resumeRuntimeIds: ['runtime-old', 'runtime-owner'],
        idempotentSubmissionErrors: [
          TuiGatewayRpcError(
            'prompt.submit',
            'private coordination detail',
            code: 4090,
            data: {'reason': reason},
          ),
        ],
      );
      final fixture = _fixture(gateway, capability: () async => true);
      addTearDown(fixture.chat.dispose);

      await fixture.chat.loadMessages();
      final accepted = await fixture.chat.send(
        fullText: 'mensaje moderno',
        model: 'hermes-agent',
        history: const [],
        delivery: fixture.delivery,
      );

      expect(accepted, isFalse, reason: reason);
      expect(gateway.resumes, hasLength(1), reason: reason);
      expect(gateway.idempotentSubmissions, hasLength(1), reason: reason);
      expect(
        fixture.delivery.current.state,
        reason == 'UNKNOWN_COORDINATION_REASON'
            ? PreparedTurnState.ambiguous
            : PreparedTurnState.failedBeforeAcceptance,
        reason: reason,
      );
    }
  });

  test('un error ambiguo de prompt.submit no recupera ownership', () async {
    const ambiguous = TuiGatewayRpcError(
      'prompt.submit',
      'Timeout waiting for JSON-RPC response',
      data: {'reason': 'SESSION_NOT_OWNED'},
    );
    final gateway = _OwnershipGateway(
      resumeRuntimeIds: ['runtime-old', 'runtime-owner'],
      idempotentSubmissionErrors: [ambiguous],
    );
    final fixture = _fixture(gateway, capability: () async => true);
    addTearDown(fixture.chat.dispose);

    await fixture.chat.loadMessages();
    final accepted = await fixture.chat.send(
      fullText: 'mensaje moderno',
      model: 'hermes-agent',
      history: const [],
      delivery: fixture.delivery,
    );

    expect(accepted, isFalse);
    expect(gateway.resumes, hasLength(1));
    expect(gateway.idempotentSubmissions, hasLength(1));
    expect(fixture.delivery.current.state, PreparedTurnState.ambiguous);
  });

  test('duplicate=true conserva una sola entrega aceptada', () async {
    final gateway = _ModernGateway()..duplicate = true;
    final fixture = _fixture(gateway, capability: () async => true);
    addTearDown(fixture.chat.dispose);

    final accepted = await fixture.chat.send(
      fullText: 'mensaje moderno',
      model: 'hermes-agent',
      history: const [],
      delivery: fixture.delivery,
    );

    expect(accepted, isTrue);
    expect(gateway.idempotentSubmissions, hasLength(1));
    expect(gateway.submissions, isEmpty);
    expect(fixture.delivery.current.state, PreparedTurnState.running);
  });

  test('duplicate terminal limpia evidencia sin esperar otro evento', () async {
    final gateway = _ModernGateway()
      ..duplicate = true
      ..ackState = DesktopTurnState.terminal;
    final fixture = _fixture(gateway, capability: () async => true);
    addTearDown(fixture.chat.dispose);

    final accepted = await fixture.chat.send(
      fullText: 'mensaje moderno',
      model: 'hermes-agent',
      history: const [],
      delivery: fixture.delivery,
    );

    expect(accepted, isTrue);
    expect(gateway.idempotentSubmissions, hasLength(1));
    expect(fixture.delivery.current.state, PreparedTurnState.terminal);
    expect(fixture.store.deletes, hasLength(1));
    expect(fixture.chat.activeTurnDelivery, isNull);
  });

  test('capability obsoleta con socket viejo conserva prompt base', () async {
    final gateway = _LegacyGateway();
    final fixture = _fixture(gateway, capability: () async => true);
    addTearDown(fixture.chat.dispose);

    final accepted = await fixture.chat.send(
      fullText: 'mensaje moderno',
      model: 'hermes-agent',
      history: const [],
      delivery: fixture.delivery,
    );

    expect(accepted, isTrue);
    expect(gateway.submissions, [('runtime-legacy', 'mensaje moderno')]);
    expect(fixture.delivery.current.state, PreparedTurnState.running);
  });

  test('method-not-found moderno invalida capability sin fallback', () async {
    final gateway = _ModernGateway()
      ..submissionError = const TuiGatewayRpcError(
        'prompt.submit',
        'method not found',
        code: -32601,
      );
    final fixture = _fixture(gateway, capability: () async => true);
    addTearDown(fixture.chat.dispose);

    final accepted = await fixture.chat.send(
      fullText: 'mensaje moderno',
      model: 'hermes-agent',
      history: const [],
      delivery: fixture.delivery,
    );

    expect(accepted, isFalse);
    expect(gateway.submissions, isEmpty);
    expect(gateway.idempotentSubmissions, hasLength(1));
    expect(fixture.chat.turnIdempotencyInvalid, isTrue);
    expect(fixture.delivery.current.state, PreparedTurnState.ambiguous);
  });

  test('turn.status recupera running sin volver a enviar', () async {
    final gateway = _ModernGateway()
      ..nextStatus = const DesktopTurnStatus(
        known: true,
        clientTurnId: 'client-turn-1',
        serverTurnId: 'server-turn-1',
        state: DesktopTurnState.running,
      );
    final fixture = _fixture(gateway, capability: () async => true);
    addTearDown(fixture.chat.dispose);
    final ambiguous = fixture.delivery.current.copyWith(
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
      state: PreparedTurnState.ambiguous,
    );

    final resolved = await fixture.chat.reconcileAmbiguousTurn(
      ambiguous,
      fixture.store,
    );

    expect(resolved.state, PreparedTurnState.running);
    expect(gateway.statusCalls, 1);
    expect(gateway.submissions, isEmpty);
    expect(gateway.idempotentSubmissions, isEmpty);
    expect(fixture.chat.state, ChatPipelineState.waiting);
  });

  test('running restaurado se elimina al recibir el terminal real', () async {
    final gateway = _ModernGateway()
      ..nextStatus = const DesktopTurnStatus(
        known: true,
        clientTurnId: 'client-turn-1',
        serverTurnId: 'server-turn-1',
        state: DesktopTurnState.running,
      );
    final fixture = _fixture(gateway, capability: () async => true);
    addTearDown(fixture.chat.dispose);
    final ambiguous = fixture.delivery.current.copyWith(
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
      state: PreparedTurnState.ambiguous,
    );

    final resolved = await fixture.chat.reconcileAmbiguousTurn(
      ambiguous,
      fixture.store,
    );
    expect(resolved.state, PreparedTurnState.running);

    gateway.emit('message.complete', payload: const {'text': 'hecho'});
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);

    expect(fixture.chat.activeTurnDelivery, isNull);
    expect(fixture.store.deletes, hasLength(1));
    expect(fixture.store.deletes.single.state, PreparedTurnState.terminal);
  });

  test('turn.status known=false permanece ambiguo', () async {
    final gateway = _ModernGateway();
    final fixture = _fixture(gateway, capability: () async => true);
    addTearDown(fixture.chat.dispose);
    final ambiguous = fixture.delivery.current.copyWith(
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
      state: PreparedTurnState.ambiguous,
    );

    final resolved = await fixture.chat.reconcileAmbiguousTurn(
      ambiguous,
      fixture.store,
    );

    expect(resolved.state, PreparedTurnState.ambiguous);
    expect(gateway.statusCalls, 1);
    expect(fixture.store.deletes, isEmpty);
  });

  test('turn.status terminal limpia la outbox sin reenviar', () async {
    final gateway = _ModernGateway()
      ..nextStatus = const DesktopTurnStatus(
        known: true,
        clientTurnId: 'client-turn-1',
        serverTurnId: 'server-turn-1',
        state: DesktopTurnState.terminal,
      );
    final fixture = _fixture(gateway, capability: () async => true);
    addTearDown(fixture.chat.dispose);
    final accepted = fixture.delivery.current.copyWith(
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
      state: PreparedTurnState.accepted,
    );

    final resolved = await fixture.chat.reconcileAmbiguousTurn(
      accepted,
      fixture.store,
    );

    expect(resolved.state, PreparedTurnState.terminal);
    expect(fixture.store.deletes, hasLength(1));
    expect(gateway.submissions, isEmpty);
    expect(gateway.idempotentSubmissions, isEmpty);
  });

  test('turn.status no se consulta sin capability positiva', () async {
    final gateway = _ModernGateway();
    final fixture = _fixture(gateway, capability: () async => false);
    addTearDown(fixture.chat.dispose);
    final ambiguous = fixture.delivery.current.copyWith(
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
      state: PreparedTurnState.ambiguous,
    );

    final resolved = await fixture.chat.reconcileAmbiguousTurn(
      ambiguous,
      fixture.store,
    );

    expect(resolved.state, PreparedTurnState.ambiguous);
    expect(gateway.statusCalls, 0);
  });
}
