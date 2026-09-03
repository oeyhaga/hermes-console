import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/models/cron_job.dart';
import 'package:hermes_android/core/services/connection_manager.dart';
import 'package:hermes_android/core/services/cron_repository.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  group('CronJob Desktop parity', () {
    test('explicit state wins and missing state falls back to enabled', () {
      expect(
        CronJob.fromJson({
          'id': 'running',
          'enabled': false,
          'state': 'running',
        }).state,
        CronJobState.running,
      );
      expect(
        CronJob.fromJson({'id': 'off', 'enabled': false}).state,
        CronJobState.disabled,
      );
      expect(
        CronJob.fromJson({'id': 'off', 'enabled': false}).isPaused,
        isTrue,
      );
      expect(
        CronJob.fromJson({'id': 'on', 'enabled': true}).state,
        CronJobState.scheduled,
      );
    });

    test('legacy disabled job resumes instead of pausing again', () async {
      final requests = <Uri>[];
      final client = DashboardClient(
        host: 'hermes.local',
        manualToken: 'token',
        httpClientOverride: MockClient((request) async {
          requests.add(request.url);
          return http.Response(
            jsonEncode({
              'id': 'legacy-off',
              'enabled': true,
              'state': 'scheduled',
            }),
            200,
          );
        }),
      );
      addTearDown(client.close);
      final repository = CronRepository(client, profile: 'default');
      final legacy = CronJob.fromJson({'id': 'legacy-off', 'enabled': false});

      await repository.pauseOrResume(legacy);

      expect(requests.single.path, '/api/cron/jobs/legacy-off/resume');
    });

    test('preserves scheduler delivery failure as an operator-visible error', () {
      final job = CronJob.fromJson({
        'id': 'delivery-failure',
        'last_status': 'delivery_failed',
        'last_delivery_error': 'destination unavailable',
      });

      expect(job.lastStatus, 'delivery_failed');
      expect(job.lastError, 'destination unavailable');
    });

    test('title follows name, prompt, script and id priority', () {
      expect(
        CronJob.fromJson({
          'id': 'a',
          'name': 'Named task',
          'prompt': 'Prompt',
        }).title,
        'Named task',
      );
      expect(
        CronJob.fromJson({'id': 'b', 'prompt': 'Prompt task'}).title,
        'Prompt task',
      );
      expect(
        CronJob.fromJson({
          'id': 'c',
          'no_agent': true,
          'script': 'backup.sh',
        }).isScriptOnly,
        isTrue,
      );
    });
  });

  test(
    'repository consumes dynamic targets, blueprints and run sessions',
    () async {
      final client = DashboardClient(
        host: 'hermes.local',
        manualToken: 'token',
        httpClientOverride: MockClient((request) async {
          switch (request.url.path) {
            case '/api/cron/delivery-targets':
              return http.Response(
                jsonEncode({
                  'targets': [
                    {'id': 'local', 'name': 'Local', 'home_target_set': true},
                    {
                      'id': 'telegram',
                      'name': 'Telegram',
                      'home_target_set': false,
                      'home_env_var': 'TELEGRAM_HOME_CHANNEL',
                    },
                  ],
                }),
                200,
              );
            case '/api/cron/blueprints':
              return http.Response(
                jsonEncode({
                  'blueprints': [
                    {
                      'key': 'morning-brief',
                      'title': 'Morning brief',
                      'description': 'Daily summary',
                      'fields': [
                        {
                          'name': 'time',
                          'type': 'time',
                          'label': 'Time',
                          'default': '09:00',
                          'options': [],
                          'optional': false,
                          'help': '',
                        },
                      ],
                    },
                  ],
                }),
                200,
              );
            case '/api/model/options':
              return http.Response(jsonEncode({'providers': []}), 200);
            case '/api/cron/jobs/job-1/runs':
              return http.Response(
                jsonEncode({
                  'runs': [
                    {
                      'id': 'cron_job-1_20260801_210000',
                      'title': 'Result',
                      'source': 'cron',
                      'message_count': 2,
                      'started_at': 1770000000,
                      'last_active': 1770000010,
                    },
                  ],
                }),
                200,
              );
            default:
              return http.Response('{}', 404);
          }
        }),
      );
      addTearDown(client.close);
      final repository = CronRepository(client, profile: 'default');

      final resources = await repository.editorResources();
      expect(resources.deliveryTargets.map((target) => target.id), [
        'local',
        'telegram',
      ]);
      expect(resources.deliveryTargets.last.homeTargetSet, isFalse);
      expect(resources.blueprints.single.key, 'morning-brief');
      expect(resources.blueprints.single.initialValues()['time'], '09:00');

      final runs = await repository.listRuns('job-1');
      expect(runs.available, isTrue);
      expect(runs.sessions.single.id, 'cron_job-1_20260801_210000');
      expect(runs.sessions.single.displayTitle, 'Result');
    },
  );

  test(
    'all profile scope is read-only query state, not mutation state',
    () async {
      final requests = <Uri>[];
      final client = DashboardClient(
        host: 'hermes.local',
        manualToken: 'token',
        httpClientOverride: MockClient((request) async {
          requests.add(request.url);
          if (request.method == 'GET' && request.url.path == '/api/cron/jobs') {
            return http.Response(
              jsonEncode([
                {
                  'id': 'all-job',
                  'name': 'All profiles',
                  'profile': 'research',
                  'enabled': true,
                },
              ]),
              200,
            );
          }
          if (request.method == 'POST' &&
              request.url.path == '/api/cron/jobs/all-job/pause') {
            return http.Response(
              jsonEncode({
                'id': 'all-job',
                'name': 'All profiles',
                'profile': 'research',
                'state': 'paused',
              }),
              200,
            );
          }
          return http.Response('{}', 404);
        }),
      );
      addTearDown(client.close);
      final repository = CronRepository(client, profile: 'work profile');

      final listing = await repository.listJobsForScope(CronProfileScope.all);
      expect(listing.usedLegacyActiveFallback, isFalse);
      expect(listing.jobs.single.profile, 'research');
      expect(requests.single.queryParameters['profile'], 'all');

      await repository.pauseOrResume(listing.jobs.single);
      expect(requests.last.queryParameters['profile'], 'work profile');
      expect(requests.last.queryParameters['profile'], isNot('all'));
    },
  );

  test(
    'all profile scope falls back to the active profile on legacy servers',
    () async {
      final requestedProfiles = <String?>[];
      final client = DashboardClient(
        host: 'hermes.local',
        manualToken: 'token',
        httpClientOverride: MockClient((request) async {
          if (request.method != 'GET' || request.url.path != '/api/cron/jobs') {
            return http.Response('{}', 404);
          }
          final profile = request.url.queryParameters['profile'];
          requestedProfiles.add(profile);
          if (profile == 'all') return http.Response('{}', 422);
          return http.Response(
            jsonEncode([
              {'id': 'legacy-job', 'profile': profile, 'enabled': true},
            ]),
            200,
          );
        }),
      );
      addTearDown(client.close);
      final repository = CronRepository(client, profile: 'default');

      final listing = await repository.listJobsForScope(CronProfileScope.all);

      expect(requestedProfiles, ['all', 'default']);
      expect(listing.usedLegacyActiveFallback, isTrue);
      expect(listing.jobs.single.id, 'legacy-job');
    },
  );

  group('Cron conversation cleanup', () {
    Map<String, dynamic> run(
      String id, {
      bool active = false,
      bool orphaned = false,
      bool pinned = false,
      bool archived = false,
      String? lineageRoot,
    }) => {
      'id': id,
      'source': 'cron',
      'title': 'Cron run',
      'message_count': 2,
      'started_at': 1770000000,
      'ended_at': active || orphaned ? null : 1770000010,
      'last_active': 1770000010,
      'is_active': active,
      'pinned': pinned,
      'archived': archived,
      '_lineage_root_id': ?lineageRoot,
    };

    test('incluye una ejecución huérfana que el servidor declara inactiva', () {
      final orphaned = Session.fromJson(
        run('cron_orphaned_20260804_165011', orphaned: true),
      );

      expect(orphaned.isActive, isFalse);
      expect(orphaned.endedAt, isNull);
      expect(cronSessionsSafeForCleanup([orphaned]), [orphaned]);
    });

    test('un servidor legacy sin is_active conserva la huérfana', () {
      final json = run('cron_legacy_orphan_20260804_165011', orphaned: true)
        ..remove('is_active');
      final orphaned = Session.fromJson(json);

      expect(orphaned.isActive, isTrue);
      expect(cronSessionsSafeForCleanup([orphaned]), isEmpty);
    });

    test(
      'preview pagina el perfil activo y excluye activas y fijadas',
      () async {
        final offsets = <String?>[];
        final client = DashboardClient(
          host: 'hermes.local',
          manualToken: 'token',
          httpClientOverride: MockClient((request) async {
            expect(request.method, 'GET');
            expect(request.url.path, '/api/sessions');
            expect(request.url.queryParameters['source'], 'cron');
            expect(request.url.queryParameters['archived'], 'include');
            expect(request.url.queryParameters['profile'], 'work profile');
            offsets.add(request.url.queryParameters['offset']);
            final offset = int.parse(request.url.queryParameters['offset']!);
            final rows = offset == 0
                ? List.generate(
                    100,
                    (index) => run('cron_job_${index}_20260807_090000'),
                  )
                : [
                    run('cron_active_20260807_100000', active: true),
                    run('cron_pinned_20260807_100100', pinned: true),
                    run('cron_archived_20260807_100200', archived: true),
                  ];
            return http.Response(
              jsonEncode({
                'sessions': rows,
                'total': 103,
                'limit': 100,
                'offset': offset,
              }),
              200,
            );
          }),
        );
        addTearDown(client.close);

        final preview = await CronRepository(
          client,
          profile: 'work profile',
        ).previewConversationCleanup();

        expect(offsets, ['0', '100']);
        expect(preview.count, 101);
        expect(
          preview.sessions.map((session) => session.id),
          contains('cron_archived_20260807_100200'),
        );
        expect(
          preview.sessions.map((session) => session.id),
          isNot(contains('cron_active_20260807_100000')),
        );
        expect(
          preview.sessions.map((session) => session.id),
          isNot(contains('cron_pinned_20260807_100100')),
        );
      },
    );

    test('un total incompatible falla antes del primer delete', () async {
      var deleteCalls = 0;
      final previewSession = Session.fromJson(
        run('cron_mismatch_20260807_090000'),
      );
      final client = DashboardClient(
        host: 'hermes.local',
        manualToken: 'token',
        httpClientOverride: MockClient((request) async {
          if (request.method == 'GET' && request.url.path == '/api/sessions') {
            return http.Response(
              jsonEncode({
                'sessions': [run(previewSession.id)],
                'total': 2,
              }),
              200,
            );
          }
          if (request.method == 'POST' || request.method == 'DELETE') {
            deleteCalls++;
            return http.Response(jsonEncode({'ok': true, 'deleted': 1}), 200);
          }
          return http.Response('{}', 404);
        }),
      );
      addTearDown(client.close);
      final repository = CronRepository(client, profile: 'default');

      await expectLater(
        repository.deleteCronConversations(
          CronConversationCleanupPreview([previewSession]),
        ),
        throwsA(isA<FormatException>()),
      );
      expect(deleteCalls, 0);
    });

    test('revalida y preserva activas fijadas y ejecuciones nuevas', () async {
      final activeId = 'cron_active_after_preview_20260807_090000';
      final pinnedId = 'cron_pinned_after_preview_20260807_090100';
      final archivedId = 'cron_archived_20260807_090200';
      final newRunId = 'cron_new_20260807_110000';
      final postedIds = <String>[];
      final requestedPaths = <String>[];
      var deleted = false;
      final client = DashboardClient(
        host: 'hermes.local',
        manualToken: 'token',
        httpClientOverride: MockClient((request) async {
          requestedPaths.add(request.url.path);
          if (request.method == 'GET' && request.url.path == '/api/sessions') {
            final rows = [
              run(activeId, active: true),
              run(pinnedId, pinned: true),
              if (!deleted) run(archivedId, archived: true),
              run(newRunId),
            ];
            return http.Response(
              jsonEncode({'sessions': rows, 'total': rows.length}),
              200,
            );
          }
          if (request.method == 'POST' &&
              request.url.path == '/api/sessions/bulk-delete') {
            final body = jsonDecode(request.body) as Map<String, dynamic>;
            postedIds.addAll((body['ids'] as List<dynamic>).cast<String>());
            deleted = true;
            return http.Response(
              jsonEncode({'ok': true, 'deleted': postedIds.length}),
              200,
            );
          }
          return http.Response('{}', 404);
        }),
      );
      addTearDown(client.close);
      final repository = CronRepository(client, profile: 'default');
      final preview = CronConversationCleanupPreview([
        Session.fromJson(run(activeId)),
        Session.fromJson(run(pinnedId)),
        Session.fromJson(run(archivedId, archived: true)),
      ]);

      final result = await repository.deleteCronConversations(preview);

      expect(postedIds, [archivedId]);
      expect(postedIds, isNot(contains(newRunId)));
      expect(result.requested, 3);
      expect(result.deleted, 1);
      expect(result.preserved, 2);
      expect(
        requestedPaths.any((path) => path.startsWith('/api/cron/jobs')),
        isFalse,
      );
    });

    test('pagina y parte más de 500 IDs sin tocar cron jobs', () async {
      final rows = List.generate(
        501,
        (index) => run('cron_bulk_${index}_20260807_090000'),
      );
      final preview = CronConversationCleanupPreview(
        rows.map(Session.fromJson),
      );
      final sequence = <String>[];
      final postedBatches = <List<String>>[];
      var deleted = false;
      final client = DashboardClient(
        host: 'hermes.local',
        manualToken: 'token',
        httpClientOverride: MockClient((request) async {
          if (request.method == 'GET' && request.url.path == '/api/sessions') {
            final offset = int.parse(request.url.queryParameters['offset']!);
            sequence.add('GET:$offset');
            final page = deleted
                ? const <Map<String, dynamic>>[]
                : rows.skip(offset).take(100).toList(growable: false);
            return http.Response(
              jsonEncode({
                'sessions': page,
                'total': deleted ? 0 : rows.length,
              }),
              200,
            );
          }
          if (request.method == 'POST' &&
              request.url.path == '/api/sessions/bulk-delete') {
            final body = jsonDecode(request.body) as Map<String, dynamic>;
            final ids = (body['ids'] as List<dynamic>).cast<String>();
            sequence.add('POST:${ids.length}');
            postedBatches.add(ids);
            deleted = true;
            return http.Response(
              jsonEncode({'ok': true, 'deleted': ids.length}),
              200,
            );
          }
          return http.Response('{}', 404);
        }),
      );
      addTearDown(client.close);

      final result = await CronRepository(
        client,
        profile: 'default',
      ).deleteCronConversations(preview);

      expect(sequence.first, 'GET:0');
      expect(postedBatches.map((batch) => batch.length), [500, 1]);
      expect(result.deleted, 501);
      expect(
        sequence.any((entry) => entry.contains('/api/cron/jobs')),
        isFalse,
      );
    });

    test(
      'bulk delete limpia solo sesiones y conserva las programaciones',
      () async {
        final requests = <http.Request>[];
        var inventoryReads = 0;
        var deleted = false;
        final client = DashboardClient(
          host: 'hermes.local',
          manualToken: 'token',
          httpClientOverride: MockClient((request) async {
            requests.add(request);
            if (request.method == 'POST' &&
                request.url.path == '/api/sessions/bulk-delete') {
              deleted = true;
              return http.Response(jsonEncode({'ok': true, 'deleted': 2}), 200);
            }
            if (request.method == 'GET' &&
                request.url.path == '/api/sessions') {
              inventoryReads++;
              final rows = deleted
                  ? const <Map<String, dynamic>>[]
                  : [
                      run('cron_a_20260807_090000'),
                      run('cron_b_20260807_090100'),
                    ];
              return http.Response(
                jsonEncode({'sessions': rows, 'total': rows.length}),
                200,
              );
            }
            return http.Response('{}', 404);
          }),
        );
        addTearDown(client.close);
        final repository = CronRepository(client, profile: 'default');
        final preview = CronConversationCleanupPreview([
          Session.fromJson(run('cron_a_20260807_090000')),
          Session.fromJson(run('cron_b_20260807_090100')),
        ]);

        final result = await repository.deleteCronConversations(preview);

        expect(result.requested, 2);
        expect(result.deleted, 2);
        expect(result.preserved, 0);
        expect(inventoryReads, 2);
        final bulk = requests.singleWhere(
          (request) => request.url.path == '/api/sessions/bulk-delete',
        );
        expect(jsonDecode(bulk.body), {
          'ids': ['cron_a_20260807_090000', 'cron_b_20260807_090100'],
          'profile': 'default',
        });
        expect(
          requests.any(
            (request) => request.url.path.contains('/api/cron/jobs'),
          ),
          isFalse,
        );
      },
    );

    test('sigue la compactación sin alcanzar una ejecución nueva', () async {
      final deletedBatches = <List<dynamic>>[];
      var reads = 0;
      final rootId = 'cron_job_20260807_090000';
      final tipId = 'cron_job_20260807_090000_tip';
      final client = DashboardClient(
        host: 'hermes.local',
        manualToken: 'token',
        httpClientOverride: MockClient((request) async {
          if (request.method == 'POST') {
            final body = jsonDecode(request.body) as Map<String, dynamic>;
            deletedBatches.add(body['ids'] as List<dynamic>);
            return http.Response(jsonEncode({'ok': true, 'deleted': 1}), 200);
          }
          reads++;
          final rows = switch (reads) {
            1 => [
              run(tipId, lineageRoot: rootId),
              run('cron_new_20260807_110000'),
            ],
            2 => [
              run(rootId, lineageRoot: rootId),
              run('cron_new_20260807_110000'),
            ],
            _ => [run('cron_new_20260807_110000')],
          };
          return http.Response(
            jsonEncode({'sessions': rows, 'total': rows.length}),
            200,
          );
        }),
      );
      addTearDown(client.close);
      final repository = CronRepository(client, profile: 'default');
      final preview = CronConversationCleanupPreview([
        Session.fromJson(run(tipId, lineageRoot: rootId)),
      ]);

      final result = await repository.deleteCronConversations(preview);

      expect(deletedBatches, [
        [tipId],
        [rootId],
      ]);
      expect(result.deleted, 1);
      expect(result.preserved, 0);
    });

    test('servidor legacy degrada a DELETE individual idempotente', () async {
      final methods = <String>[];
      final paths = <String>[];
      var deleted = false;
      final client = DashboardClient(
        host: 'hermes.local',
        manualToken: 'token',
        httpClientOverride: MockClient((request) async {
          methods.add(request.method);
          paths.add(request.url.path);
          if (request.method == 'POST') return http.Response('{}', 405);
          if (request.method == 'DELETE') {
            deleted = true;
            return http.Response('{}', 200);
          }
          final rows = deleted
              ? const <Map<String, dynamic>>[]
              : [run('cron_legacy_20260807_090000')];
          return http.Response(
            jsonEncode({'sessions': rows, 'total': rows.length}),
            200,
          );
        }),
      );
      addTearDown(client.close);
      final repository = CronRepository(client, profile: 'work profile');
      final preview = CronConversationCleanupPreview([
        Session.fromJson(run('cron_legacy_20260807_090000')),
      ]);

      final result = await repository.deleteCronConversations(preview);

      expect(methods, ['GET', 'POST', 'DELETE', 'GET']);
      expect(paths, [
        '/api/sessions',
        '/api/sessions/bulk-delete',
        '/api/sessions/cron_legacy_20260807_090000',
        '/api/sessions',
      ]);
      expect(result.deleted, 1);
    });
  });
}
