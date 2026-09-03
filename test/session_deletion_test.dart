import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/services/connection_manager.dart';
import 'package:hermes_android/core/services/session_deletion.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

Session cronSession(String id) =>
    Session.fromJson({'id': id, 'title': 'Scheduled report', 'source': 'cron'});

Session childSession(String id, String parentId) => Session.fromJson({
  'id': id,
  'title': null,
  'source': 'cron',
  'parent_session_id': parentId,
});

void main() {
  test('las cuatro superficies delegan en el coordinador compartido', () {
    const paths = [
      'lib/core/screens/home_dashboard_screen.dart',
      'lib/core/screens/session_list_screen.dart',
      'lib/core/screens/session_detail_screen.dart',
      'lib/core/screens/chat_screen.dart',
    ];
    for (final path in paths) {
      final source = File(path).readAsStringSync();
      expect(
        source,
        contains('deleteSessionWithResolvedLineage('),
        reason: path,
      );
      expect(
        source,
        isNot(contains('deleteSessionWithLinkedCron(')),
        reason: '$path no debe saltarse la resolución compartida',
      );
      expect(
        source,
        contains('sessionDeletionFailureMessage('),
        reason: '$path debe presentar fallos mediante el helper ARB común',
      );
      expect(
        source,
        isNot(contains(r'${result.error}')),
        reason: '$path no debe filtrar errores técnicos a la UI',
      );
      expect(
        source,
        isNot(contains('DeleteFailed(e.toString())')),
        reason: '$path no debe mostrar excepciones de transporte sin tipar',
      );
      expect(
        source,
        contains('cronDeletion:'),
        reason: '$path debe declarar si conserva o elimina la programación',
      );
    }

    final chat = File('lib/core/screens/chat_screen.dart').readAsStringSync();
    expect(chat, isNot(contains('deleteSession: client.deleteSession')));
    expect(chat, contains('final ownerProfile = _chat.sessionProfile;'));
    expect(
      chat,
      matches(
        RegExp(
          r'client\.getSessions\(\s*includeChildren: includeChildren,\s*profile: ownerProfile,',
        ),
      ),
    );
    expect(
      chat,
      contains('client.deleteSession(sessionId, profile: ownerProfile)'),
    );
    expect(chat, contains('remoteSessionId: _chat.serverSessionId'));
    expect(chat, contains('localRecoverySessionId: widget.session.id'));
    expect(chat, contains('clearLocalRecovery: _clearDeletedChatRecovery'));

    final home = File(
      'lib/core/screens/home_dashboard_screen.dart',
    ).readAsStringSync();
    expect(home, isNot(contains('deleteSession: client.deleteSession')));
    expect(
      home,
      contains('final ownerProfile = Session.profileOwner(session.profile);'),
    );
    expect(
      home,
      contains('client.deleteSession(sessionId, profile: ownerProfile)'),
    );
    expect(home, contains('profile: ownerProfile'));

    final detail = File(
      'lib/core/screens/session_detail_screen.dart',
    ).readAsStringSync();
    expect(
      detail,
      contains('final ownerProfile = Session.profileOwner(_session.profile);'),
    );
    expect(detail, contains('profile: ownerProfile'));

    final list = File(
      'lib/core/screens/session_list_screen.dart',
    ).readAsStringSync();
    expect(
      list,
      matches(
        RegExp(
          r'_client\.getSessions\(\s*includeChildren: includeChildren,\s*profile: ownerProfile,',
        ),
      ),
    );

    final service = File(
      'lib/core/services/session_deletion.dart',
    ).readAsStringSync();
    expect(service, isNot(contains('No se pudo identificar el cron')));
    expect(service, isNot(contains('No hay acceso al gestor de cron')));
  });

  test('borrado individual distingue confirmación, rechazo y error', () async {
    final deleted = await deleteRemoteSession(
      'chat-ok',
      delete: (_) async => true,
    );
    final rejected = await deleteRemoteSession(
      'cron-active',
      delete: (_) async => false,
    );
    final failed = await deleteRemoteSession(
      'chat-error',
      delete: (_) async => throw StateError('offline'),
    );

    expect(deleted.status, RemoteSessionDeleteStatus.deleted);
    expect(rejected.status, RemoteSessionDeleteStatus.rejected);
    expect(failed.status, RemoteSessionDeleteStatus.failed);
    expect(failed.error, isA<StateError>());
  });

  test(
    'borrado total no cuenta deleted=false como conversación borrada',
    () async {
      final result = await deleteRemoteSessions(
        const ['chat-ok', 'cron-active', 'chat-error'],
        delete: (id) async => switch (id) {
          'chat-ok' => true,
          'cron-active' => false,
          _ => throw StateError('offline'),
        },
      );

      expect(result.deleted, 1);
      expect(result.rejected, 1);
      expect(result.failed, 1);
      expect(result.allDeleted, isFalse);
    },
  );

  test(
    'borrado total solo confirma éxito cuando todas fueron eliminadas',
    () async {
      final result = await deleteRemoteSessions(const [
        'chat-a',
        'cron-b',
      ], delete: (_) async => true);

      expect(result.deleted, 2);
      expect(result.rejected, 0);
      expect(result.failed, 0);
      expect(result.allDeleted, isTrue);
    },
  );

  test(
    'la autorización falla cerrada antes de App Lock en solo lectura',
    () async {
      var verifications = 0;

      final readOnly = await authorizeHistoryCleanup(
        readOnly: true,
        verifyAppLock: () async {
          verifications++;
          return true;
        },
      );
      final rejected = await authorizeHistoryCleanup(
        readOnly: false,
        verifyAppLock: () async {
          verifications++;
          return false;
        },
      );
      final accepted = await authorizeHistoryCleanup(
        readOnly: false,
        verifyAppLock: () async {
          verifications++;
          return true;
        },
      );

      expect(readOnly, isFalse);
      expect(rejected, isFalse);
      expect(accepted, isTrue);
      expect(verifications, 2);
    },
  );

  test('la invalidación publica conexión y alcance exactos', () async {
    final bus = HistoryCleanupInvalidationBus();
    addTearDown(bus.close);
    final events = <HistoryCleanupInvalidation>[];
    final subscription = bus.events.listen(events.add);
    addTearDown(subscription.cancel);

    bus.publish(
      connectionId: 'qa',
      scope: HistoryCleanupScope.normalConversations,
    );
    bus.publish(connectionId: 'qa', scope: HistoryCleanupScope.cronResults);

    expect(events.map((event) => event.connectionId), ['qa', 'qa']);
    expect(events.map((event) => event.scope), [
      HistoryCleanupScope.normalConversations,
      HistoryCleanupScope.cronResults,
    ]);
  });

  test('vaciar limpia borradores aunque falle el listado remoto', () async {
    var draftsCalled = 0;
    var transcriptsCalled = 0;
    var outboxCalled = 0;

    final result = await clearConversationsAndLocalState(
      loadSessions: ({bool includeChildren = false}) async {
        expect(includeChildren, isTrue);
        throw StateError('offline');
      },
      deleteSession: (_) async => true,
      clearDrafts: () async {
        draftsCalled++;
        return 2;
      },
      clearTranscripts: () async {
        transcriptsCalled++;
        return 1;
      },
      clearOutbox: () async {
        outboxCalled++;
        return 1;
      },
    );

    expect(result.remote, isNull);
    expect(result.remoteListError, isA<StateError>());
    expect(result.drafts.removed, 2);
    expect(result.transcripts.removed, 1);
    expect(result.outbox.removed, 1);
    expect(draftsCalled, 1);
    expect(transcriptsCalled, 1);
    expect(outboxCalled, 1);
    expect(result.allSucceeded, isFalse);
  });

  test('vaciar conserva informes y aísla fallos locales', () async {
    final deleted = <String>[];
    final result = await clearConversationsAndLocalState(
      loadSessions: ({bool includeChildren = false}) async => [
        Session.fromJson({'id': 'chat-a', 'source': 'mobile'}),
        cronSession('cron_daily_20260721_120000'),
      ],
      deleteSession: (id) async {
        deleted.add(id);
        return true;
      },
      clearDrafts: () async => throw StateError('keystore'),
      clearTranscripts: () async => 2,
      clearOutbox: () async => 0,
    );

    expect(deleted, ['chat-a']);
    expect(result.remote?.deleted, 1);
    expect(result.drafts.succeeded, isFalse);
    expect(result.transcripts.removed, 2);
    expect(result.outbox.succeeded, isTrue);
    expect(result.localFailureCount, 1);
  });

  test('borra primero el cron vinculado y después su conversación', () async {
    final calls = <String>[];
    final result = await deleteSessionWithLinkedCron(
      cronSession('cron_job_with_underscores_20260715_214800'),
      cronDeletion: LinkedCronDeletionMode.deleteSchedule,
      deleteCronJob: (id) async => calls.add('cron:$id'),
      deleteSession: (id) async {
        calls.add('session:$id');
        return true;
      },
    );

    expect(result.status, LinkedSessionDeleteStatus.deleted);
    expect(result.cronDeleted, isTrue);
    expect(calls, [
      'cron:job_with_underscores',
      'session:cron_job_with_underscores_20260715_214800',
    ]);
  });

  test('resuelve la raíz cron desde la última continuación', () {
    final root = cronSession('cron_job123_20260715_214800');
    final child = childSession('compact-1', root.id);
    final leaf = childSession('compact-2', child.id);

    expect(sessionLineageRoot(leaf, [root, child, leaf]), same(root));
    expect(sessionLineageRoot(leaf, [root, child, leaf]).cronJobId, 'job123');
  });

  test(
    'el contexto compartido fuerza includeChildren y conserva raíz y linaje',
    () async {
      final root = cronSession('cron_job123_20260715_214800');
      final child = childSession('compact-1', root.id);
      final leaf = childSession('compact-2', child.id);
      bool? requestedIncludeChildren;

      final context = await resolveSessionDeletionContext(
        leaf,
        loadSessions: ({bool includeChildren = false}) async {
          requestedIncludeChildren = includeChildren;
          return [root, child, leaf];
        },
      );

      expect(requestedIncludeChildren, isTrue);
      expect(context.target, same(root));
      expect(context.lineage, [root, child, leaf]);
      expect(context.remoteSessionId, root.id);
      expect(context.localRecoverySessionId, leaf.id);
    },
  );

  test(
    'borrado de linaje conserva include_children=true en el wire Gateway',
    () async {
      final requests = <http.Request>[];
      final root = cronSession('cron_wire_20260807_001500');
      final leaf = childSession('leaf-wire', root.id);
      final client = ApiClient(
        baseUrl: 'http://hermes.local:8642',
        apiKey: 'gateway-key',
        httpClient: MockClient((request) async {
          requests.add(request);
          if (request.method == 'GET' && request.url.path == '/api/sessions') {
            return http.Response(
              jsonEncode({
                'data': [
                  {
                    'id': root.id,
                    'title': root.title,
                    'source': root.source,
                    'message_count': 1,
                  },
                  {
                    'id': leaf.id,
                    'title': leaf.title,
                    'source': leaf.source,
                    'message_count': 1,
                    'parent_session_id': root.id,
                  },
                ],
              }),
              200,
            );
          }
          if (request.method == 'DELETE' &&
              request.url.path.startsWith('/api/sessions/')) {
            return http.Response(jsonEncode({'deleted': true}), 200);
          }
          return http.Response('not found', 404);
        }),
      );
      addTearDown(client.close);

      final result = await deleteSessionWithResolvedLineage(
        leaf,
        loadSessions: client.getSessions,
        deleteSession: client.deleteSession,
      );

      expect(result.status, LinkedSessionDeleteStatus.deleted);
      expect(requests.map((request) => request.method), [
        'GET',
        'DELETE',
        'DELETE',
      ]);
      expect(requests.first.url.queryParameters, {
        'limit': '200',
        'include_children': 'true',
      });
      expect(requests[1].url.path, '/api/sessions/leaf-wire');
      expect(requests.last.url.path, '/api/sessions/${root.id}');
    },
  );

  test('un fetch de linaje fallido se convierte en fallo controlado', () async {
    final result = await deleteSessionWithResolvedLineage(
      cronSession('cron_job123_20260715_214800'),
      loadSessions: ({bool includeChildren = false}) async {
        expect(includeChildren, isTrue);
        throw StateError('offline');
      },
      deleteSession: (_) async => true,
      deleteCronJob: (_) async {},
    );

    expect(result.status, LinkedSessionDeleteStatus.sessionDeleteFailed);
    expect(result.failure?.code, SessionDeletionFailureCode.lineageUnavailable);
    expect(result.failure?.cause, isA<StateError>());
  });

  test(
    'cron sin vínculo o gestor devuelve códigos estables sin copy',
    () async {
      final missingLink = await deleteSessionWithLinkedCron(
        cronSession('legacy-cron-session'),
        cronDeletion: LinkedCronDeletionMode.deleteSchedule,
        deleteSession: (_) async => true,
      );
      final missingManager = await deleteSessionWithLinkedCron(
        cronSession('cron_job123_20260715_214800'),
        cronDeletion: LinkedCronDeletionMode.deleteSchedule,
        deleteSession: (_) async => true,
      );

      expect(
        missingLink.failure?.code,
        SessionDeletionFailureCode.missingCronJobId,
      );
      expect(
        missingManager.failure?.code,
        SessionDeletionFailureCode.cronManagerUnavailable,
      );
      expect(missingLink.failure?.cause, isNull);
      expect(missingManager.failure?.cause, isNull);
    },
  );

  test('borra una cadena cron de las hojas a la raíz', () async {
    final root = cronSession('cron_job123_20260715_214800');
    final child = childSession('compact-1', root.id);
    final leaf = childSession('compact-2', child.id);
    final calls = <String>[];

    final result = await deleteSessionWithLinkedCron(
      root,
      lineage: [root, child, leaf],
      cronDeletion: LinkedCronDeletionMode.deleteSchedule,
      deleteCronJob: (id) async => calls.add('cron:$id'),
      deleteSession: (id) async {
        calls.add('session:$id');
        return true;
      },
    );

    expect(result.status, LinkedSessionDeleteStatus.deleted);
    expect(calls, [
      'cron:job123',
      'session:compact-2',
      'session:compact-1',
      'session:${root.id}',
    ]);
  });

  test('si no puede detener el cron conserva la conversación', () async {
    var sessionDeleteCalled = false;
    final result = await deleteSessionWithLinkedCron(
      cronSession('cron_job123_20260715_214800'),
      cronDeletion: LinkedCronDeletionMode.deleteSchedule,
      deleteCronJob: (_) async => throw StateError('dashboard offline'),
      deleteSession: (_) async {
        sessionDeleteCalled = true;
        return true;
      },
    );

    expect(result.status, LinkedSessionDeleteStatus.cronDeleteFailed);
    expect(result.cronDeleted, isFalse);
    expect(sessionDeleteCalled, isFalse);
  });

  test(
    'borrar solo el chat conserva el cron incluso si conoce su id',
    () async {
      final scheduled = cronSession('cron_job123_20260715_214800');
      final calls = <String>[];

      final result = await deleteSessionWithResolvedLineage(
        scheduled,
        loadSessions: ({bool includeChildren = false}) async => [scheduled],
        deleteCronJob: (id) async => calls.add('cron:$id'),
        deleteSession: (id) async {
          calls.add('session:$id');
          return true;
        },
      );

      expect(result.status, LinkedSessionDeleteStatus.deleted);
      expect(result.cronDeleted, isFalse);
      expect(calls, ['session:${scheduled.id}']);
    },
  );

  test('borrar solo el chat funciona también con un cron legacy', () async {
    final legacy = cronSession('legacy-cron-session');
    final calls = <String>[];

    final result = await deleteSessionWithResolvedLineage(
      legacy,
      loadSessions: ({bool includeChildren = false}) async => [legacy],
      deleteCronJob: (id) async => calls.add('cron:$id'),
      deleteSession: (id) async {
        calls.add('session:$id');
        return true;
      },
    );

    expect(result.status, LinkedSessionDeleteStatus.deleted);
    expect(result.cronDeleted, isFalse);
    expect(calls, ['session:legacy-cron-session']);
  });

  test(
    'separa el id remoto de la clave local y limpia solo tras éxito',
    () async {
      final local = Session.fromJson({
        'id': 'mob-local',
        'title': 'Nuevo chat',
        'source': 'mobile',
      });
      final remoteDeletes = <String>[];
      final localCleanups = <String>[];

      final result = await deleteSessionWithResolvedLineage(
        local,
        remoteSessionId: 'desktop-remote',
        loadSessions: ({bool includeChildren = false}) async => const [],
        deleteSession: (id) async {
          remoteDeletes.add(id);
          return true;
        },
        clearLocalRecovery: (id) async => localCleanups.add(id),
      );

      expect(result.status, LinkedSessionDeleteStatus.deleted);
      expect(remoteDeletes, ['desktop-remote']);
      expect(localCleanups, ['mob-local']);
    },
  );

  test('rechazo o fallo remoto no limpia la recuperación local', () async {
    final local = Session.fromJson({
      'id': 'mob-local',
      'title': 'Nuevo chat',
      'source': 'mobile',
    });
    final localCleanups = <String>[];

    final rejected = await deleteSessionWithResolvedLineage(
      local,
      remoteSessionId: 'desktop-rejected',
      loadSessions: ({bool includeChildren = false}) async => const [],
      deleteSession: (_) async => false,
      clearLocalRecovery: (id) async => localCleanups.add(id),
    );
    final failed = await deleteSessionWithResolvedLineage(
      local,
      remoteSessionId: 'desktop-failed',
      loadSessions: ({bool includeChildren = false}) async => const [],
      deleteSession: (_) async => throw StateError('offline'),
      clearLocalRecovery: (id) async => localCleanups.add(id),
    );

    expect(rejected.status, LinkedSessionDeleteStatus.sessionRejected);
    expect(failed.status, LinkedSessionDeleteStatus.sessionDeleteFailed);
    expect(localCleanups, isEmpty);
  });

  test('informa si el cron se borró pero el servidor retuvo el chat', () async {
    final result = await deleteSessionWithLinkedCron(
      cronSession('cron_job123_20260715_214800'),
      cronDeletion: LinkedCronDeletionMode.deleteSchedule,
      deleteCronJob: (_) async {},
      deleteSession: (_) async => false,
    );

    expect(result.status, LinkedSessionDeleteStatus.sessionRejected);
    expect(result.cronDeleted, isTrue);
  });

  test('no borra una sesión cron mientras el agente aún escribe', () async {
    final calls = <String>[];
    final now = DateTime.now().millisecondsSinceEpoch / 1000;
    final active = Session.fromJson({
      'id': 'cron_job123_20260716_120000',
      'title': 'Running report',
      'source': 'cron',
      'started_at': now,
      'ended_at': null,
    });

    final result = await deleteSessionWithLinkedCron(
      active,
      cronDeletion: LinkedCronDeletionMode.deleteSchedule,
      deleteCronJob: (id) async => calls.add('cron:$id'),
      deleteSession: (id) async {
        calls.add('session:$id');
        return true;
      },
    );

    expect(result.status, LinkedSessionDeleteStatus.sessionRejected);
    expect(result.cronDeleted, isTrue);
    expect(calls, ['cron:job123']);
  });

  test('limpieza normal excluye siempre Cron y sesiones tool', () {
    final normal = Session.fromJson({
      'id': 'chat-normal',
      'title': 'Normal',
      'source': 'chat',
    });
    final cron = cronSession('cron_job123_20260715_214800');
    final tool = Session.fromJson({
      'id': 'tool-run',
      'title': 'Tool runtime',
      'source': 'tool',
    });

    expect(sessionsSafeForBulkDelete([normal, cron, tool]), [normal]);
  });

  test('vaciar un perfil nombra cada operación remota y local', () async {
    final calls = <String>[];
    final summary = await clearProfileConversationsAndLocalState(
      profile: 'team_alpha',
      loadSessions:
          ({bool includeChildren = false, required String profile}) async {
            calls.add('list:$profile:$includeChildren');
            return [
              Session.fromJson({
                'id': 'chat-1',
                'title': 'Scoped',
                'source': 'mobile',
              }),
            ];
          },
      deleteSession: (sessionId, {required String profile}) async {
        calls.add('delete:$profile:$sessionId');
        return true;
      },
      clearDraft: (sessionId, {required String profile}) async {
        calls.add('draft:$profile:$sessionId');
        return 1;
      },
      clearTranscript: (sessionId, {required String profile}) async {
        calls.add('transcript:$profile:$sessionId');
        return 1;
      },
      clearOutbox: (sessionId, {required String profile}) async {
        calls.add('outbox:$profile:$sessionId');
        return 1;
      },
    );

    expect(calls, [
      'list:team_alpha:true',
      'delete:team_alpha:chat-1',
      'draft:team_alpha:chat-1',
      'transcript:team_alpha:chat-1',
      'outbox:team_alpha:chat-1',
    ]);
    expect(summary.remote?.deleted, 1);
    expect(summary.drafts.removed, 1);
    expect(summary.transcripts.removed, 1);
    expect(summary.outbox.removed, 1);
  });

  test('vaciar el perfil vacío conserva el owner default', () async {
    final owners = <String>[];
    final summary = await clearProfileConversationsAndLocalState(
      profile: '',
      loadSessions:
          ({bool includeChildren = false, required String profile}) async {
            owners.add(profile);
            return [
              Session.fromJson({
                'id': 'default-chat',
                'title': 'Default',
                'source': 'mobile',
              }),
            ];
          },
      deleteSession: (_, {required String profile}) async {
        owners.add(profile);
        return true;
      },
      clearDraft: (_, {required String profile}) async {
        owners.add(profile);
        return 0;
      },
      clearTranscript: (_, {required String profile}) async {
        owners.add(profile);
        return 0;
      },
      clearOutbox: (_, {required String profile}) async {
        owners.add(profile);
        return 0;
      },
    );

    expect(owners, List.filled(5, 'default'));
    expect(summary.allSucceeded, isTrue);
  });
}
