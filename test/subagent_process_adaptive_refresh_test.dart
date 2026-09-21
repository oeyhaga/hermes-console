import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/models/desktop_control_center.dart';
import 'package:hermes_android/core/models/desktop_session_snapshot.dart';
import 'package:hermes_android/core/screens/chat_screen.dart';
import 'package:hermes_android/core/services/active_chat_service.dart';
import 'package:hermes_android/core/services/app_lock.dart';
import 'package:hermes_android/core/services/approval_policy.dart';
import 'package:hermes_android/core/services/bridge_manager.dart';
import 'package:hermes_android/core/services/connection_manager.dart';
import 'package:hermes_android/core/services/desktop_control_gateway.dart';
import 'package:hermes_android/core/services/font_size_service.dart';
import 'package:hermes_android/core/services/notifications/notification_service.dart';
import 'package:hermes_android/core/services/secure_storage.dart';
import 'package:hermes_android/core/services/sftp_transfer_service.dart';
import 'package:hermes_android/core/services/ssh_manager.dart';
import 'package:hermes_android/core/services/ssh_session_service.dart';
import 'package:hermes_android/core/services/tui_gateway_client.dart';
import 'package:hermes_android/main.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/in_memory_compression_fence_storage.dart';

class _AdaptiveGateway
    implements
        HermesDesktopGateway,
        HermesDesktopSessionLifecycleGateway,
        HermesDesktopSubagentGateway,
        HermesDesktopControlGateway,
        HermesDesktopSessionControlGateway {
  _AdaptiveGateway({required this.changeEventsAvailable});

  final bool changeEventsAvailable;
  final StreamController<TuiGatewayEvent> _events =
      StreamController<TuiGatewayEvent>.broadcast();
  bool connected = true;
  bool failReads = false;
  List<DesktopSubagentSnapshot> subagents = const [];
  AgentCenterSnapshot processSnapshot = const AgentCenterSnapshot(
    snapshots: [],
    processes: [],
  );
  int listCalls = 0;
  int processCalls = 0;
  int controlCalls = 0;

  void resetCounts() {
    listCalls = 0;
    processCalls = 0;
    controlCalls = 0;
  }

  void emit(String type, [Map<String, dynamic> payload = const {}]) {
    _events.add(
      TuiGatewayEvent(
        type: type,
        sessionId: 'runtime-adaptive',
        payload: payload,
      ),
    );
  }

  @override
  Stream<TuiGatewayEvent> get events => _events.stream;

  @override
  bool get isConnected => connected;

  @override
  Future<void> connect() async => connected = true;

  @override
  Future<DesktopSessionSnapshot> resumeExisting(
    String storedSessionId, {
    String profile = '',
    bool omitMessages = false,
    bool deferHistory = false,
  }) async => DesktopSessionSnapshot(
    runtimeSessionId: 'runtime-adaptive',
    storedSessionId: storedSessionId,
    created: false,
    running: true,
    status: 'working',
  );

  @override
  Future<DesktopSessionSnapshot> createForFirstSubmit({
    String profile = '',
    List<Map<String, dynamic>> seedMessages = const [],
    String model = '',
  }) async => const DesktopSessionSnapshot(
    runtimeSessionId: 'runtime-adaptive',
    storedSessionId: 'stored-adaptive',
    created: true,
  );

  @override
  Future<DesktopSessionBinding> resumeSession(
    String storedSessionId, {
    String profile = '',
    List<Map<String, dynamic>> seedMessages = const [],
    String model = '',
  }) async => DesktopSessionBinding(
    runtimeSessionId: 'runtime-adaptive',
    storedSessionId: storedSessionId,
    created: false,
  );

  @override
  Future<List<DesktopSubagentSnapshot>> listSubagents(
    String runtimeSessionId,
  ) async {
    listCalls += 1;
    if (failReads) throw StateError('subagent snapshot failed');
    return subagents;
  }

  @override
  Future<AgentCenterSnapshot> agentCenterSnapshot({
    String runtimeSessionId = '',
  }) async {
    processCalls += 1;
    if (failReads) throw StateError('process snapshot failed');
    return processSnapshot;
  }

  @override
  Future<SessionControlSnapshot> readSessionControl(
    String runtimeSessionId,
  ) async {
    controlCalls += 1;
    if (failReads) throw StateError('control snapshot failed');
    return const SessionControlSnapshot(
      goal: null,
      loop: null,
      heartbeat: null,
      revision: '',
      updatedAt: null,
    );
  }

  @override
  Future<void> submitPrompt(String runtimeSessionId, String text) async {}

  @override
  Future<void> steer(String runtimeSessionId, String text) async {}

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
  Future<void> close() async {
    connected = false;
    if (!_events.isClosed) await _events.close();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Fixture {
  const _Fixture({
    required this.gateway,
    required this.chat,
    required this.activeChats,
  });

  final _AdaptiveGateway gateway;
  final ActiveChat chat;
  final ActiveChatService activeChats;
}

final _connection = SavedConnection(
  id: 'adaptive-refresh',
  label: 'Adaptive refresh',
  host: 'example.invalid',
  port: 443,
  apiKey: 'test-only',
  useHttps: true,
  kind: InstanceKind.vps,
);

const _session = Session(
  id: 'stored-adaptive',
  title: 'Adaptive refresh',
  model: 'hermes-agent',
  source: 'mobile',
  messageCount: 0,
  isActive: true,
  preview: '',
  startedAt: 0,
);

Future<_Fixture> _mountChat(
  WidgetTester tester, {
  required bool changeEventsAvailable,
  List<DesktopSubagentSnapshot> subagents = const [],
  bool failReads = false,
}) async {
  final prefs = await SharedPreferences.getInstance();
  final manager = await ConnectionManager.create(prefs);
  final secure = SecureStorage();
  final gateway = _AdaptiveGateway(
    changeEventsAvailable: changeEventsAvailable,
  )
    ..subagents = subagents
    ..failReads = failReads;
  final activeChats = ActiveChatService(
    attachDesktopRuntimeOnLoad: false,
    compressionFenceStore: testCompressionFenceStore(),
  );
  final chat = activeChats.attach(
    connection: _connection,
    sessionId: _session.id,
    sessionTitle: _session.title,
    initialStoredSessionId: _session.id,
    api: ApiClient(
      baseUrl: 'https://example.invalid',
      apiKey: 'test-only',
      httpClient: MockClient((_) async => http.Response('unused', 500)),
    ),
    desktopGateway: gateway,
    attachDesktopRuntimeOnLoad: false,
    allowUnownedDesktopSnapshotForTesting: true,
    disableForegroundKeepAlive: true,
  );
  chat.messagesLoaded = true;
  expect(
    await chat.ensureDesktopRuntime(acquireForExplicitAction: true),
    isTrue,
  );
  await tester.pump();
  gateway.resetCounts();

  await tester.pumpWidget(
    HermesApp(
      connManager: manager,
      appLock: AppLockService(prefs),
      approvalPolicy: ApprovalPolicyService(prefs),
      fontSize: FontSizeService(prefs),
      bridgeManager: BridgeManager(secure, manager),
      sshManager: SshManager(secure, manager),
      sftpTransfers: SftpTransferService(
        SshManager(secure, manager),
        NotificationService(prefs),
      ),
      sshSessions: SshSessionService(SshManager(secure, manager)),
      notifications: NotificationService(prefs),
      activeChats: activeChats,
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(seconds: 4));
  await tester.pump(const Duration(milliseconds: 400));
  await tester.pump(const Duration(milliseconds: 400));
  await tester.pump(const Duration(milliseconds: 500));
  final context = tester.element(find.byType(Navigator).first);
  Navigator.of(context).push(
    PageRouteBuilder<void>(
      transitionDuration: Duration.zero,
      reverseTransitionDuration: Duration.zero,
      pageBuilder: (_, _, _) => ChatScreen(
        connection: _connection,
        session: _session,
        initialStoredSessionId: 'stored-adaptive',
      ),
    ),
  );
  await tester.pump();
  await tester.pump();
  return _Fixture(gateway: gateway, chat: chat, activeChats: activeChats);
}

Future<void> _disposeFixture(WidgetTester tester, _Fixture fixture) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump();
  fixture.activeChats.dispose();
  await fixture.gateway.close();
}

void _expectFullReads(_AdaptiveGateway gateway, int count) {
  expect(gateway.listCalls, count, reason: 'subagent.list reads');
  expect(gateway.processCalls, count, reason: 'process snapshot reads');
  expect(gateway.controlCalls, count, reason: 'session control reads');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({'onboarding_done': true});
    final secure = <String, String>{};
    TestWidgetsFlutterBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
          (call) async {
            final args = (call.arguments as Map?) ?? {};
            switch (call.method) {
              case 'read':
                return secure[args['key']];
              case 'write':
                secure[args['key'] as String] = args['value'] as String;
              case 'delete':
                secure.remove(args['key']);
              case 'readAll':
                return Map<String, String>.from(secure);
              case 'containsKey':
                return secure.containsKey(args['key']);
            }
            return null;
          },
        );
    for (final name in [
      'dexterous.com/flutter/local_notifications',
      'flutter_foreground_task/background',
    ]) {
      TestWidgetsFlutterBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(MethodChannel(name), (_) async => null);
    }
    TestWidgetsFlutterBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('flutter_foreground_task/methods'),
          (call) async => call.method == 'isRunningService' ? false : null,
        );
  });

  testWidgets('event gateway snapshots on attach and debounces unknown child', (
    tester,
  ) async {
    final fixture = await _mountChat(tester, changeEventsAvailable: true);
    _expectFullReads(fixture.gateway, 1);

    for (var index = 0; index < 10; index++) {
      fixture.gateway.emit('subagent.start', {
        'subagent_id': 'unknown-child',
        'event_id': 'event-$index',
        'event_revision': index + 1,
        'status': 'running',
      });
    }
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 249));
    _expectFullReads(fixture.gateway, 1);
    await tester.pump(const Duration(milliseconds: 1));
    expect(fixture.gateway.listCalls, 2);
    expect(fixture.gateway.processCalls, 1);
    expect(fixture.gateway.controlCalls, 1);

    await _disposeFixture(tester, fixture);
  });

  testWidgets('event gateway uses 30 second active backstop', (tester) async {
    final fixture = await _mountChat(
      tester,
      changeEventsAvailable: true,
      subagents: const [
        DesktopSubagentSnapshot(
          subagentId: 'active-child',
          status: 'running',
        ),
      ],
    );
    _expectFullReads(fixture.gateway, 1);

    await tester.pump(const Duration(milliseconds: 29999));
    _expectFullReads(fixture.gateway, 1);
    await tester.pump(const Duration(milliseconds: 1));
    _expectFullReads(fixture.gateway, 2);

    await _disposeFixture(tester, fixture);
  });

  testWidgets('event gateway uses 60 second stable empty backstop', (
    tester,
  ) async {
    final fixture = await _mountChat(tester, changeEventsAvailable: true);
    _expectFullReads(fixture.gateway, 1);

    await tester.pump(const Duration(milliseconds: 59999));
    _expectFullReads(fixture.gateway, 1);
    await tester.pump(const Duration(milliseconds: 1));
    _expectFullReads(fixture.gateway, 2);

    await _disposeFixture(tester, fixture);
  });

  testWidgets('legacy gateway retains five second cadence', (tester) async {
    final fixture = await _mountChat(tester, changeEventsAvailable: false);
    _expectFullReads(fixture.gateway, 1);

    await tester.pump(const Duration(milliseconds: 4999));
    _expectFullReads(fixture.gateway, 1);
    await tester.pump(const Duration(milliseconds: 1));
    _expectFullReads(fixture.gateway, 2);

    await _disposeFixture(tester, fixture);
  });

  testWidgets('failures back off and a relevant event resets the delay', (
    tester,
  ) async {
    final fixture = await _mountChat(
      tester,
      changeEventsAvailable: true,
      failReads: true,
    );
    _expectFullReads(fixture.gateway, 1);

    for (final delay in const [5, 15, 30, 60]) {
      await tester.pump(Duration(seconds: delay) - const Duration(milliseconds: 1));
      _expectFullReads(fixture.gateway, const [1, 2, 3, 4][const [5, 15, 30, 60].indexOf(delay)]);
      await tester.pump(const Duration(milliseconds: 1));
      _expectFullReads(fixture.gateway, const [2, 3, 4, 5][const [5, 15, 30, 60].indexOf(delay)]);
    }

    fixture.gateway.emit('status.update', const {'kind': 'process'});
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    expect(fixture.gateway.processCalls, 6);
    await tester.pump(
      const Duration(seconds: 5) - const Duration(milliseconds: 1),
    );
    expect(fixture.gateway.processCalls, 6);
    await tester.pump(const Duration(milliseconds: 1));
    expect(fixture.gateway.listCalls, 5);
    expect(fixture.gateway.processCalls, 7);
    expect(fixture.gateway.controlCalls, 5);

    await _disposeFixture(tester, fixture);
  });

  testWidgets('hidden and background routes perform zero reads', (tester) async {
    final fixture = await _mountChat(tester, changeEventsAvailable: true);
    _expectFullReads(fixture.gateway, 1);
    final navigator = tester.state<NavigatorState>(find.byType(Navigator).first);
    unawaited(
      navigator.push<void>(
        PageRouteBuilder<void>(
          transitionDuration: Duration.zero,
          reverseTransitionDuration: Duration.zero,
          pageBuilder: (_, _, _) => const SizedBox.expand(),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    fixture.gateway.resetCounts();
    await tester.pump(const Duration(seconds: 65));
    _expectFullReads(fixture.gateway, 0);

    navigator.pop();
    await tester.pump();
    await tester.pump();
    _expectFullReads(fixture.gateway, 1);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    fixture.gateway.resetCounts();
    await tester.pump(const Duration(seconds: 65));
    _expectFullReads(fixture.gateway, 0);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    await _disposeFixture(tester, fixture);
  });
}
