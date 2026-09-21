import 'dart:convert';

/// Lo que el backend publica de una compactación, y nada más.
///
/// Hermes Agent NO envía porcentaje ni progreso: `status.update` con
/// `kind=compacting` (más latidos periódicos) marca el inicio de la
/// compactación automática y `kind=compacted` su final; la manual
/// (`session.compress`) trae `before/after_tokens` solo en el RESULTADO. Por
/// eso esta clase mide lo único que es real (el tiempo transcurrido) y estima
/// el resto a partir de compactaciones anteriores medidas en este mismo
/// dispositivo. Toda cifra estimada se pinta con «≈» y no supera [maxFraction]
/// hasta que llega el evento de fin.
final class CompactionProgress {
  const CompactionProgress({
    required this.startedAt,
    required this.manual,
    this.tokensBefore,
    this.messagesBefore,
    this.estimate,
    this.finishedAt,
    this.tokensAfter,
    this.messagesAfter,
    this.note,
  });

  /// La barra nunca llega al 100 % por estimación: solo el fin real la cierra.
  static const double maxFraction = 0.95;

  final DateTime startedAt;

  /// `/compress` (o «Comprimir ahora») frente a la compactación automática.
  final bool manual;
  final int? tokensBefore;
  final int? messagesBefore;

  /// Duración típica aprendida de compactaciones previas, o `null` sin
  /// historial (entonces solo hay tiempo transcurrido).
  final Duration? estimate;

  /// No nulo cuando la compactación terminó.
  final DateTime? finishedAt;
  final int? tokensAfter;
  final int? messagesAfter;

  /// Texto libre del backend (línea fijada `compressing N messages…`), nunca
  /// se pinta tal cual: solo sirve a los tests y al diagnóstico.
  final String? note;

  bool get isFinished => finishedAt != null;

  Duration elapsed(DateTime now) {
    final end = finishedAt ?? now;
    final value = end.difference(startedAt);
    return value.isNegative ? Duration.zero : value;
  }

  /// Duración total, solo una vez terminada.
  Duration? get duration => finishedAt == null ? null : elapsed(finishedAt!);

  /// Fracción estimada `0..0.95`, o `null` si no hay estimación fiable.
  double? fraction(DateTime now) {
    final typical = estimate;
    if (isFinished || typical == null || typical <= Duration.zero) return null;
    final value = elapsed(now).inMilliseconds / typical.inMilliseconds;
    return value.clamp(0.0, maxFraction).toDouble();
  }

  /// Tiempo restante estimado (`>= 0`), o `null` sin estimación.
  Duration? remaining(DateTime now) {
    final typical = estimate;
    if (isFinished || typical == null) return null;
    final left = typical - elapsed(now);
    return left.isNegative ? Duration.zero : left;
  }

  CompactionProgress copyWith({
    Duration? estimate,
    DateTime? finishedAt,
    int? tokensBefore,
    int? tokensAfter,
    int? messagesBefore,
    int? messagesAfter,
    String? note,
  }) => CompactionProgress(
    startedAt: startedAt,
    manual: manual,
    tokensBefore: tokensBefore ?? this.tokensBefore,
    messagesBefore: messagesBefore ?? this.messagesBefore,
    estimate: estimate ?? this.estimate,
    finishedAt: finishedAt ?? this.finishedAt,
    tokensAfter: tokensAfter ?? this.tokensAfter,
    messagesAfter: messagesAfter ?? this.messagesAfter,
    note: note ?? this.note,
  );
}

/// Una compactación medida: duración y, si se conocía, tamaño de partida.
final class CompactionSample {
  const CompactionSample({required this.durationMs, this.tokensBefore});

  final int durationMs;
  final int? tokensBefore;

  Map<String, Object?> toJson() => {
    'd': durationMs,
    if (tokensBefore != null) 't': tokensBefore,
  };

  static CompactionSample? tryParse(Object? raw) {
    if (raw is! Map) return null;
    final d = raw['d'];
    if (d is! num || !d.isFinite || d <= 0 || d > 6 * 3600 * 1000) return null;
    final t = raw['t'];
    return CompactionSample(
      durationMs: d.round(),
      tokensBefore: t is num && t.isFinite && t > 0 ? t.round() : null,
    );
  }
}

/// Historial acotado de compactaciones de una conexión+modelo y su estimador.
final class CompactionHistory {
  const CompactionHistory(this.samples);

  static const CompactionHistory empty = CompactionHistory([]);

  /// Cuántas mediciones se conservan (las más recientes).
  static const int capacity = 10;

  /// Factor de escala permitido cuando se conoce el tamaño de partida.
  static const double minScale = 0.5;
  static const double maxScale = 3.0;

  final List<CompactionSample> samples;

  bool get isEmpty => samples.isEmpty;

  CompactionHistory add(CompactionSample sample) {
    final next = [...samples, sample];
    return CompactionHistory(
      next.length <= capacity ? next : next.sublist(next.length - capacity),
    );
  }

  static num _median(List<num> values) {
    final sorted = [...values]..sort();
    final mid = sorted.length ~/ 2;
    return sorted.length.isOdd
        ? sorted[mid]
        : (sorted[mid - 1] + sorted[mid]) / 2;
  }

  /// Duración típica: mediana de las mediciones, escalada por
  /// `tokensBefore / mediana(tokens)` (acotado a 0.5x–3x) cuando ambos se
  /// conocen. `null` sin historial: no se inventa una cifra.
  Duration? estimate({int? tokensBefore}) {
    if (samples.isEmpty) return null;
    var ms = _median(samples.map((s) => s.durationMs).toList()).toDouble();
    final known = samples.map((s) => s.tokensBefore).whereType<int>().toList();
    if (tokensBefore != null && tokensBefore > 0 && known.isNotEmpty) {
      final typicalTokens = _median(known).toDouble();
      if (typicalTokens > 0) {
        ms *= (tokensBefore / typicalTokens).clamp(minScale, maxScale);
      }
    }
    return Duration(milliseconds: ms.round());
  }

  String encode() => jsonEncode([for (final s in samples) s.toJson()]);

  static CompactionHistory decode(String? raw) {
    if (raw == null || raw.isEmpty) return empty;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return empty;
      final parsed = decoded
          .map(CompactionSample.tryParse)
          .whereType<CompactionSample>()
          .toList();
      return CompactionHistory(
        parsed.length <= capacity
            ? parsed
            : parsed.sublist(parsed.length - capacity),
      );
    } catch (_) {
      return empty;
    }
  }
}

/// Formatea tokens de forma compacta: `842`, `12.4k`, `180k`, `1.2M`.
String formatCompactTokens(int tokens) {
  if (tokens < 1000) return '$tokens';
  String trim(double v) {
    final text = v.toStringAsFixed(v >= 100 ? 0 : 1);
    return text.endsWith('.0') ? text.substring(0, text.length - 2) : text;
  }

  if (tokens < 1000000) return '${trim(tokens / 1000)}k';
  return '${trim(tokens / 1000000)}M';
}
