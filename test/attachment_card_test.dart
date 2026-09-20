import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/models/attachment_draft.dart';
import 'package:hermes_android/core/theme/app_theme.dart';
import 'package:hermes_android/core/widgets/attachment_card.dart';
import 'package:hermes_android/l10n/app_localizations.dart';

class _FakeAudioPlayback implements GeneratedAudioPlayback {
  final durations = StreamController<Duration>.broadcast();
  final positions = StreamController<Duration>.broadcast();
  final playing = StreamController<bool>.broadcast();
  int playCalls = 0;
  int pauseCalls = 0;
  int resumeCalls = 0;
  Duration? seekPosition;

  @override
  Stream<Duration> get durationChanges => durations.stream;

  @override
  Stream<Duration> get positionChanges => positions.stream;

  @override
  Stream<bool> get playingChanges => playing.stream;

  @override
  Future<void> play(File file) async {
    playCalls++;
    playing.add(true);
  }

  @override
  Future<void> pause() async {
    pauseCalls++;
    playing.add(false);
  }

  @override
  Future<void> resume() async {
    resumeCalls++;
    playing.add(true);
  }

  @override
  Future<void> seek(Duration position) async {
    seekPosition = position;
  }

  @override
  Future<void> dispose() async {
    await durations.close();
    await positions.close();
    await playing.close();
  }
}

void main() {
  Widget host(Widget child) => MaterialApp(
    locale: const Locale('es'),
    localizationsDelegates: Strings.localizationsDelegates,
    supportedLocales: Strings.supportedLocales,
    theme: AppTheme.hermesRedDark,
    home: Scaffold(body: child),
  );

  testWidgets('adjunto en subida muestra progreso y permite quitarlo', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(
        AttachmentCard(
          name: 'captura.jpg',
          mimeType: 'image/jpeg',
          sizeLabel: '2 MB',
          showUploadState: true,
          uploadState: AttachmentUploadState.uploading,
          onRemove: () {},
        ),
      ),
    );

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.byIcon(Icons.close), findsOneWidget);
    expect(find.textContaining('Subiendo'), findsOneWidget);
  });

  testWidgets('quitar adjunto tiene etiqueta y target de 48 dp', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(
        AttachmentCard(
          name: 'documento.pdf',
          mimeType: 'application/pdf',
          sizeLabel: '20 KB',
          onRemove: () {},
        ),
      ),
    );

    final target = find
        .ancestor(
          of: find.byIcon(Icons.close),
          matching: find.byType(GestureDetector),
        )
        .first;
    expect(tester.getSize(target), const Size(48, 48));
    expect(find.bySemanticsLabel('Quitar adjunto'), findsOneWidget);
  });

  testWidgets('archivo generado muestra progreso determinado y cancelar', (
    tester,
  ) async {
    var cancelled = 0;
    await tester.pumpWidget(
      host(
        GeneratedFileCard(
          name: 'informe.pdf',
          mimeType: 'application/pdf',
          status: GeneratedFileStatus.downloading,
          receivedBytes: 512,
          totalBytes: 1024,
          onDownload: () {},
          onCancel: () => cancelled++,
        ),
      ),
    );

    final progress = tester.widget<LinearProgressIndicator>(
      find.byType(LinearProgressIndicator),
    );
    expect(progress.value, 0.5);
    expect(find.textContaining('512 B / 1.0 KB'), findsOneWidget);
    await tester.tap(find.text('Cancelar'));
    expect(cancelled, 1);

    await tester.pumpWidget(
      host(
        GeneratedFileCard(
          name: 'informe.pdf',
          mimeType: 'application/pdf',
          status: GeneratedFileStatus.downloading,
          receivedBytes: 512,
          onDownload: () {},
          onCancel: () {},
        ),
      ),
    );
    expect(
      tester.widget<LinearProgressIndicator>(
        find.byType(LinearProgressIndicator),
      ).value,
      isNull,
    );
    expect(find.textContaining('Cargando contenido generado'), findsOneWidget);
  });

  testWidgets('archivo generado listo ofrece abrir compartir y guardar', (
    tester,
  ) async {
    var opened = 0;
    var shared = 0;
    var saved = 0;
    await tester.pumpWidget(
      host(
        GeneratedFileCard(
          name: 'informe.pdf',
          mimeType: 'application/pdf',
          status: GeneratedFileStatus.ready,
          receivedBytes: 2048,
          totalBytes: 2048,
          onDownload: () {},
          onOpen: () => opened++,
          onShare: () => shared++,
          onSave: () => saved++,
        ),
      ),
    );

    await tester.tap(find.text('Abrir'));
    await tester.tap(find.text('Compartir'));
    await tester.tap(find.text('Guardar'));
    expect((opened, shared, saved), (1, 1, 1));
  });

  testWidgets('archivo generado fallido ofrece reintentar', (tester) async {
    var retries = 0;
    await tester.pumpWidget(
      host(
        GeneratedFileCard(
          name: 'informe.pdf',
          mimeType: 'application/pdf',
          status: GeneratedFileStatus.error,
          errorLabel: 'Este archivo ya no está disponible',
          onDownload: () => retries++,
        ),
      ),
    );

    expect(find.textContaining('ya no está disponible'), findsOneWidget);
    await tester.tap(find.text('Reintentar'));
    expect(retries, 1);
  });

  testWidgets('audio generado no reproduce solo y muestra duración y progreso', (
    tester,
  ) async {
    final directory = Directory.systemTemp.createTempSync('generated-audio-');
    addTearDown(() {
      if (directory.existsSync()) directory.deleteSync(recursive: true);
    });
    final file = File('${directory.path}/resumen.mp3')..writeAsBytesSync([1]);
    final playback = _FakeAudioPlayback();

    await tester.pumpWidget(
      host(
        GeneratedAudioPlayerCard(
          file: file,
          name: 'resumen.mp3',
          mimeType: 'audio/mpeg',
          sizeBytes: 1024,
          playback: playback,
          onShare: () {},
          onSave: () {},
        ),
      ),
    );

    expect(playback.playCalls, 0);
    playback.durations.add(const Duration(minutes: 2));
    playback.positions.add(const Duration(seconds: 30));
    await tester.pump();
    expect(find.text('0:30 / 2:00'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.play_arrow_rounded));
    await tester.pump();
    expect(playback.playCalls, 1);
    expect(find.byIcon(Icons.pause_rounded), findsOneWidget);
  });

  testWidgets('audio generado permite pausa, seek, compartir y guardar', (
    tester,
  ) async {
    final directory = Directory.systemTemp.createTempSync('generated-audio-');
    addTearDown(() {
      if (directory.existsSync()) directory.deleteSync(recursive: true);
    });
    final file = File('${directory.path}/resumen.mp3')..writeAsBytesSync([1]);
    final playback = _FakeAudioPlayback();
    var shared = 0;
    var saved = 0;

    await tester.pumpWidget(
      host(
        GeneratedAudioPlayerCard(
          file: file,
          name: 'resumen.mp3',
          mimeType: 'audio/mpeg',
          sizeBytes: 1024,
          playback: playback,
          onShare: () => shared++,
          onSave: () => saved++,
        ),
      ),
    );
    playback.durations.add(const Duration(minutes: 1));
    playback.playing.add(true);
    await tester.pump();

    await tester.tap(find.byIcon(Icons.pause_rounded));
    expect(playback.pauseCalls, 1);
    final slider = tester.widget<Slider>(find.byType(Slider));
    slider.onChanged!(30000);
    await tester.pump();
    expect(playback.seekPosition, const Duration(seconds: 30));
    await tester.tap(find.text('Compartir'));
    await tester.tap(find.text('Guardar'));
    expect((shared, saved), (1, 1));
  });

  testWidgets('error de imagen ofrece retry y remove independientes de 48 dp', (
    tester,
  ) async {
    final directory = Directory.systemTemp.createTempSync(
      'attachment-card-image-',
    );
    addTearDown(() {
      if (directory.existsSync()) {
        directory.deleteSync(recursive: true);
      }
    });
    final image = File('${directory.path}/pixel.png');
    image.writeAsBytesSync(
      base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwC'
        'AAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
      ),
    );
    var retries = 0;
    var removes = 0;

    await tester.pumpWidget(
      host(
        AttachmentCard(
          name: 'captura.png',
          mimeType: 'image/png',
          sizeLabel: '1 KB',
          thumbnailFile: image,
          showUploadState: true,
          uploadState: AttachmentUploadState.error,
          onRetry: () => retries++,
          onRemove: () => removes++,
        ),
      ),
    );

    expect(find.text('Error al subir'), findsOneWidget);
    expect(find.bySemanticsLabel('Reintentar adjunto'), findsOneWidget);
    expect(find.bySemanticsLabel('Quitar adjunto'), findsOneWidget);
    for (final icon in [Icons.refresh_rounded, Icons.close]) {
      final target = find
          .ancestor(
            of: find.byIcon(icon),
            matching: find.byType(GestureDetector),
          )
          .first;
      expect(tester.getSize(target), const Size(48, 48));
    }

    await tester.tap(find.byIcon(Icons.refresh_rounded));
    await tester.tap(find.byIcon(Icons.close));
    expect(retries, 1);
    expect(removes, 1);
  });
}
