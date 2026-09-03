import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/screens/settings_screen.dart';
import 'package:hermes_android/core/services/connection_manager.dart';
import 'package:hermes_android/core/theme/app_theme.dart';
import 'package:hermes_android/l10n/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const secureChannel = MethodChannel(
    'plugins.it_nomads.com/flutter_secure_storage',
  );

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    final secureValues = <String, String>{};
    TestWidgetsFlutterBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(secureChannel, (call) async {
          final args = call.arguments is Map
              ? Map<Object?, Object?>.from(call.arguments as Map)
              : const <Object?, Object?>{};
          switch (call.method) {
            case 'write':
              secureValues[args['key'] as String] = args['value'] as String;
              return null;
            case 'read':
              return secureValues[args['key']];
            case 'readAll':
              return Map<String, String>.of(secureValues);
            case 'delete':
              secureValues.remove(args['key']);
              return null;
          }
          return null;
        });
  });

  tearDown(() {
    TestWidgetsFlutterBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(secureChannel, null);
  });

  Future<void> pumpActions(
    WidgetTester tester, {
    required bool readOnly,
    required VoidCallback onNormal,
    required VoidCallback onCron,
  }) => tester.pumpWidget(
    MaterialApp(
      locale: const Locale('es'),
      localizationsDelegates: Strings.localizationsDelegates,
      supportedLocales: Strings.supportedLocales,
      theme: AppTheme.fromId('dark'),
      home: Scaffold(
        body: HistoryCleanupActionList(
          readOnly: readOnly,
          clearingNormal: false,
          clearingCron: false,
          onClearNormal: onNormal,
          onClearCron: onCron,
        ),
      ),
    ),
  );

  testWidgets(
    'Ajustes descubre por separado conversaciones normales y resultados Cron',
    (tester) async {
      var normalTaps = 0;
      var cronTaps = 0;
      await pumpActions(
        tester,
        readOnly: false,
        onNormal: () => normalTaps++,
        onCron: () => cronTaps++,
      );

      expect(
        find.byKey(const ValueKey('history-cleanup-normal')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('history-cleanup-cron')),
        findsOneWidget,
      );
      final strings = Strings.of(
        tester.element(find.byType(HistoryCleanupActionList)),
      );
      expect(find.text(strings.setClearConvos), findsOneWidget);
      expect(find.text(strings.crnCleanupTitle), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('history-cleanup-normal')));
      await tester.tap(find.byKey(const ValueKey('history-cleanup-cron')));
      expect(normalTaps, 1);
      expect(cronTaps, 1);
    },
  );

  testWidgets('solo lectura desactiva ambos alcances destructivos', (
    tester,
  ) async {
    await pumpActions(
      tester,
      readOnly: true,
      onNormal: () => fail('normal no debe habilitarse'),
      onCron: () => fail('Cron no debe habilitarse'),
    );

    final normal = tester.widget<InkWell>(
      find.byKey(const ValueKey('history-cleanup-normal')),
    );
    final cron = tester.widget<InkWell>(
      find.byKey(const ValueKey('history-cleanup-cron')),
    );
    expect(normal.onTap, isNull);
    expect(cron.onTap, isNull);
  });

  testWidgets(
    'congela la instancia y bloquea doble toque mientras verifica App Lock',
    (tester) async {
      final manager = await ConnectionManager.create(
        await SharedPreferences.getInstance(),
      );
      final connectionA = SavedConnection(
        id: 'instance-a',
        label: 'Instancia A',
        host: '127.0.0.2',
        port: 8642,
        apiKey: 'key-a',
        kind: InstanceKind.vps,
      );
      final connectionB = SavedConnection(
        id: 'instance-b',
        label: 'Instancia B',
        host: '127.0.0.3',
        port: 8642,
        apiKey: 'key-b',
        kind: InstanceKind.vps,
      );

      final verification = Completer<bool>();
      var verificationCalls = 0;
      Widget sectionFor(SavedConnection connection) => MaterialApp(
        locale: const Locale('es'),
        localizationsDelegates: Strings.localizationsDelegates,
        supportedLocales: Strings.supportedLocales,
        theme: AppTheme.fromId('dark'),
        home: Scaffold(
          body: HistoryCleanupSection(
            key: ValueKey('history-cleanup-${connection.id}'),
            connection: connection,
            connManager: manager,
            verifyHistoryCleanupForTesting: () {
              verificationCalls++;
              return verification.future;
            },
          ),
        ),
      );

      await tester.pumpWidget(sectionFor(connectionA));

      await tester.tap(find.byKey(const ValueKey('history-cleanup-normal')));
      await tester.tap(find.byKey(const ValueKey('history-cleanup-normal')));
      await tester.tap(find.byKey(const ValueKey('history-cleanup-cron')));

      await tester.pumpWidget(sectionFor(connectionB));
      verification.complete(true);
      await tester.pump();
      await tester.pump();

      expect(verificationCalls, 1);
      expect(
        find.byKey(ValueKey('history-cleanup-${connectionB.id}')),
        findsOneWidget,
      );
      expect(find.byType(AlertDialog), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  test('ambos alcances conservan App Lock y reutilizan CronRepository', () {
    final source = File(
      'lib/core/screens/settings_screen.dart',
    ).readAsStringSync();

    expect(source, contains('authorizeHistoryCleanup('));
    expect(source, contains('previewConversationCleanup()'));
    expect(source, contains('deleteCronConversations(preview)'));
    expect(source, contains('scope: HistoryCleanupScope.normalConversations'));
    expect(source, contains('scope: HistoryCleanupScope.cronResults'));
  });

  test('vaciar conversaciones enlaza el perfil activo en cada scope', () {
    final source = File(
      'lib/core/screens/settings_screen.dart',
    ).readAsStringSync();
    final normalCleanup = source.substring(
      source.indexOf('Future<void> _clearNormal()'),
      source.indexOf('Future<void> _clearCron()'),
    );

    expect(normalCleanup, contains('activeProfileFor('));
    expect(normalCleanup, contains('clearProfileConversationsAndLocalState('));
    expect(normalCleanup, contains('profile: targetProfile'));
    expect(normalCleanup, contains('profile: profile'));
    expect(normalCleanup, contains('ChatDraftStore('));
    expect(normalCleanup, contains(').clear(targetConnection.id, sessionId'));
    expect(normalCleanup, contains('LocalTranscriptStore.clear('));
    expect(normalCleanup, contains('.deleteForChat('));
    expect(normalCleanup, isNot(contains('deleteForConnection(')));
  });
}
