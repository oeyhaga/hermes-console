import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/services/connection_manager.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('named profile prefixes every Gateway run REST operation', () async {
    final requests = <http.Request>[];
    final client = ApiClient(
      baseUrl: 'https://hermes.example',
      apiKey: 'test-key',
      httpClient: MockClient((request) async {
        requests.add(request);
        if (request.method == 'POST' && request.url.path.endsWith('/v1/runs')) {
          return http.Response(jsonEncode({'run_id': 'run/1'}), 202);
        }
        if (request.url.path.endsWith('/events')) {
          return http.Response('data: {"event":"run.completed"}\n\n', 200);
        }
        return http.Response(jsonEncode({'status': 'running'}), 200);
      }),
    );

    final runId = await client.startRun(input: 'do it', profile: 'team alpha');
    await client.getRun(runId, profile: 'team alpha');
    await client.resolveRunApproval(runId, 'once', profile: 'team alpha');
    await client.stopRun(runId, profile: 'team alpha');
    await client.streamRunEvents(
      runId,
      profile: 'team alpha',
      onEvent: (_) {},
      onDone: () {},
      onError: fail,
    );

    expect(
      requests.map((request) => request.url.toString()),
      everyElement(contains('/p/team%20alpha/')),
    );
    final createBody = jsonDecode(requests.first.body) as Map<String, dynamic>;
    expect(createBody.containsKey('profile'), isFalse);
    client.close();
  });

  test(
    'named profile prefixes session detail message delete and fork routes',
    () async {
      final requests = <http.Request>[];
      final client = ApiClient(
        baseUrl: 'https://hermes.example',
        apiKey: 'test-key',
        httpClient: MockClient((request) async {
          requests.add(request);
          if (request.url.path.endsWith('/messages')) {
            return http.Response(jsonEncode({'data': <Object>[]}), 200);
          }
          if (request.method == 'DELETE') {
            return http.Response(jsonEncode({'deleted': true}), 200);
          }
          return http.Response(
            jsonEncode({
              'session': {
                'id': 'session/1',
                'title': 'Scoped',
                'started_at': 1,
              },
            }),
            200,
          );
        }),
      );

      await client.getSession('session/1', profile: 'team alpha');
      await client.getMessages('session/1', profile: 'team alpha');
      await client.getMessagesPage('session/1', profile: 'team alpha');
      await client.deleteSession('session/1', profile: 'team alpha');
      await client.forkSession('session/1', profile: 'team alpha');

      expect(
        requests.map((request) => request.url.toString()),
        everyElement(contains('/p/team%20alpha/api/sessions/session%2F1')),
      );
      client.close();
    },
  );

  test(
    'default and empty profiles preserve unprefixed Gateway routes',
    () async {
      final requests = <http.Request>[];
      final client = ApiClient(
        baseUrl: 'https://hermes.example',
        apiKey: 'test-key',
        httpClient: MockClient((request) async {
          requests.add(request);
          return http.Response(jsonEncode({'status': 'running'}), 200);
        }),
      );

      await client.getRun('run-1');
      await client.getRun('run-2', profile: 'default');
      await client.getRun('run-3', profile: '  ');

      expect(requests.map((request) => request.url.path), [
        '/v1/runs/run-1',
        '/v1/runs/run-2',
        '/v1/runs/run-3',
      ]);
      client.close();
    },
  );
}
