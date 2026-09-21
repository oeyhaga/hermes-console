import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:hermes_android/core/models/desktop_session_snapshot.dart';
import 'package:hermes_android/core/services/active_chat_service.dart';
import 'package:hermes_android/core/services/connection_manager.dart';
import 'package:hermes_android/core/services/tui_gateway_client.dart';

import 'support/in_memory_compression_fence_storage.dart';

/// Gateway moderno: publica resolver durable y rewind durable, y registra por
/// separado los `prompt.submit` planos y los que llevan dirección de recorte.
class _RewriteGateway
    implements
        HermesDesktopGateway,
        HermesDesktopSessionLifecycleGateway,
        HermesDesktopRewindResolverGateway,
        HermesDesktopRewindGateway,
        HermesDesktopDurableRewindGateway {
  _RewriteGateway({
    this.resolvedRowId,
    this.ack = const DesktopRewindAck(),
    this.requireRebindForAck = false,
    this.durableError,
    List<Object?> durableOutcomes = const [],
    List<DesktopSessionSnapshot> resumeSnapshots = const [],
  }) : durableOutcomes = List<Object?>.of(durableOutcomes),
       resumeSnapshots = List<DesktopSessionSnapshot>.of(resumeSnapshots);

  /// Lo que `session.history` puede probar. `null` = fail-closed, que es lo que
  /// devuelve siempre el cliente real tras una compactación.
  final int? resolvedRowId;
  final DesktopRewindAck ack;
  final bool requireRebindForAck;
  final Object? durableError;
  final List<Object?> durableOutcomes;
  final List<DesktopSessionSnapshot> resumeSnapshots;

  final _events = StreamController<TuiGatewayEvent>.broadcast();
  final List<String> plainPrompts = [];
  final List<({String text, int ordinal, int rowId, List<int> rebind})>
  durableRewinds = [];
  final List<({String text, int ordinal})> legacyRewinds = [];
  int resolverCalls = 0;
  int resumeExistingCalls = 0;

  void emit(String type, [Map<String, dynamic>? payload]) {
    _events.add(
      TuiGatewayEvent(
        type: type,
        sessionId: 'runtime-1',
        payload: payload ?? const {},
      ),
    );
  }

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
    runtimeSessionId: 'runtime-1',
    storedSessionId: storedSessionId,
    created: false,
  );

  @override
  Future<DesktopSessionSnapshot> resumeExisting(
    String storedSessionId, {
    String profile = '',
    bool omitMessages = false,
    bool deferHistory = false,
  }) async {
    resumeExistingCalls++;
    if (resumeSnapshots.isNotEmpty) return resumeSnapshots.removeAt(0);
    return DesktopSessionSnapshot(
      runtimeSessionId: 'runtime-1',
      storedSessionId: storedSessionId,
      created: false,
    );
  }

  @override
  Future<DesktopSessionSnapshot> createForFirstSubmit({
    String profile = '',
    List<Map<String, dynamic>> seedMessages = const [],
    String model = '',
  }) async => const DesktopSessionSnapshot(
    runtimeSessionId: 'runtime-1',
    storedSessionId: 'sess-rewrite',
    created: true,
  );

  @override
  Future<void> submitPrompt(String runtimeSessionId, String text) async {
    plainPrompts.add(text);
  }

  @override
  Future<void> steer(String runtimeSessionId, String text) async {}

  @override
  Future<void> interrupt(String runtimeSessionId) async {
    emit('message.complete', const {'text': 'Operation interrupted.'});
  }

  @override
  Future<void> resolveApproval(
    String runtimeSessionId,
    String choice, {
    bool resolveAll = false,
    String? requestId,
  }) async {}

  @override
  Future<void> close() => _events.close();

  @override
  Future<int?> resolveDurableUserRowId(
    String runtimeSessionId, {
    required String sourceText,
    required int expectedOrdinal,
  }) async {
    resolverCalls++;
    return resolvedRowId;
  }

  @override
  Future<void> submitRewindPrompt(
    String runtimeSessionId,
    String text,
    int truncateBeforeUserOrdinal,
  ) async {
    legacyRewinds.add((text: text, ordinal: truncateBeforeUserOrdinal));
  }

  @override
  Future<DesktopRewindAck> submitDurableRewindPrompt(
    String runtimeSessionId,
    String text,
    int truncateBeforeUserOrdinal, {
    required int truncateBeforeRowId,
    List<int> rebindSurvivorRowIds = const [],
  }) async {
    durableRewinds.add((
      text: text,
      ordinal: truncateBeforeUserOrdinal,
      rowId: truncateBeforeRowId,
      rebind: List<int>.of(rebindSurvivorRowIds),
    ));
    if (durableOutcomes.isNotEmpty) {
      final outcome = durableOutcomes.removeAt(0);
      if (outcome != null) throw outcome;
    }
    final error = durableError;
    if (error != null) throw error;
    if (requireRebindForAck && rebindSurvivorRowIds.isEmpty) {
      return const DesktopRewindAck();
    }
    return ack;
  }
}

SavedConnection _connection() => SavedConnection(
  id: 'conn-rewrite',
  label: 'Remoto',
  host: 'hermes.local',
  port: 8642,
  apiKey: 'test-key',
);

({ActiveChatService service, ActiveChat chat}) _attach(
  _RewriteGateway gateway,
) {
  final service = ActiveChatService(
    compressionFenceStore: testCompressionFenceStore(),
  );
  final connection = _connection();
  final chat = service.attach(
    connection: connection,
    sessionId: 'sess-rewrite',
    sessionTitle: 'Rewrite',
    api: ApiClient(
      baseUrl: connection.baseUrl,
      apiKey: 'test-key',
      httpClient: MockClient((_) async => http.Response('not found', 404)),
    ),
    desktopGateway: gateway,
  );
  return (service: service, chat: chat);
}

Map<String, dynamic> _userRow(
  List<Map<String, dynamic>> messages,
  String text,
) => messages.firstWhere((message) => message['content'] == text);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // Canales de plataforma en memoria: sin ellos el turno muere con
  // MissingPluginException antes de llegar al gateway y la prueba dejaría de
  // observar el comportamiento de rewind.
  final secureStore = <String, String>{};

  void mockChannel(String name) {
    TestWidgetsFlutterBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(MethodChannel(name), (_) async => null);
  }

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    secureStore.clear();
    TestWidgetsFlutterBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
          (call) async {
            final args =
                (call.arguments as Map?)?.cast<String, dynamic>() ?? {};
            switch (call.method) {
              case 'write':
                secureStore[args['key'] as String] = args['value'] as String;
                return null;
              case 'read':
                return secureStore[args['key'] as String];
              case 'readAll':
                return Map<String, String>.from(secureStore);
              case 'delete':
                secureStore.remove(args['key'] as String);
                return null;
              case 'deleteAll':
                secureStore.clear();
                return null;
              case 'containsKey':
                return secureStore.containsKey(args['key'] as String);
            }
            return null;
          },
        );
    TestWidgetsFlutterBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('flutter_foreground_task/methods'),
          (call) async => call.method == 'isRunningService' ? true : null,
        );
    mockChannel('flutter_foreground_task/background');
    mockChannel('dexterous.com/flutter/local_notifications');
  });

  test('editar sin dirección durable falla cerrado sin duplicar', () async {
    final gateway = _RewriteGateway();
    final attached = _attach(gateway);
    addTearDown(attached.service.dispose);
    final chat = attached.chat;
    chat.internalMessagesForTesting = [
      {'role': 'assistant', 'content': 'respuesta original'},
      {'role': 'user', 'content': 'pregunta original'},
    ];
    chat.state = ChatPipelineState.completed;
    expect(
      await chat.ensureDesktopRuntime(acquireForExplicitAction: true),
      isTrue,
    );

    await expectLater(
      chat.rewrite(
        userOrdinal: 0,
        text: 'pregunta corregida',
        model: 'hermes-agent',
      ),
      throwsA(isA<StateError>()),
    );

    expect(gateway.resolverCalls, 1);
    expect(gateway.durableRewinds, isEmpty);
    expect(gateway.legacyRewinds, isEmpty);
    expect(gateway.plainPrompts, isEmpty);
    final contents = chat.internalMessagesForTesting
        .map((message) => (message['content'] ?? '').toString())
        .toList(growable: false);
    expect(contents, isNot(contains('pregunta corregida')));
    expect(contents, contains('pregunta original'));
  });

  test('editar un turno fallido reenvía plano', () async {
    final gateway = _RewriteGateway(resolvedRowId: 73);
    final attached = _attach(gateway);
    addTearDown(attached.service.dispose);
    final chat = attached.chat;
    // El optimista de usuario nunca llegó al gateway: su row id cacheado ya no
    // direcciona nada y un truncate por él erraría el tiro.
    chat.internalMessagesForTesting = [
      {'role': 'assistant_error', 'content': 'el turno falló'},
      {'role': 'user', 'content': 'pregunta original', '_desktopRowId': 73},
    ];
    chat.state = ChatPipelineState.failed;
    expect(
      await chat.ensureDesktopRuntime(acquireForExplicitAction: true),
      isTrue,
    );

    await chat.rewrite(
      userOrdinal: 0,
      text: 'pregunta corregida',
      model: 'hermes-agent',
    );

    expect(gateway.durableRewinds, isEmpty);
    expect(gateway.legacyRewinds, isEmpty);
    expect(gateway.plainPrompts, ['pregunta corregida']);
  });

  test('desajuste de longitud no borra los row_id supervivientes', () async {
    final gateway = _RewriteGateway(
      ack: const DesktopRewindAck(survivorUserRowIds: [111]),
    );
    final attached = _attach(gateway);
    addTearDown(attached.service.dispose);
    final chat = attached.chat;
    chat.internalMessagesForTesting = [
      {'role': 'assistant', 'content': 'respuesta C'},
      {'role': 'user', 'content': 'pregunta C', '_desktopRowId': 33},
      {'role': 'assistant', 'content': 'respuesta B'},
      {'role': 'user', 'content': 'pregunta B', '_desktopRowId': 22},
      {'role': 'assistant', 'content': 'respuesta A'},
      {'role': 'user', 'content': 'pregunta A', '_desktopRowId': 11},
    ];
    chat.state = ChatPipelineState.completed;
    expect(
      await chat.ensureDesktopRuntime(acquireForExplicitAction: true),
      isTrue,
    );

    await chat.rewrite(
      userOrdinal: 2,
      text: 'pregunta C corregida',
      model: 'hermes-agent',
    );

    expect(gateway.durableRewinds, hasLength(1));
    expect(gateway.durableRewinds.single.rowId, 33);
    final messages = chat.internalMessagesForTesting;
    // El ACK sólo describe un superviviente, pero eso no invalida a los que sí
    // cubre: únicamente los ordinales fuera del rango pierden su identidad.
    expect(_userRow(messages, 'pregunta A')['_desktopRowId'], 111);
    expect(
      _userRow(messages, 'pregunta B').containsKey('_desktopRowId'),
      isFalse,
    );
  });

  test('se acepta survivor_row_id_map', () async {
    final gateway = _RewriteGateway(
      ack: const DesktopRewindAck(survivorRowIdMap: {11: 111, 22: null}),
    );
    final attached = _attach(gateway);
    addTearDown(attached.service.dispose);
    final chat = attached.chat;
    chat.internalMessagesForTesting = [
      {'role': 'assistant', 'content': 'respuesta C'},
      {'role': 'user', 'content': 'pregunta C', '_desktopRowId': 33},
      {'role': 'assistant', 'content': 'respuesta B'},
      {'role': 'user', 'content': 'pregunta B', '_desktopRowId': 22},
      {'role': 'assistant', 'content': 'respuesta A'},
      {'role': 'user', 'content': 'pregunta A', '_desktopRowId': 11},
    ];
    chat.state = ChatPipelineState.completed;
    expect(
      await chat.ensureDesktopRuntime(acquireForExplicitAction: true),
      isTrue,
    );

    await chat.rewrite(
      userOrdinal: 2,
      text: 'pregunta C corregida',
      model: 'hermes-agent',
    );

    final messages = chat.internalMessagesForTesting;
    expect(_userRow(messages, 'pregunta A')['_desktopRowId'], 111);
    expect(
      _userRow(messages, 'pregunta B').containsKey('_desktopRowId'),
      isFalse,
    );
  });

  test('two consecutive edits use the survivor row id map', () async {
    final gateway = _RewriteGateway(
      resolvedRowId: 999,
      requireRebindForAck: true,
      ack: const DesktopRewindAck(
        survivorRowIdMap: {11: 111, 22: 222, 33: null},
      ),
    );
    final attached = _attach(gateway);
    addTearDown(attached.service.dispose);
    final chat = attached.chat;
    chat.internalMessagesForTesting = [
      {'role': 'assistant', 'content': 'respuesta C'},
      {'role': 'user', 'content': 'pregunta C', '_desktopRowId': 33},
      {'role': 'assistant', 'content': 'respuesta B'},
      {'role': 'user', 'content': 'pregunta B', '_desktopRowId': 22},
      {'role': 'assistant', 'content': 'respuesta A'},
      {'role': 'user', 'content': 'pregunta A', '_desktopRowId': 11},
    ];
    chat.state = ChatPipelineState.completed;
    expect(
      await chat.ensureDesktopRuntime(acquireForExplicitAction: true),
      isTrue,
    );

    await chat.rewrite(
      userOrdinal: 2,
      text: 'pregunta C corregida',
      model: 'hermes-agent',
    );
    await chat.rewrite(
      userOrdinal: 1,
      text: 'pregunta B corregida',
      model: 'hermes-agent',
    );

    expect(gateway.durableRewinds, hasLength(2));
    expect(gateway.durableRewinds.first.rebind, [33, 22, 11]);
    expect(gateway.durableRewinds.last.rowId, 222);
  });

  test('stale durable target resumes history and retries the real edit', () async {
    final initialResume = DesktopSessionSnapshot(
      runtimeSessionId: 'runtime-1',
      storedSessionId: 'sess-rewrite',
      created: false,
    );
    final refreshedResume = DesktopSessionSnapshot.fromJson(
      const {
        'session_id': 'runtime-2',
        'stored_session_id': 'sess-rewrite',
        'messages': [
          {'role': 'user', 'content': 'pregunta anterior', 'row_id': 41},
          {'role': 'assistant', 'content': 'respuesta anterior', 'row_id': 42},
          {'role': 'user', 'content': 'turno insertado', 'row_id': 99},
          {'role': 'assistant', 'content': 'respuesta insertada', 'row_id': 100},
          {'role': 'user', 'content': 'pregunta original', 'row_id': 173},
          {'role': 'assistant', 'content': 'respuesta original', 'row_id': 174},
        ],
        'message_count': 6,
      },
      requestedStoredSessionId: 'sess-rewrite',
      created: false,
      method: 'session.resume',
    );
    final gateway = _RewriteGateway(
      resumeSnapshots: [initialResume, refreshedResume],
      durableOutcomes: const [
        TuiGatewayRpcError(
          'prompt.submit',
          'target user message is no longer in session history',
          code: 4018,
        ),
        null,
      ],
    );
    final attached = _attach(gateway);
    addTearDown(attached.service.dispose);
    final chat = attached.chat;
    chat.internalMessagesForTesting = [
      {'role': 'assistant', 'content': 'respuesta original', '_desktopRowId': 74},
      {'role': 'user', 'content': 'pregunta original', '_desktopRowId': 73},
      {'role': 'assistant', 'content': 'respuesta anterior', '_desktopRowId': 42},
      {'role': 'user', 'content': 'pregunta anterior', '_desktopRowId': 41},
    ];
    chat.state = ChatPipelineState.completed;
    expect(
      await chat.ensureDesktopRuntime(acquireForExplicitAction: true),
      isTrue,
    );

    await chat.rewrite(
      userOrdinal: 1,
      text: 'pregunta corregida',
      model: 'hermes-agent',
    );

    expect(gateway.resumeExistingCalls, 2);
    expect(gateway.durableRewinds, hasLength(2));
    expect(gateway.durableRewinds.first.rowId, 73);
    expect(gateway.durableRewinds.last.rowId, 173);
    expect(gateway.durableRewinds.last.ordinal, 2);
    expect(gateway.plainPrompts, isEmpty);
  });

  test(
    'failed live edit rollback removes pipeline rows and stays cancelled',
    () async {
      final gateway = _RewriteGateway(
        durableError: const TuiGatewayRpcError(
          'prompt.submit',
          'transport rejected rewind',
          code: 4007,
        ),
      );
      final attached = _attach(gateway);
      addTearDown(attached.service.dispose);
      final chat = attached.chat;
      expect(
        await chat.ensureDesktopRuntime(acquireForExplicitAction: true),
        isTrue,
      );
      chat.internalMessagesForTesting = [
        {
          'role': 'assistant',
          'content': 'respuesta parcial',
          '_pipeline': true,
        },
        {'role': 'user', 'content': 'pregunta original', '_desktopRowId': 73},
      ];
      chat.state = ChatPipelineState.streaming;

      await chat.rewrite(
        userOrdinal: 0,
        text: 'pregunta corregida',
        model: 'hermes-agent',
      );

      expect(
        chat.internalMessagesForTesting.any(
          (message) => message['_pipeline'] == true,
        ),
        isFalse,
      );
      expect(chat.state, ChatPipelineState.cancelled);
    },
  );

  test('DesktopRewindAck parsea survivor_row_id_map', () {
    final ack = DesktopRewindAck.fromJson(const {
      'survivor_row_id_map': {'11': 111, '22': null, 'malformado': 9},
    });

    expect(ack.survivorRowIdMap, {11: 111, 22: null});
    expect(ack.survivorUserRowIds, isNull);
  });

  test('una edición tras Stop no deja la cola suspendida', () async {
    final gateway = _RewriteGateway(resolvedRowId: 73);
    final attached = _attach(gateway);
    addTearDown(attached.service.dispose);
    final chat = attached.chat;

    expect(
      await chat.send(
        fullText: 'turno vivo',
        model: 'hermes-agent',
        history: const [],
      ),
      isTrue,
    );
    expect(chat.enqueue('pendiente'), isTrue);

    await chat.cancel();
    expect(chat.queueParked, isTrue);
    expect(chat.queueDrainSuspendedForTesting, isTrue);

    chat.internalMessagesForTesting = [
      {'role': 'assistant', 'content': 'respuesta original'},
      {'role': 'user', 'content': 'pregunta original', '_desktopRowId': 73},
    ];

    await chat.rewrite(
      userOrdinal: 0,
      text: 'pregunta corregida',
      model: 'hermes-agent',
    );

    // Editar es un gesto explícito: admite y levanta el park, igual que enviar.
    expect(chat.queueDrainSuspendedForTesting, isFalse);
    expect(chat.queueParked, isFalse);
    expect(chat.queuedMessages, ['pendiente']);
  });
}
