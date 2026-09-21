import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/models/desktop_active_session.dart';
import 'package:hermes_android/core/models/desktop_control_center.dart';
import 'package:hermes_android/core/models/desktop_session_snapshot.dart';
import 'package:hermes_android/core/services/active_chat_service.dart';
import 'package:hermes_android/core/services/connection_manager.dart';
import 'package:hermes_android/core/services/desktop_control_gateway.dart';
import 'package:hermes_android/core/services/desktop_gateway_capabilities.dart';
import 'package:hermes_android/core/services/tui_gateway_client.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'support/in_memory_compression_fence_storage.dart';

class _StopGateway
    implements
        HermesDesktopGateway,
        HermesDesktopSessionLifecycleGateway,
        HermesDesktopSessionActivityGateway,
        HermesDesktopControlGateway {
  final _events = StreamController<TuiGatewayEvent>.broadcast();
  final interrupted = <String>[];
  final killed = <({String runtimeId, String processId})>[];
  bool running = true;
  bool exposeProcess = false;

  @override
  Stream<TuiGatewayEvent> get events => _events.stream;

  @override
  bool get isConnected => true;

  @override
  Future<void> connect() async {}

  DesktopSessionSnapshot _snapshot(String storedSessionId) =>
      DesktopSessionSnapshot(
        runtimeSessionId: 'runtime-$storedSessionId',
        storedSessionId: storedSessionId,
        created: false,
        running: running,
        status: running ? 'working' : 'idle',
        inflight: running
            ? DesktopInflightTurn(user: 'keep working', streaming: true)
            : null,
      );

  @override
  Future<DesktopSessionBinding> resumeSession(
    String storedSessionId, {
    String profile = '',
    List<Map<String, dynamic>> seedMessages = const [],
    String model = '',
  }) async => DesktopSessionBinding(
    runtimeSessionId: 'runtime-$storedSessionId',
    storedSessionId: storedSessionId,
    created: false,
    running: running,
    status: running ? 'working' : 'idle',
    inflight: running
        ? DesktopInflightTurn(user: 'keep working', streaming: true)
        : null,
  );

  @override
  Future<DesktopSessionSnapshot> resumeExisting(
    String storedSessionId, {
    String profile = '',
    bool omitMessages = false,
    bool deferHistory = false,
  }) async => _snapshot(storedSessionId);

  @override
  Future<DesktopSessionSnapshot> createForFirstSubmit({
    String profile = '',
    List<Map<String, dynamic>> seedMessages = const [],
    String model = '',
  }) => throw UnimplementedError();

  @override
  Future<void> interrupt(String runtimeSessionId) async {
    interrupted.add(runtimeSessionId);
    running = false;
  }

  @override
  DesktopGatewayCapabilityState capabilityState(
    DesktopGatewayCapability capability,
  ) => DesktopGatewayCapabilityState.supported;

  @override
  Future<DesktopSessionSnapshot> activateSession(
    String runtimeSessionId, {
    required String storedSessionId,
  }) async => _snapshot(storedSessionId);

  @override
  Future<DesktopActiveSessionList> listActiveSessions({
    String currentRuntimeSessionId = '',
  }) async => DesktopActiveSessionList(
    sessions: running
        ? const [
            DesktopActiveSession(
              runtimeSessionId: 'runtime-stop-session',
              storedSessionId: 'stop-session',
              status: 'working',
            ),
          ]
        : const [],
  );

  @override
  Future<AgentCenterSnapshot> agentCenterSnapshot({
    String runtimeSessionId = '',
  }) async => AgentCenterSnapshot(
    snapshots: const [],
    processes: exposeProcess
        ? const [
            BackgroundProcessEntry(
              opaqueId: 'process-1',
              status: AgentCenterStatus.running,
              uptimeSeconds: 1,
            ),
          ]
        : const [],
  );

  @override
  Future<void> killBackgroundProcess(
    String runtimeSessionId,
    String processId,
  ) async {
    killed.add((runtimeId: runtimeSessionId, processId: processId));
    exposeProcess = false;
  }

  @override
  Future<void> submitPrompt(String runtimeSessionId, String text) async {}

  @override
  Future<void> steer(String runtimeSessionId, String text) async {}

  @override
  Future<void> resolveApproval(
    String runtimeSessionId,
    String choice, {
    bool resolveAll = false,
    String? requestId,
  }) async {}

  @override
  Future<void> close() async {
    if (!_events.isClosed) await _events.close();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

SavedConnection _connection() => SavedConnection(
  id: 'stop-connection',
  label: 'Stop test',
  host: 'example.invalid',
  port: 443,
  apiKey: 'test-key',
  useHttps: true,
  kind: InstanceKind.vps,
);

Session _session() => Session(
  id: 'stop-session',
  title: 'Stop session',
  model: 'hermes-agent',
  source: 'mobile',
  messageCount: 1,
  isActive: true,
  preview: 'Working',
  startedAt: 1,
);

ApiClient _api() => ApiClient(
  baseUrl: 'https://example.invalid',
  apiKey: 'test-key',
  httpClient: MockClient((_) async => http.Response('{"messages":[]}', 200)),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('row Stop resumes a missing ActiveChat and interrupts its runtime', () async {
    final gateway = _StopGateway();
    final service = ActiveChatService(
      compressionFenceStore: testCompressionFenceStore(),
    );
    addTearDown(service.dispose);
    addTearDown(gateway.close);

    expect(service.of(_connection().id, _session().id), isNull);

    await service.stopSessionWork(
      connection: _connection(),
      session: _session(),
      desktopGateway: gateway,
      api: _api(),
      storedMessageLoader: (_, _) async => const [],
    );

    expect(gateway.interrupted, ['runtime-stop-session']);
    expect(service.of(_connection().id, _session().id), isNull);
  });

  test('session Stop also kills listed background processes', () async {
    final gateway = _StopGateway()..exposeProcess = true;
    final service = ActiveChatService(
      compressionFenceStore: testCompressionFenceStore(),
    );
    addTearDown(service.dispose);
    addTearDown(gateway.close);
    final chat = service.attach(
      connection: _connection(),
      sessionId: _session().id,
      sessionTitle: _session().title,
      initialStoredSessionId: _session().id,
      desktopGateway: gateway,
      api: _api(),
      storedMessageLoader: (_, _) async => const [],
      attachDesktopRuntimeOnLoad: true,
      allowUnownedDesktopSnapshotForTesting: true,
      disableForegroundKeepAlive: true,
    );
    await chat.loadMessages();
    await chat.refreshBackgroundProcessesForTesting();
    expect(chat.backgroundProcesses.map((process) => process.id), ['process-1']);

    await service.stopSessionWork(
      connection: _connection(),
      session: _session(),
    );

    expect(gateway.interrupted, ['runtime-stop-session']);
    expect(
      gateway.killed,
      [(runtimeId: 'runtime-stop-session', processId: 'process-1')],
    );
  });
}
