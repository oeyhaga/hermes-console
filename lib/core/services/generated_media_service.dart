import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:path_provider/path_provider.dart';

enum GeneratedMediaKind { image, video, audio, file }

enum GeneratedMediaSourceKind { serverPath, https }

typedef GeneratedMediaProgress = void Function(int received, int? total);
typedef GeneratedMediaStreamingFetcher =
    Future<void> Function(
      String path,
      File destination,
      GeneratedMediaProgress onProgress,
      bool Function() isCancelled,
    );

class GeneratedMediaDownloadCancelled implements Exception {
  const GeneratedMediaDownloadCancelled();

  @override
  String toString() => 'generated_media_download_cancelled';
}

class GeneratedMediaReference {
  final String source;
  final GeneratedMediaKind kind;
  final GeneratedMediaSourceKind sourceKind;
  final String displayName;
  final String mimeType;

  const GeneratedMediaReference({
    required this.source,
    required this.kind,
    required this.sourceKind,
    this.displayName = 'file',
    this.mimeType = 'application/octet-stream',
  });
}

sealed class GeneratedMediaSegment {
  const GeneratedMediaSegment();
}

class GeneratedMediaTextSegment extends GeneratedMediaSegment {
  final String text;
  const GeneratedMediaTextSegment(this.text);
}

class GeneratedMediaFileSegment extends GeneratedMediaSegment {
  final GeneratedMediaReference reference;
  const GeneratedMediaFileSegment(this.reference);
}

/// Detects Hermes' canonical `MEDIA:<path-or-url>` directives and keeps their
/// bytes in app-private storage. Server paths are fetched by the authenticated
/// Dashboard client supplied by the caller; they are never exposed as public
/// URLs or Android external-storage paths.
class GeneratedMediaService {
  static const int maxImageBytes = 25 * 1024 * 1024;
  static const int maxVideoBytes = 100 * 1024 * 1024;
  static const int maxFileBytes = 100 * 1024 * 1024;
  static const int _maxCacheBytes = 512 * 1024 * 1024;
  static const int _maxRedirects = 3;

  static const Set<String> _imageExtensions = {
    '.png',
    '.jpg',
    '.jpeg',
    '.gif',
    '.webp',
    '.bmp',
    '.tiff',
  };
  static const Set<String> _videoExtensions = {
    '.mp4',
    '.mov',
    '.avi',
    '.mkv',
    '.webm',
    '.3gp',
  };
  static const Set<String> _audioExtensions = {
    '.mp3',
    '.m2a',
    '.wav',
    '.ogg',
    '.opus',
    '.m4a',
    '.flac',
  };
  static const Set<String> _knownFileExtensions = {
    '.svg',
    '.pdf',
    '.docx',
    '.doc',
    '.odt',
    '.rtf',
    '.txt',
    '.md',
    '.epub',
    '.xlsx',
    '.xls',
    '.ods',
    '.csv',
    '.tsv',
    '.json',
    '.xml',
    '.yaml',
    '.yml',
    '.kmz',
    '.kml',
    '.geojson',
    '.gpx',
    '.pptx',
    '.ppt',
    '.odp',
    '.key',
    '.zip',
    '.tar',
    '.gz',
    '.tgz',
    '.bz2',
    '.xz',
    '.7z',
    '.rar',
    '.apk',
    '.ipa',
    '.html',
    '.htm',
  };

  static final Map<String, Future<File>> _inFlight = {};

  static List<GeneratedMediaSegment> parseSegments(String content) {
    if (content.isEmpty || !content.contains('MEDIA:')) {
      return <GeneratedMediaSegment>[GeneratedMediaTextSegment(content)];
    }

    final segments = <GeneratedMediaSegment>[];
    final lines = content.split('\n');
    final text = StringBuffer();
    String? fenceMarker;
    var fenceWidth = 0;
    var withheldDirective = false;

    void flushText() {
      if (text.isEmpty) return;
      segments.add(GeneratedMediaTextSegment(text.toString()));
      text.clear();
    }

    for (var index = 0; index < lines.length; index++) {
      final line = lines[index];
      final hasNewline = index < lines.length - 1;
      final trimmed = line.trimLeft();
      final fence = RegExp(r'^(`{3,}|~{3,})').firstMatch(trimmed)?.group(1);
      if (fence != null &&
          (fenceMarker == null ||
              (fence[0] == fenceMarker && fence.length >= fenceWidth))) {
        if (fenceMarker == null) {
          fenceMarker = fence[0];
          fenceWidth = fence.length;
        } else {
          fenceMarker = null;
          fenceWidth = 0;
        }
        text.write(line);
        if (hasNewline) text.write('\n');
        continue;
      }

      final reference = fenceMarker != null ? null : _parseDirective(line);
      if (reference == null) {
        // Outside a code fence, MEDIA is a control directive rather than prose.
        // Drop malformed/unsupported directives so local paths, signed URLs or
        // traversal attempts never leak through Markdown, clipboard or TTS.
        if (fenceMarker == null && line.trimLeft().startsWith('MEDIA:')) {
          withheldDirective = true;
          if (hasNewline) text.write('\n');
          continue;
        }
        text.write(line);
        if (hasNewline) text.write('\n');
        continue;
      }

      flushText();
      segments.add(GeneratedMediaFileSegment(reference));
      if (hasNewline) text.write('\n');
    }
    flushText();
    if (segments.isNotEmpty) return segments;
    return <GeneratedMediaSegment>[
      GeneratedMediaTextSegment(withheldDirective ? '' : content),
    ];
  }

  static GeneratedMediaReference? referenceFromSource(String rawSource) {
    final source = rawSource.trim();
    if (source.isEmpty) return null;
    return _parseDirective('MEDIA:$source');
  }

  /// Extracts only successful first-party producer results. `agent_visible_image`
  /// is deliberately never fetched: it may be a sandbox-only path.
  static List<GeneratedMediaReference> referencesFromToolResult(
    String? toolName,
    Object? rawResult,
  ) {
    final normalizedName = toolName?.trim().toLowerCase();
    if (normalizedName != 'image_generate' &&
        normalizedName != 'video_generate') {
      return const [];
    }
    Object? decoded = rawResult;
    if (decoded is String) {
      try {
        decoded = jsonDecode(decoded);
      } catch (_) {
        return const [];
      }
    }
    if (decoded is! Map || decoded['success'] != true) return const [];

    final fields = normalizedName == 'image_generate'
        ? const ['host_image', 'image']
        : const ['video'];
    for (final field in fields) {
      final value = decoded[field];
      if (value is! String) continue;
      final reference = referenceFromSource(value);
      if (reference == null) continue;
      final expectedKind = normalizedName == 'image_generate'
          ? GeneratedMediaKind.image
          : GeneratedMediaKind.video;
      if (reference.kind == expectedKind) {
        return List<GeneratedMediaReference>.unmodifiable([reference]);
      }
    }
    return const [];
  }

  static GeneratedMediaReference? _parseDirective(String line) {
    final match = RegExp(r'^\s*MEDIA:\s*(.*?)\s*$').firstMatch(line);
    if (match == null) return null;
    var source = (match.group(1) ?? '').trim();
    if (source.length >= 2 &&
        ((source.startsWith('"') && source.endsWith('"')) ||
            (source.startsWith("'") && source.endsWith("'")))) {
      source = source.substring(1, source.length - 1).trim();
    }
    if (source.isEmpty || source.contains('\u0000')) return null;

    final uri = Uri.tryParse(source);
    final sourceKind = uri != null && uri.scheme.toLowerCase() == 'https'
        ? GeneratedMediaSourceKind.https
        : GeneratedMediaSourceKind.serverPath;
    if (uri != null &&
        uri.hasScheme &&
        sourceKind != GeneratedMediaSourceKind.https) {
      // Explicitly reject http:, file:, data: and custom schemes.
      return null;
    }
    if (sourceKind == GeneratedMediaSourceKind.https) {
      if (uri == null ||
          !uri.hasAuthority ||
          uri.host.isEmpty ||
          uri.userInfo.isNotEmpty ||
          _hasCredentialQuery(uri)) {
        return null;
      }
      source = uri.removeFragment().toString();
    }
    if (sourceKind == GeneratedMediaSourceKind.serverPath &&
        !_isSafeServerPath(source)) {
      return null;
    }

    final path = sourceKind == GeneratedMediaSourceKind.https
        ? uri!.path
        : source;
    final rawName = _decodedBasename(path);
    if (_isSensitiveName(rawName)) return null;
    final displayName = _displayName(rawName);
    final lower = path.toLowerCase();
    final kind = _imageExtensions.any(lower.endsWith)
        ? GeneratedMediaKind.image
        : _videoExtensions.any(lower.endsWith)
        ? GeneratedMediaKind.video
        : _audioExtensions.any(lower.endsWith)
        ? GeneratedMediaKind.audio
        : GeneratedMediaKind.file;
    return GeneratedMediaReference(
      source: source,
      kind: kind,
      sourceKind: sourceKind,
      displayName: displayName,
      mimeType: _mimeType(displayName, kind),
    );
  }

  static bool _hasCredentialQuery(Uri uri) {
    try {
      return uri.queryParametersAll.keys.any(
        (key) => RegExp(
          r'(^|[_-])(token|key|secret|signature|credential|password|auth)($|[_-])',
          caseSensitive: false,
        ).hasMatch(key),
      );
    } on FormatException {
      return true;
    }
  }

  static String _decodedBasename(String path) {
    final raw = path.replaceAll('\\', '/').split('/').last;
    try {
      return Uri.decodeComponent(raw);
    } on FormatException {
      return raw;
    }
  }

  static String _displayName(String name) {
    var safe = name
        .replaceAll(RegExp(r'[\\/:*?"<>|\x00-\x1f\x7f]'), '_')
        .replaceAll(RegExp(r'\.{2,}'), '.')
        .trim();
    safe = safe.replaceFirst(RegExp(r'^\.+'), '');
    if (safe.length > 120) safe = safe.substring(0, 120);
    return safe.isEmpty ? 'file' : safe;
  }

  static bool _isSensitiveName(String name) {
    final lower = name.toLowerCase();
    if (lower == '.env' ||
        lower.endsWith('.env') ||
        lower.startsWith('.env.') ||
        lower == 'key.properties' ||
        lower == 'credentials.json' ||
        lower == 'secrets.json' ||
        lower == 'id_rsa' ||
        lower == 'id_ed25519') {
      return true;
    }
    return const {
      '.jks',
      '.keystore',
      '.p12',
      '.pfx',
      '.pem',
      '.keytab',
    }.any(lower.endsWith);
  }

  static String _mimeType(String name, GeneratedMediaKind kind) {
    final lower = name.toLowerCase();
    if (kind == GeneratedMediaKind.image) {
      if (lower.endsWith('.png')) return 'image/png';
      if (lower.endsWith('.gif')) return 'image/gif';
      if (lower.endsWith('.webp')) return 'image/webp';
      if (lower.endsWith('.bmp')) return 'image/bmp';
      if (lower.endsWith('.tiff')) return 'image/tiff';
      return 'image/jpeg';
    }
    if (kind == GeneratedMediaKind.video) {
      if (lower.endsWith('.webm')) return 'video/webm';
      if (lower.endsWith('.mov')) return 'video/quicktime';
      if (lower.endsWith('.avi')) return 'video/x-msvideo';
      if (lower.endsWith('.mkv')) return 'video/x-matroska';
      if (lower.endsWith('.3gp')) return 'video/3gpp';
      return 'video/mp4';
    }
    if (kind == GeneratedMediaKind.audio) {
      if (lower.endsWith('.wav')) return 'audio/wav';
      if (lower.endsWith('.ogg') || lower.endsWith('.opus')) return 'audio/ogg';
      if (lower.endsWith('.m4a') || lower.endsWith('.m2a')) return 'audio/mp4';
      if (lower.endsWith('.flac')) return 'audio/flac';
      return 'audio/mpeg';
    }
    final dot = lower.lastIndexOf('.');
    final extension = dot < 0 ? '' : lower.substring(dot);
    if (!_knownFileExtensions.contains(extension)) {
      return 'application/octet-stream';
    }
    return switch (extension) {
      '.pdf' => 'application/pdf',
      '.txt' || '.md' || '.csv' || '.tsv' => 'text/plain',
      '.json' || '.geojson' => 'application/json',
      '.xml' => 'application/xml',
      '.yaml' || '.yml' => 'application/yaml',
      '.svg' => 'image/svg+xml',
      '.html' || '.htm' => 'text/html',
      '.zip' => 'application/zip',
      '.apk' => 'application/vnd.android.package-archive',
      _ => 'application/octet-stream',
    };
  }

  static bool _isSafeServerPath(String source) {
    if (source.length > 2048 ||
        !source.startsWith('/') ||
        source.startsWith('//') ||
        source.contains('\\') ||
        source.contains(RegExp(r'[\x00-\x1f\x7f]')) ||
        source.contains('?') ||
        source.contains('#')) {
      return false;
    }
    for (final raw in source.split('/').skip(1)) {
      if (raw.isEmpty || raw == '.' || raw == '..') return false;
      String decoded;
      try {
        decoded = Uri.decodeComponent(raw);
      } on FormatException {
        return false;
      }
      if (decoded.isEmpty ||
          decoded == '.' ||
          decoded == '..' ||
          decoded.contains('/') ||
          decoded.contains('\\') ||
          decoded.contains(RegExp(r'[\x00-\x1f\x7f]'))) {
        return false;
      }
    }
    return true;
  }

  /// Text suitable for copy, read-aloud and notification previews: prose is
  /// preserved while server-local paths and signed media URLs stay private.
  static String stripDirectives(String content) => parseSegments(content)
      .whereType<GeneratedMediaTextSegment>()
      .map((segment) => segment.text)
      .join();

  static Future<File> ensureDownloaded(
    String connectionId,
    GeneratedMediaReference reference, {
    Future<Uint8List> Function(String path)? fetchServerPath,
    Future<void> Function(String path, File destination)? fetchServerPathToFile,
    GeneratedMediaStreamingFetcher? fetchServerPathToFileWithProgress,
    GeneratedMediaProgress? onProgress,
    bool Function()? isCancelled,
    Directory? baseDir,
  }) {
    if (reference.sourceKind == GeneratedMediaSourceKind.serverPath &&
        fetchServerPath == null &&
        fetchServerPathToFile == null &&
        fetchServerPathToFileWithProgress == null) {
      throw ArgumentError('A server-path fetcher is required');
    }
    final key =
        '${baseDir?.path ?? 'app'}\u0000$connectionId\u0000${reference.source}';
    final existing = _inFlight[key];
    if (existing != null) return existing;
    final future = _ensureDownloaded(
      connectionId,
      reference,
      fetchServerPath: fetchServerPath,
      fetchServerPathToFile: fetchServerPathToFile,
      fetchServerPathToFileWithProgress: fetchServerPathToFileWithProgress,
      onProgress: onProgress,
      isCancelled: isCancelled,
      baseDir: baseDir,
    );
    _inFlight[key] = future;
    unawaited(
      future.then<void>(
        (_) {
          _inFlight.remove(key);
        },
        onError: (Object _, StackTrace _) {
          _inFlight.remove(key);
        },
      ),
    );
    return future;
  }

  static Future<File> _ensureDownloaded(
    String connectionId,
    GeneratedMediaReference reference, {
    Future<Uint8List> Function(String path)? fetchServerPath,
    Future<void> Function(String path, File destination)? fetchServerPathToFile,
    GeneratedMediaStreamingFetcher? fetchServerPathToFileWithProgress,
    GeneratedMediaProgress? onProgress,
    bool Function()? isCancelled,
    Directory? baseDir,
  }) async {
    if (isCancelled?.call() ?? false) {
      throw const GeneratedMediaDownloadCancelled();
    }
    final root = baseDir ?? await getApplicationSupportDirectory();
    final connectionHash = sha256.convert(utf8.encode(connectionId)).toString();
    final sourceHash = sha256.convert(utf8.encode(reference.source)).toString();
    final suffix = _extensionFor(reference.displayName, reference.kind);
    final directory = Directory('${root.path}/generated_media/$connectionHash');
    await directory.create(recursive: true);
    final target = File('${directory.path}/$sourceHash$suffix');

    if (await target.exists()) {
      try {
        final length = await target.length();
        if (length > 0 && length <= _maxBytes(reference.kind)) {
          final probe = await _readPrefix(target, 32);
          if (validateBytes(probe, reference.kind)) {
            if (isCancelled?.call() ?? false) {
              throw const GeneratedMediaDownloadCancelled();
            }
            onProgress?.call(length, length);
            await target.setLastModified(DateTime.now());
            return target;
          }
        }
      } catch (_) {
        // A concurrent prune may have removed the cache entry. Re-download.
      }
      if (await target.exists()) {
        await target.delete().catchError((_) => target);
      }
    }

    final temporary = File(
      '${target.path}.tmp-${DateTime.now().microsecondsSinceEpoch}',
    );
    try {
      if (reference.sourceKind == GeneratedMediaSourceKind.serverPath &&
          fetchServerPathToFileWithProgress != null) {
        await fetchServerPathToFileWithProgress(
          reference.source,
          temporary,
          onProgress ?? (_, _) {},
          isCancelled ?? () => false,
        );
      } else if (reference.sourceKind == GeneratedMediaSourceKind.serverPath &&
          fetchServerPathToFile != null) {
        await fetchServerPathToFile(reference.source, temporary);
      } else if (reference.sourceKind == GeneratedMediaSourceKind.serverPath) {
        final bytes = await fetchServerPath!(reference.source);
        if (bytes.isEmpty || bytes.length > _maxBytes(reference.kind)) {
          throw const FormatException('generated media exceeds its size limit');
        }
        if (isCancelled?.call() ?? false) {
          throw const GeneratedMediaDownloadCancelled();
        }
        await temporary.writeAsBytes(bytes, flush: true);
        onProgress?.call(bytes.length, bytes.length);
      } else {
        await _downloadHttpsToFile(
          reference.source,
          reference.kind,
          temporary,
          onProgress: onProgress,
          isCancelled: isCancelled,
        );
      }

      if (isCancelled?.call() ?? false) {
        throw const GeneratedMediaDownloadCancelled();
      }
      final length = await temporary.length();
      if (length <= 0 || length > _maxBytes(reference.kind)) {
        throw const FormatException('generated media exceeds its size limit');
      }
      final probe = await _readPrefix(temporary, 32);
      if (!validateBytes(probe, reference.kind)) {
        throw const FormatException('generated media signature is invalid');
      }
      await temporary.rename(target.path);
    } finally {
      if (await temporary.exists()) {
        await temporary.delete().catchError((_) => temporary);
      }
    }
    await _pruneCache(Directory('${root.path}/generated_media'));
    return target;
  }

  static int _maxBytes(GeneratedMediaKind kind) => switch (kind) {
    GeneratedMediaKind.image => maxImageBytes,
    GeneratedMediaKind.video => maxVideoBytes,
    GeneratedMediaKind.audio || GeneratedMediaKind.file => maxFileBytes,
  };

  static String _extensionFor(String name, GeneratedMediaKind kind) {
    final dot = name.lastIndexOf('.');
    if (dot >= 0) {
      final extension = name.substring(dot).toLowerCase();
      final allowed = switch (kind) {
        GeneratedMediaKind.image => _imageExtensions,
        GeneratedMediaKind.video => _videoExtensions,
        GeneratedMediaKind.audio => _audioExtensions,
        GeneratedMediaKind.file => _knownFileExtensions,
      };
      if (allowed.contains(extension) ||
          (kind == GeneratedMediaKind.file &&
              RegExp(r'^\.[a-z0-9]{1,16}$').hasMatch(extension))) {
        return extension;
      }
    }
    return switch (kind) {
      GeneratedMediaKind.image => '.img',
      GeneratedMediaKind.video => '.video',
      GeneratedMediaKind.audio => '.audio',
      GeneratedMediaKind.file => '.file',
    };
  }

  static Future<Uint8List> _readPrefix(File file, int count) async {
    final handle = await file.open();
    try {
      return Uint8List.fromList(await handle.read(count));
    } finally {
      await handle.close();
    }
  }

  static bool validateBytes(Uint8List bytes, GeneratedMediaKind kind) {
    if (kind == GeneratedMediaKind.image) {
      if (bytes.length >= 8 &&
          bytes[0] == 0x89 &&
          bytes[1] == 0x50 &&
          bytes[2] == 0x4e &&
          bytes[3] == 0x47 &&
          bytes[4] == 0x0d &&
          bytes[5] == 0x0a &&
          bytes[6] == 0x1a &&
          bytes[7] == 0x0a) {
        return true;
      }
      if (bytes.length >= 3 &&
          bytes[0] == 0xff &&
          bytes[1] == 0xd8 &&
          bytes[2] == 0xff) {
        return true;
      }
      if (bytes.length >= 6) {
        final signature = String.fromCharCodes(bytes.sublist(0, 6));
        if (signature == 'GIF87a' || signature == 'GIF89a') return true;
      }
      if (bytes.length >= 12 &&
          String.fromCharCodes(bytes.sublist(0, 4)) == 'RIFF' &&
          String.fromCharCodes(bytes.sublist(8, 12)) == 'WEBP') {
        return true;
      }
      if (bytes.length >= 4) {
        final signature = bytes.sublist(0, 4);
        if ((signature[0] == 0x49 &&
                signature[1] == 0x49 &&
                signature[2] == 0x2a &&
                signature[3] == 0x00) ||
            (signature[0] == 0x4d &&
                signature[1] == 0x4d &&
                signature[2] == 0x00 &&
                signature[3] == 0x2a)) {
          return true;
        }
      }
      return bytes.length >= 2 && bytes[0] == 0x42 && bytes[1] == 0x4d;
    }

    if (kind == GeneratedMediaKind.file) return bytes.isNotEmpty;
    if (kind == GeneratedMediaKind.audio) {
      if (bytes.length >= 3 &&
          String.fromCharCodes(bytes.sublist(0, 3)) == 'ID3') {
        return true;
      }
      if (bytes.length >= 2 &&
          bytes[0] == 0xff &&
          (bytes[1] & 0xe0) == 0xe0) {
        return true;
      }
      if (bytes.length >= 4) {
        final signature = String.fromCharCodes(bytes.sublist(0, 4));
        if (signature == 'OggS' || signature == 'fLaC') return true;
      }
      if (bytes.length >= 12 &&
          String.fromCharCodes(bytes.sublist(0, 4)) == 'RIFF' &&
          String.fromCharCodes(bytes.sublist(8, 12)) == 'WAVE') {
        return true;
      }
      return bytes.length >= 12 &&
          String.fromCharCodes(bytes.sublist(4, 8)) == 'ftyp';
    }

    if (bytes.length >= 12 &&
        String.fromCharCodes(bytes.sublist(4, 8)) == 'ftyp') {
      return true;
    }
    if (bytes.length >= 4 &&
        bytes[0] == 0x1a &&
        bytes[1] == 0x45 &&
        bytes[2] == 0xdf &&
        bytes[3] == 0xa3) {
      return true;
    }
    return bytes.length >= 12 &&
        String.fromCharCodes(bytes.sublist(0, 4)) == 'RIFF' &&
        String.fromCharCodes(bytes.sublist(8, 12)) == 'AVI ';
  }

  static Future<void> _downloadHttpsToFile(
    String source,
    GeneratedMediaKind kind,
    File target, {
    GeneratedMediaProgress? onProgress,
    bool Function()? isCancelled,
  }) async {
    var uri = Uri.parse(source);
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 15);
    try {
      for (var redirect = 0; redirect <= _maxRedirects; redirect++) {
        if (isCancelled?.call() ?? false) {
          throw const GeneratedMediaDownloadCancelled();
        }
        if (uri.scheme != 'https' ||
            uri.host.isEmpty ||
            uri.userInfo.isNotEmpty) {
          throw const FormatException(
            'only credential-free HTTPS media is supported',
          );
        }
        final request = await client
            .getUrl(uri)
            .timeout(const Duration(seconds: 20));
        request.followRedirects = false;
        final response = await request.close().timeout(
          const Duration(seconds: 30),
        );
        if (response.isRedirect) {
          final location = response.headers.value(HttpHeaders.locationHeader);
          await _cancelHttpResponse(response);
          if (location == null || redirect == _maxRedirects) {
            throw const HttpException('invalid media redirect');
          }
          final next = uri.resolve(location);
          if (next.scheme != 'https' || next.origin != uri.origin) {
            throw const HttpException('cross-origin media redirect rejected');
          }
          uri = next;
          continue;
        }
        if (response.statusCode < 200 || response.statusCode >= 300) {
          await _cancelHttpResponse(response);
          throw HttpException('media download failed (${response.statusCode})');
        }
        final maxBytes = _maxBytes(kind);
        final declared = response.contentLength;
        final total = declared >= 0 ? declared : null;
        if (declared > maxBytes) {
          await _cancelHttpResponse(response);
          throw const HttpException('generated media is too large');
        }

        final sink = target.openWrite(mode: FileMode.writeOnly);
        var received = 0;
        try {
          await for (final chunk in response.timeout(
            const Duration(minutes: 2),
          )) {
            if (isCancelled?.call() ?? false) {
              throw const GeneratedMediaDownloadCancelled();
            }
            received += chunk.length;
            if (received > maxBytes) {
              throw const HttpException('generated media is too large');
            }
            sink.add(chunk);
            onProgress?.call(received, total);
            if (isCancelled?.call() ?? false) {
              throw const GeneratedMediaDownloadCancelled();
            }
          }
          await sink.flush();
        } finally {
          await sink.close();
        }
        if (received <= 0) {
          throw const HttpException('generated media is empty');
        }
        if (total != null && received != total) {
          throw const HttpException('generated media download was incomplete');
        }
        return;
      }
      throw const HttpException('too many media redirects');
    } finally {
      client.close(force: true);
    }
  }

  static Future<void> _cancelHttpResponse(HttpClientResponse response) async {
    final subscription = response.listen((_) {});
    await subscription.cancel();
  }

  static Future<void> _pruneCache(Directory root) async {
    if (!await root.exists()) return;
    final files = <File>[];
    await for (final entity in root.list(recursive: true, followLinks: false)) {
      if (entity is File && !entity.path.contains('.tmp-')) files.add(entity);
    }
    var total = 0;
    final entries = <({File file, int bytes, DateTime modified})>[];
    for (final file in files) {
      try {
        final stat = await file.stat();
        total += stat.size;
        entries.add((file: file, bytes: stat.size, modified: stat.modified));
      } catch (_) {
        // A concurrent cleanup may already have removed it.
      }
    }
    if (total <= _maxCacheBytes) return;
    entries.sort((a, b) => a.modified.compareTo(b.modified));
    for (final entry in entries) {
      if (total <= _maxCacheBytes) break;
      try {
        await entry.file.delete();
        total -= entry.bytes;
      } catch (_) {
        // Best effort cache maintenance.
      }
    }
  }
}
