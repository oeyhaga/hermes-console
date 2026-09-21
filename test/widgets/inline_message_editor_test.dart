import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/theme/app_theme.dart';
import 'package:hermes_android/core/widgets/inline_message_editor.dart';
import 'package:hermes_android/l10n/app_localizations.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final brightness in [Brightness.light, Brightness.dark]) {
    for (final locale in const [Locale('es'), Locale('en')]) {
      testWidgets(
        'inline editor fits 320dp at 2x in ${brightness.name} ${locale.languageCode}',
        (tester) async {
          tester.view
            ..physicalSize = const Size(320, 640)
            ..devicePixelRatio = 1;
          addTearDown(tester.view.reset);
          String? saved;
          var cancelled = false;

          await tester.pumpWidget(
            MaterialApp(
              locale: locale,
              localizationsDelegates: Strings.localizationsDelegates,
              supportedLocales: Strings.supportedLocales,
              theme: brightness == Brightness.light
                  ? AppTheme.hermesRedLight
                  : AppTheme.hermesRedDark,
              home: MediaQuery(
                data: const MediaQueryData(
                  size: Size(320, 640),
                  textScaler: TextScaler.linear(2),
                  disableAnimations: true,
                ),
                child: Scaffold(
                  body: SingleChildScrollView(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: brightness == Brightness.light
                              ? Colors.grey.shade200
                              : Colors.grey.shade900,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: InlineMessageEditor(
                            initialText: 'Texto original',
                            onCancel: () => cancelled = true,
                            onSave: (value) => saved = value,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
          await tester.pump();

          final field = find.byKey(
            const ValueKey('inline-message-editor-field'),
          );
          expect(field, findsOneWidget);
          final editable = tester.widget<EditableText>(
            find.descendant(of: field, matching: find.byType(EditableText)),
          );
          expect(
            editable.controller.selection.baseOffset,
            'Texto original'.length,
          );
          expect(tester.takeException(), isNull);

          final saveButton = find.byKey(
            const ValueKey('inline-message-editor-save'),
          );
          expect(tester.widget<IconButton>(saveButton).onPressed, isNull);
          expect(
            find.byTooltip(
              locale.languageCode == 'es'
                  ? 'Guardar y reenviar'
                  : 'Save and resend',
            ),
            findsOneWidget,
          );
          final expectedSaveLabel = locale.languageCode == 'es'
              ? 'Guardar y reenviar'
              : 'Save and resend';
          final expectedCancelLabel = locale.languageCode == 'es'
              ? 'Cancelar edición'
              : 'Cancel edit';
          expect(find.byTooltip(expectedCancelLabel), findsOneWidget);
          final semantics = tester.ensureSemantics();
          expect(find.bySemanticsLabel(expectedSaveLabel), findsOneWidget);
          expect(find.bySemanticsLabel(expectedCancelLabel), findsOneWidget);
          semantics.dispose();

          await tester.enterText(field, 'Texto corregido');
          await tester.pump();
          expect(tester.widget<IconButton>(saveButton).onPressed, isNotNull);
          await tester.tap(saveButton);
          expect(saved, 'Texto corregido');
          expect(cancelled, isFalse);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
}
