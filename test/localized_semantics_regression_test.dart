// Accesibilidad localizada (console-1210 P2-A): textos que TalkBack anuncia y
// que antes estaban escritos a mano en español dentro del árbol de widgets.
// Se monta en inglés a propósito: si la cadena sigue codificada en el widget,
// el aserto en inglés falla.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/screens/image_viewer_screen.dart';
import 'package:hermes_android/core/screens/onboarding_screen.dart';
import 'package:hermes_android/core/services/connection_manager.dart';
import 'package:hermes_android/core/theme/app_theme.dart';
import 'package:hermes_android/l10n/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

Widget _host(Widget child, {Locale locale = const Locale('en')}) => MaterialApp(
  locale: locale,
  theme: AppTheme.fromId('dark'),
  localizationsDelegates: Strings.localizationsDelegates,
  supportedLocales: Strings.supportedLocales,
  home: child,
);

Future<ConnectionManager> _emptyManager() async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  return ConnectionManager.create(prefs);
}

void main() {
  testWidgets('ImageViewerScreen: el botón cerrar expone tooltip localizado', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(const ImageViewerScreen(imageUrl: 'https://example.invalid/a.png')),
    );
    await tester.pump();

    final closeButton = find.ancestor(
      of: find.byIcon(Icons.close),
      matching: find.byType(IconButton),
    );
    expect(closeButton, findsOneWidget);
    expect(tester.widget<IconButton>(closeButton).tooltip, 'Close');

    final handle = tester.ensureSemantics();
    expect(
      tester.getSemantics(closeButton).label.contains('Close'),
      isTrue,
      reason: 'el nodo de semántica del botón debe anunciar "Close"',
    );
    handle.dispose();
  });

  testWidgets('Onboarding: los puntos anuncian "Step N of M" localizado', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    final manager = await _emptyManager();
    await tester.pumpWidget(
      _host(OnboardingScreen(connManager: manager, onDone: () {})),
    );
    // El glow de fondo usa repeat(): nunca usar pumpAndSettle.
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.bySemanticsLabel('Step 1 of 4'), findsOneWidget);
    expect(find.bySemanticsLabel('Paso 1 de 4'), findsNothing);
    handle.dispose();
  });
}
