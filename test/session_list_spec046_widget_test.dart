import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/models/desktop_active_session.dart';
import 'package:hermes_android/core/models/desktop_session_snapshot.dart';
import 'package:hermes_android/core/screens/session_list_screen.dart';
import 'package:hermes_android/core/services/connection_manager.dart';
import 'package:hermes_android/core/services/desktop_gateway_capabilities.dart';
import 'package:hermes_android/core/services/session_deletion.dart';
import 'package:hermes_android/core/services/session_repository.dart';
import 'package:hermes_android/core/services/tui_gateway_client.dart';
import 'package:hermes_android/core/theme/app_theme.dart';
import 'package:hermes_android/l10n/app_localizations.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _connectionId = 'conn-spec-046';

Map<String, dynamic> _sessionRow(
  int index, {
  String? id,
  String? title,
  String source = 'mobile',
}) {
  final lastActive = 1784500000 - index * 60;
  return {
    'id': id ?? 'session-$index',
    '_lineage_root_id': 'root-$index',
    'title': title ?? 'Conversation $index',
    'preview': 'Preview $index',
    'model': 'model-a',
    'source': source,
    'message_count': 2,
    'is_active': false,
    'started_at': lastActive - 30,
    'ended_at': lastActive - 1,
    'last_active': lastActive,
    'archived': false,
  };
}

http.Response _pageResponse(
  Iterable<Map<String, dynamic>> rows, {
  required int total,
  required int limit,
  required int offset,
}) => http.Response(
  jsonEncode({
    'sessions': rows.toList(growable: false),
    'total': total,
    'limit': limit,
    'offset': offset,
  }),
  200,
);

http.Response _searchResponse({
  required String id,
  required String snippet,
  String source = 'mobile',
  bool archived = false,
}) => http.Response(
  jsonEncode({
    'results': [
      {
        'session_id': id,
        'lineage_root': 'root-$id',
        'snippet': snippet,
        'source': source,
        'model': 'model-a',
        'session_started': 1784500000,
        'archived': archived,
      },
    ],
  }),
  200,
);

ApiClient _gateway(http.Client client) => ApiClient(
  baseUrl: 'http://127.0.0.1:8642',
  apiKey: 'gateway-key',
  connectionId: _connectionId,
  httpClient: client,
);

DashboardClient _dashboard(http.Client client) => DashboardClient(
  host: '127.0.0.1',
  port: 9119,
  manualToken: 'dashboard-token',
  httpClientOverride: client,
);

SavedConnection _connection() => SavedConnection(
  id: _connectionId,
  label: 'Spec 046',
  host: '127.0.0.1',
  port: 8642,
  apiKey: 'gateway-key',
  dashboardUrl: 'http://127.0.0.1:9119',
  kind: InstanceKind.vps,
);

Widget _host(Widget child) => MaterialApp(
  locale: const Locale('en'),
  theme: AppTheme.fromId('dark'),
  localizationsDelegates: Strings.localizationsDelegates,
  supportedLocales: Strings.supportedLocales,
  home: child,
);

Future<ConnectionManager> _manager() async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  return ConnectionManager.create(prefs);
}

Future<void> _pumpUntil(
  WidgetTester tester,
  Finder finder, {
  int attempts = 40,
}) async {
  for (var attempt = 0; attempt < attempts; attempt++) {
    await tester.pump(const Duration(milliseconds: 25));
    if (finder.evaluate().isNotEmpty) return;
  }
  expect(finder, findsWidgets);
}

MockClient _healthyGatewayHttp() => MockClient((request) async {
  if (request.url.path == '/health' || request.url.path == '/api/sessions') {
    return http.Response('{}', 200);
  }
  return http.Response('{}', 404);
});

class _CountingActivityGateway implements HermesDesktopSessionActivityGateway {
  _CountingActivityGateway({this.inventory = const DesktopActiveSessionList()});

  DesktopActiveSessionList inventory;
  int listCalls = 0;

  @override
  DesktopGatewayCapabilityState capabilityState(
    DesktopGatewayCapability capability,
  ) => DesktopGatewayCapabilityState.supported;

  @override
  Future<DesktopSessionSnapshot> activateSession(
    String runtimeSessionId, {
    required String storedSessionId,
  }) => throw UnimplementedError();

  @override
  Future<DesktopActiveSessionList> listActiveSessions({
    String currentRuntimeSessionId = '',
  }) async {
    listCalls += 1;
    return inventory;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('sessions.changed es el único evento que refresca la biblioteca', () {
    expect(sessionLibraryRefreshGap, const Duration(seconds: 10));
    expect(
      isSessionLibraryRefreshEvent(
        const TuiGatewayEvent(
          type: 'sessions.changed',
          sessionId: '',
          payload: {},
        ),
      ),
      isTrue,
    );
    expect(
      isSessionLibraryRefreshEvent(
        const TuiGatewayEvent(
          type: 'message.delta',
          sessionId: 'runtime',
          payload: {},
        ),
      ),
      isFalse,
    );
  });

  setUp(() {
    TestWidgetsFlutterBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
          (call) async => call.method == 'readAll' ? <String, String>{} : null,
        );
  });

  tearDown(() {
    TestWidgetsFlutterBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
          null,
        );
  });

  testWidgets('a late search cannot replace the newest query', (tester) async {
    final alpha = Completer<http.Response>();
    final beta = Completer<http.Response>();
    final searchQueries = <String>[];
    final dashboardHttp = MockClient((request) async {
      if (request.url.path == '/api/sessions') {
        return _pageResponse(
          [_sessionRow(0, title: 'Initial conversation')],
          total: 1,
          limit: 50,
          offset: 0,
        );
      }
      if (request.url.path == '/api/sessions/search') {
        final query = request.url.queryParameters['q']!;
        searchQueries.add(query);
        return switch (query) {
          'alpha' => alpha.future,
          'beta' => beta.future,
          _ => http.Response('{}', 404),
        };
      }
      return http.Response('{}', 404);
    });
    final dashboard = _dashboard(dashboardHttp);
    final gateway = _gateway(_healthyGatewayHttp());
    final repository = SessionRepository(dashboard, gateway);
    addTearDown(() {
      repository.close();
      dashboard.close();
    });

    await tester.pumpWidget(
      _host(
        SessionListScreen(
          connection: _connection(),
          connManager: await _manager(),
          clientOverride: gateway,
          repositoryOverride: repository,
        ),
      ),
    );
    await _pumpUntil(tester, find.text('Initial conversation'));

    await tester.enterText(find.byType(TextField), 'alpha');
    await tester.pump(const Duration(milliseconds: 221));
    expect(searchQueries, ['alpha']);

    await tester.enterText(find.byType(TextField), 'beta');
    await tester.pump(const Duration(milliseconds: 221));
    expect(searchQueries, ['alpha', 'beta']);

    beta.complete(
      _searchResponse(id: 'beta-result', snippet: 'Beta visible phrase'),
    );
    await _pumpUntil(tester, find.text('Beta visible phrase'));
    expect(find.text('Alpha stale phrase'), findsNothing);

    alpha.complete(
      _searchResponse(id: 'alpha-result', snippet: 'Alpha stale phrase'),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 25));

    expect(find.text('Beta visible phrase'), findsWidgets);
    expect(find.text('Alpha stale phrase'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'la invalidación local refresca Conversaciones sin navegar de vuelta',
    (tester) async {
      var rows = <Map<String, dynamic>>[
        _sessionRow(0, title: 'Conversation removed by cleanup'),
      ];
      var sessionReads = 0;
      final dashboardHttp = MockClient((request) async {
        if (request.url.path == '/api/sessions') {
          sessionReads++;
          return _pageResponse(rows, total: rows.length, limit: 50, offset: 0);
        }
        return http.Response('{}', 404);
      });
      final dashboard = _dashboard(dashboardHttp);
      final gateway = _gateway(_healthyGatewayHttp());
      final repository = SessionRepository(dashboard, gateway);
      addTearDown(() {
        repository.close();
        dashboard.close();
      });

      await tester.pumpWidget(
        _host(
          SessionListScreen(
            connection: _connection(),
            connManager: await _manager(),
            clientOverride: gateway,
            repositoryOverride: repository,
          ),
        ),
      );
      await _pumpUntil(tester, find.text('Conversation removed by cleanup'));
      final readsBefore = sessionReads;

      historyCleanupInvalidations.publish(
        connectionId: 'another-connection',
        scope: HistoryCleanupScope.cronResults,
      );
      await tester.pump();
      expect(
        sessionReads,
        readsBefore,
        reason: 'Conversaciones ignora invalidaciones de otra conexión',
      );

      rows = [];
      historyCleanupInvalidations.publish(
        connectionId: _connectionId,
        scope: HistoryCleanupScope.cronResults,
      );
      for (var attempt = 0; attempt < 40; attempt++) {
        await tester.pump(const Duration(milliseconds: 25));
        if (find.text('Conversation removed by cleanup').evaluate().isEmpty) {
          break;
        }
      }

      expect(sessionReads, greaterThan(readsBefore));
      expect(find.text('Conversation removed by cleanup'), findsNothing);
      expect(find.byKey(const ValueKey('session-filter-all')), findsOneWidget);
      expect(
        find.byKey(const ValueKey('session-filter-automation')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('session-filter-everything')),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const ValueKey('session-filter-automation')));
      await _pumpUntil(tester, find.text('No automation sessions'));
      expect(find.text('No automation sessions'), findsOneWidget);
      expect(find.byKey(const ValueKey('session-filter-all')), findsOneWidget);
      expect(
        find.byKey(const ValueKey('session-filter-automation')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('session-filter-everything')),
        findsOneWidget,
      );

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      final readsAfterDispose = sessionReads;
      historyCleanupInvalidations.publish(
        connectionId: _connectionId,
        scope: HistoryCleanupScope.cronResults,
      );
      await tester.pump();
      expect(sessionReads, readsAfterDispose);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Dashboard keeps child sessions folded without exposing a fake toggle',
    (tester) async {
      final queries = <Map<String, String>>[];
      final child = _sessionRow(
        1,
        id: 'child-session',
        title: 'Hidden child session',
      )..['parent_session_id'] = 'session-0';
      final dashboardHttp = MockClient((request) async {
        if (request.url.path == '/api/sessions') {
          queries.add(request.url.queryParameters);
          return _pageResponse(
            [_sessionRow(0, title: 'Visible parent session'), child],
            total: 2,
            limit: 50,
            offset: 0,
          );
        }
        return http.Response('{}', 404);
      });
      final dashboard = _dashboard(dashboardHttp);
      final gateway = _gateway(_healthyGatewayHttp());
      final repository = SessionRepository(dashboard, gateway);
      addTearDown(() {
        repository.close();
        dashboard.close();
      });

      await tester.pumpWidget(
        _host(
          SessionListScreen(
            connection: _connection(),
            connManager: await _manager(),
            clientOverride: gateway,
            repositoryOverride: repository,
          ),
        ),
      );
      await _pumpUntil(tester, find.text('Visible parent session'));

      expect(find.text('Hidden child session'), findsNothing);
      expect(queries, hasLength(1));
      expect(queries.single.containsKey('include_children'), isFalse);

      await tester.tap(find.byTooltip('More options'));
      await tester.pumpAndSettle();

      expect(find.text('Refresh'), findsOneWidget);
      expect(find.text('Show sub-sessions'), findsNothing);
      expect(find.text('Hide sub-sessions'), findsNothing);
      expect(find.byIcon(Icons.account_tree_outlined), findsNothing);
      expect(queries, hasLength(1));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('categories and archive filter independently before pagination', (
    tester,
  ) async {
    final queries = <Map<String, String>>[];
    final dashboardHttp = MockClient((request) async {
      if (request.url.path == '/api/sessions') {
        queries.add(request.url.queryParameters);
        final sources = request.url.queryParameters['sources'];
        final excluded = request.url.queryParameters['exclude_sources'];
        final archived = request.url.queryParameters['archived'];
        if (archived == 'only') {
          return _pageResponse(
            [
              _sessionRow(2, title: 'Archived automation', source: 'webhook')
                ..['archived'] = true,
            ],
            total: 1,
            limit: 50,
            offset: 0,
          );
        }
        if (sources != null) {
          return _pageResponse(
            [
              _sessionRow(
                1,
                id: 'webhook_automation_20260802_013000',
                title: 'Webhook automation',
                source: 'webhook',
              ),
            ],
            total: 1,
            limit: 50,
            offset: 0,
          );
        }
        if (excluded == null) {
          return _pageResponse(
            [
              _sessionRow(3, title: 'Everything conversation'),
              _sessionRow(4, title: 'Everything automation', source: 'acp'),
            ],
            total: 2,
            limit: 50,
            offset: 0,
          );
        }
        return _pageResponse(
          [_sessionRow(0, title: 'Normal conversation')],
          total: 1,
          limit: 50,
          offset: 0,
        );
      }
      return http.Response('{}', 404);
    });
    final dashboard = _dashboard(dashboardHttp);
    final gateway = _gateway(_healthyGatewayHttp());
    final repository = SessionRepository(dashboard, gateway);
    addTearDown(() {
      repository.close();
      dashboard.close();
    });

    await tester.pumpWidget(
      _host(
        SessionListScreen(
          connection: _connection(),
          connManager: await _manager(),
          clientOverride: gateway,
          repositoryOverride: repository,
        ),
      ),
    );
    await _pumpUntil(tester, find.text('Normal conversation'));

    expect(queries, hasLength(1));
    expect(
      queries.single['exclude_sources'],
      'cron,kanban,subagent,tool,api_server,acp,hermes_flow,vulcan_delegate,webhook',
    );
    expect(queries.single['sources'], isNull);
    expect(queries.single['source'], isNull);
    expect(queries.single['archived'], 'exclude');
    expect(find.text('Normal conversation'), findsWidgets);
    expect(find.text('Webhook automation'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('session-filter-automation')));
    await _pumpUntil(tester, find.text('Webhook automation'));

    expect(queries, hasLength(2));
    expect(
      queries.last['sources'],
      'cron,kanban,subagent,tool,api_server,acp,hermes_flow,vulcan_delegate,webhook',
    );
    expect(queries.last['exclude_sources'], isNull);
    expect(queries.last['archived'], 'exclude');
    expect(find.text('Normal conversation'), findsNothing);
    expect(find.text('Webhook automation'), findsWidgets);

    await tester.tap(find.byKey(const ValueKey('session-filter-archived')));
    await _pumpUntil(tester, find.text('Archived automation'));

    expect(queries, hasLength(3));
    expect(
      queries.last['sources'],
      'cron,kanban,subagent,tool,api_server,acp,hermes_flow,vulcan_delegate,webhook',
    );
    expect(queries.last['exclude_sources'], isNull);
    expect(queries.last['archived'], 'only');
    expect(find.text('Webhook automation'), findsNothing);
    expect(find.text('Archived automation'), findsWidgets);

    await tester.tap(find.byKey(const ValueKey('session-filter-archived')));
    await _pumpUntil(tester, find.text('Webhook automation'));
    await tester.tap(find.byKey(const ValueKey('session-filter-everything')));
    await _pumpUntil(tester, find.text('Everything conversation'));

    expect(queries.last['sources'], isNull);
    expect(queries.last['exclude_sources'], isNull);
    expect(queries.last['archived'], 'exclude');
    expect(find.text('Everything conversation'), findsWidgets);
    expect(find.text('Everything automation'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('changing category restarts search and drops its late response', (
    tester,
  ) async {
    final chatSearch = Completer<http.Response>();
    final automationSearch = Completer<http.Response>();
    final searchQueries = <Map<String, String>>[];
    final dashboardHttp = MockClient((request) async {
      if (request.url.path == '/api/sessions') {
        final automation = request.url.queryParameters['sources'] != null;
        return _pageResponse(
          [
            _sessionRow(
              automation ? 1 : 0,
              title: automation ? 'Automation page' : 'Chat page',
              source: automation ? 'webhook' : 'mobile',
            ),
          ],
          total: 1,
          limit: 50,
          offset: 0,
        );
      }
      if (request.url.path == '/api/sessions/search') {
        searchQueries.add(request.url.queryParameters);
        return request.url.queryParameters['sources'] != null
            ? automationSearch.future
            : chatSearch.future;
      }
      return http.Response('{}', 404);
    });
    final dashboard = _dashboard(dashboardHttp);
    final gateway = _gateway(_healthyGatewayHttp());
    final repository = SessionRepository(dashboard, gateway);
    addTearDown(() {
      repository.close();
      dashboard.close();
    });

    await tester.pumpWidget(
      _host(
        SessionListScreen(
          connection: _connection(),
          connManager: await _manager(),
          clientOverride: gateway,
          repositoryOverride: repository,
        ),
      ),
    );
    await _pumpUntil(tester, find.text('Chat page'));

    await tester.enterText(find.byType(TextField), 'same');
    await tester.pump(const Duration(milliseconds: 221));
    expect(searchQueries, hasLength(1));

    await tester.tap(find.byKey(const ValueKey('session-filter-automation')));
    for (var attempt = 0; attempt < 40 && searchQueries.length < 2; attempt++) {
      await tester.pump(const Duration(milliseconds: 25));
    }
    expect(searchQueries, hasLength(2));

    automationSearch.complete(
      _searchResponse(
        id: 'automation-search',
        snippet: 'Automation search visible',
        source: 'webhook',
      ),
    );
    await _pumpUntil(tester, find.text('Automation search visible'));

    chatSearch.complete(
      _searchResponse(
        id: 'late-chat-search',
        snippet: 'Late chat must stay hidden',
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 25));

    expect(find.text('Automation search visible'), findsWidgets);
    expect(find.text('Late chat must stay hidden'), findsNothing);
    expect(searchQueries.first['exclude_sources'], isNotNull);
    expect(searchQueries.last['sources'], isNotNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Cron results filter fits a 320dp screen at 200% text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final dashboard = _dashboard(
      MockClient((request) async {
        if (request.url.path == '/api/sessions') {
          return _pageResponse(
            [_sessionRow(0, title: 'Conversación normal')],
            total: 1,
            limit: 50,
            offset: 0,
          );
        }
        return http.Response('{}', 404);
      }),
    );
    final gateway = _gateway(_healthyGatewayHttp());
    final repository = SessionRepository(dashboard, gateway);
    addTearDown(() {
      repository.close();
      dashboard.close();
    });

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('es'),
        theme: AppTheme.fromId('dark'),
        localizationsDelegates: Strings.localizationsDelegates,
        supportedLocales: Strings.supportedLocales,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: const TextScaler.linear(2)),
          child: child!,
        ),
        home: SessionListScreen(
          connection: _connection(),
          connManager: await _manager(),
          clientOverride: gateway,
          repositoryOverride: repository,
        ),
      ),
    );
    await _pumpUntil(tester, find.text('Conversación normal'));

    expect(find.text('Automatización'), findsOneWidget);
    expect(find.text('Todo'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('session-filter-archived')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('unavailable remote search falls back with a scope notice', (
    tester,
  ) async {
    final dashboardHttp = MockClient((request) async {
      if (request.url.path == '/api/sessions') {
        return _pageResponse(
          [_sessionRow(0, title: 'Needle local conversation')],
          total: 1,
          limit: 50,
          offset: 0,
        );
      }
      if (request.url.path == '/api/sessions/search') {
        return http.Response('{}', 404);
      }
      return http.Response('{}', 404);
    });
    final dashboard = _dashboard(dashboardHttp);
    final gateway = _gateway(_healthyGatewayHttp());
    final repository = SessionRepository(dashboard, gateway);
    addTearDown(() {
      repository.close();
      dashboard.close();
    });

    await tester.pumpWidget(
      _host(
        SessionListScreen(
          connection: _connection(),
          connManager: await _manager(),
          clientOverride: gateway,
          repositoryOverride: repository,
        ),
      ),
    );
    await _pumpUntil(tester, find.text('Needle local conversation'));

    await tester.enterText(find.byType(TextField), 'Needle');
    await tester.pump(const Duration(milliseconds: 221));
    await _pumpUntil(
      tester,
      find.text('Searching only the conversations already loaded'),
    );

    expect(find.text('Needle local conversation'), findsWidgets);
    expect(
      find.text('Searching only the conversations already loaded'),
      findsOneWidget,
    );
    final notice = find.byKey(const ValueKey('session-library-scope-notice'));
    expect(notice, findsOneWidget);
    expect(
      find.descendant(
        of: notice,
        matching: find.byKey(const ValueKey('hermes-info-banner-surface')),
      ),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('scrolling near the end loads and appends offset 50', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final offsets = <int>[];
    final dashboardHttp = MockClient((request) async {
      if (request.url.path != '/api/sessions') {
        return http.Response('{}', 404);
      }
      final limit = int.parse(request.url.queryParameters['limit']!);
      final offset = int.parse(request.url.queryParameters['offset']!);
      offsets.add(offset);
      if (offset == 0) {
        return _pageResponse(
          [for (var index = 0; index < 50; index++) _sessionRow(index)],
          total: 51,
          limit: limit,
          offset: offset,
        );
      }
      return _pageResponse(
        [_sessionRow(50)],
        total: 51,
        limit: limit,
        offset: offset,
      );
    });
    final dashboard = _dashboard(dashboardHttp);
    final gateway = _gateway(_healthyGatewayHttp());
    final repository = SessionRepository(dashboard, gateway);
    addTearDown(() {
      repository.close();
      dashboard.close();
    });

    await tester.pumpWidget(
      _host(
        SessionListScreen(
          connection: _connection(),
          connManager: await _manager(),
          clientOverride: gateway,
          repositoryOverride: repository,
        ),
      ),
    );
    await _pumpUntil(tester, find.text('Conversation 0'));

    await tester.fling(find.byType(ListView), const Offset(0, -8000), 5000);
    for (var attempt = 0; attempt < 40 && !offsets.contains(50); attempt++) {
      await tester.pump(const Duration(milliseconds: 25));
    }
    await _pumpUntil(tester, find.text('Conversation 50'));

    expect(offsets, [0, 50]);
    expect(find.text('Conversation 50'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('remote activity refreshes on open without periodic polling', (
    tester,
  ) async {
    final dashboardHttp = MockClient((request) async {
      if (request.url.path == '/api/sessions') {
        return _pageResponse(
          [_sessionRow(0, title: 'Activity probe conversation')],
          total: 1,
          limit: 50,
          offset: 0,
        );
      }
      return http.Response('{}', 404);
    });
    final dashboard = _dashboard(dashboardHttp);
    final gateway = _gateway(_healthyGatewayHttp());
    final repository = SessionRepository(dashboard, gateway);
    final activity = _CountingActivityGateway();
    addTearDown(() {
      repository.close();
      dashboard.close();
    });

    await tester.pumpWidget(
      _host(
        SessionListScreen(
          connection: _connection(),
          connManager: await _manager(),
          clientOverride: gateway,
          repositoryOverride: repository,
          activityGatewayOverride: activity,
        ),
      ),
    );
    await _pumpUntil(tester, find.text('Activity probe conversation'));
    await tester.pump();

    expect(activity.listCalls, 1);
    await tester.pump(const Duration(seconds: 5));
    expect(activity.listCalls, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'sessions.changed refresca working y no pierde su fila omitida por REST',
    (tester) async {
      final events = StreamController<TuiGatewayEvent>.broadcast();
      addTearDown(events.close);
      var pageRequests = 0;
      final dashboardHttp = MockClient((request) async {
        if (request.url.path != '/api/sessions') {
          return http.Response('{}', 404);
        }
        pageRequests += 1;
        final rows = pageRequests == 1
            ? [_sessionRow(0, title: 'Working conversation')]
            : [_sessionRow(1, title: 'Fresh conversation')];
        return _pageResponse(rows, total: rows.length, limit: 50, offset: 0);
      });
      final dashboard = _dashboard(dashboardHttp);
      final gateway = _gateway(_healthyGatewayHttp());
      final repository = SessionRepository(dashboard, gateway);
      final activity = _CountingActivityGateway(
        inventory: const DesktopActiveSessionList(
          sessions: [
            DesktopActiveSession(
              runtimeSessionId: 'runtime-0',
              storedSessionId: 'session-0',
              status: 'working',
            ),
          ],
        ),
      );
      addTearDown(() {
        repository.close();
        dashboard.close();
      });

      await tester.pumpWidget(
        _host(
          SessionListScreen(
            connection: _connection(),
            connManager: await _manager(),
            clientOverride: gateway,
            repositoryOverride: repository,
            activityGatewayOverride: activity,
            eventStreamOverride: events.stream,
          ),
        ),
      );
      await _pumpUntil(tester, find.text('Working conversation'));
      await _pumpUntil(
        tester,
        find.byKey(const ValueKey('session-running-session-0')),
      );

      events.add(
        const TuiGatewayEvent(
          type: 'sessions.changed',
          sessionId: '',
          payload: {},
        ),
      );
      await tester.pump(const Duration(milliseconds: 50));

      expect(pageRequests, 2);
      expect(activity.listCalls, 2);
      expect(find.text('Working conversation'), findsWidgets);
      expect(find.text('Fresh conversation'), findsWidgets);
      expect(
        find.byKey(const ValueKey('session-running-session-0')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('remote archive 500 rolls back, refreshes, and explains why', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final archiveResponse = Completer<http.Response>();
    var pageRequests = 0;
    var archiveRequests = 0;
    final dashboardHttp = MockClient((request) async {
      if (request.method == 'GET' && request.url.path == '/api/sessions') {
        pageRequests += 1;
        return _pageResponse(
          [_sessionRow(0, title: 'Archive rollback conversation')],
          total: 1,
          limit: 50,
          offset: 0,
        );
      }
      if (request.method == 'PATCH' &&
          request.url.path == '/api/sessions/session-0') {
        archiveRequests += 1;
        expect(jsonDecode(request.body), {'archived': true});
        return archiveResponse.future;
      }
      return http.Response('{}', 404);
    });
    final dashboard = _dashboard(dashboardHttp);
    final gateway = _gateway(_healthyGatewayHttp());
    final repository = SessionRepository(dashboard, gateway);
    addTearDown(() {
      repository.close();
      dashboard.close();
    });

    await tester.pumpWidget(
      _host(
        SessionListScreen(
          connection: _connection(),
          connManager: await _manager(),
          clientOverride: gateway,
          repositoryOverride: repository,
        ),
      ),
    );
    const title = 'Archive rollback conversation';
    await _pumpUntil(tester, find.text(title));

    await tester.longPress(find.text(title));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Archive'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(archiveRequests, 1);
    expect(find.text(title), findsNothing);

    archiveResponse.complete(http.Response('{}', 500));
    await _pumpUntil(tester, find.text(title));
    await _pumpUntil(
      tester,
      find.text(
        'Archive state could not be confirmed on the server; '
        'the previous state was restored',
      ),
    );

    expect(pageRequests, 2);
    expect(find.text(title), findsWidgets);
    expect(
      find.text(
        'Archive state could not be confirmed on the server; '
        'the previous state was restored',
      ),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('remote archive 404 falls back locally with an honest label', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var archiveRequests = 0;
    final dashboardHttp = MockClient((request) async {
      if (request.method == 'GET' && request.url.path == '/api/sessions') {
        return _pageResponse(
          [_sessionRow(0, title: 'Local archive conversation')],
          total: 1,
          limit: 50,
          offset: 0,
        );
      }
      if (request.method == 'PATCH' &&
          request.url.path == '/api/sessions/session-0') {
        archiveRequests += 1;
        return http.Response('{}', 404);
      }
      return http.Response('{}', 404);
    });
    final dashboard = _dashboard(dashboardHttp);
    final gateway = _gateway(_healthyGatewayHttp());
    final repository = SessionRepository(dashboard, gateway);
    addTearDown(() {
      repository.close();
      dashboard.close();
    });

    await tester.pumpWidget(
      _host(
        SessionListScreen(
          connection: _connection(),
          connManager: await _manager(),
          clientOverride: gateway,
          repositoryOverride: repository,
        ),
      ),
    );
    const title = 'Local archive conversation';
    await _pumpUntil(tester, find.text(title));

    await tester.longPress(find.text(title));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Archive'));
    await tester.pumpAndSettle();

    expect(archiveRequests, 1);
    expect(find.text(title), findsNothing);
    expect(
      find.text(
        'Archived only on this device; the server cannot sync archive state',
      ),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const ValueKey('session-filter-archived')));
    await tester.pump();
    expect(find.text(title), findsWidgets);
    expect(tester.takeException(), isNull);
  });
}
