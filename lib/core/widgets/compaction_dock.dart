import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../models/compaction_progress.dart';
import '../theme/app_theme.dart';
import 'activity_pill.dart' show ActivityTicker, formatTurnElapsed;

/// Duración de una compactación en segundos enteros («71 s»), con un decimal por
/// debajo de 10 s y `m:ss` pasados 3 minutos.
String formatCompactionDuration(Duration value, {String languageCode = 'en'}) {
  final ms = value.inMilliseconds;
  if (ms < 10000) {
    final text = (ms / 1000).toStringAsFixed(1);
    return '${languageCode == 'es' ? text.replaceAll('.', ',') : text} s';
  }
  if (ms < 180000) return '${value.inSeconds} s';
  return formatTurnElapsed(value);
}

/// Texto de los hechos conocidos mientras compacta («22 mensajes · ~21.5k
/// tokens · parte 2 de 4»). Solo lo que el backend ha dicho.
List<String> compactionFacts(Strings strings, CompactionProgress compaction) =>
    [
      if (compaction.messagesBefore != null)
        strings.liveCompactionMessages(compaction.messagesBefore!),
      if (compaction.tokensBefore != null)
        strings.liveCompactionTokensApprox(
          formatCompactTokens(compaction.tokensBefore!),
        ),
      if (compaction.chunkIndex != null && compaction.chunkCount != null)
        strings.liveCompactionChunks(
          compaction.chunkIndex!,
          compaction.chunkCount!,
        ),
    ];

/// Resultado real: «Compactado · 22 → 12 mensajes · 96k → 4.8k tokens · 71 s».
/// Los recuentos que el backend no dio no se muestran.
String compactionResultText(
  Strings strings,
  CompactionProgress compaction,
  String languageCode,
) => [
  strings.liveCompactionDone,
  if (compaction.messagesBefore != null && compaction.messagesAfter != null)
    strings.liveCompactionMessagesChange(
      compaction.messagesBefore!,
      compaction.messagesAfter!,
    ),
  if (compaction.tokensBefore != null && compaction.tokensAfter != null)
    strings.liveCompactionTokensChange(
      formatCompactTokens(compaction.tokensBefore!),
      formatCompactTokens(compaction.tokensAfter!),
    ),
  if (compaction.duration != null)
    formatCompactionDuration(compaction.duration!, languageCode: languageCode),
].join(' · ');

/// Barra fina pegada sobre el compositor mientras se compacta.
///
///  * sin progreso publicado: un segmento que se mueve (honesto: «está
///    trabajando», nunca un relleno que finja porcentaje);
///  * con `chunk_index/chunk_count` reales: relleno determinado;
///  * terminada: línea llena y el resultado exacto unos segundos.
///
/// El tiempo es el medido en el dispositivo; no hay tiempo restante estimado.
class CompactionDock extends StatelessWidget {
  const CompactionDock({
    required this.compaction,
    this.note,
    this.clock,
    super.key,
  });

  final CompactionProgress compaction;

  /// Estado que exige atención (resultado pendiente de confirmar…).
  final String? note;
  final DateTime Function()? clock;

  @override
  Widget build(BuildContext context) {
    final strings = Strings.of(context);
    final lang = Localizations.localeOf(context).languageCode;
    final label = compaction.isFinished
        ? compactionResultText(strings, compaction, lang)
        : strings.liveCompacting;
    return ActivityTicker(
      active: !compaction.isFinished,
      clock: clock,
      builder: (context, now) => _DockBody(
        compaction: compaction,
        now: now,
        label: label,
        note: compaction.isFinished ? null : note,
        facts: compaction.isFinished
            ? const []
            : compactionFacts(strings, compaction),
      ),
    );
  }
}

class _DockBody extends StatelessWidget {
  const _DockBody({
    required this.compaction,
    required this.now,
    required this.label,
    required this.facts,
    this.note,
  });

  final CompactionProgress compaction;
  final DateTime now;
  final String label;
  final List<String> facts;
  final String? note;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).hermes;
    final finished = compaction.isFinished;
    return Semantics(
      key: ValueKey(
        finished ? 'compaction-result' : 'desktop-session-compression-progress',
      ),
      liveRegion: true,
      container: true,
      label: [label, ...facts, ?note].join(', '),
      excludeSemantics: true,
      child: Padding(
        key: const ValueKey('compaction-dock'),
        padding: const EdgeInsets.fromLTRB(12, 6, 12, 2),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            CompactionLine(
              key: const ValueKey('compaction-line'),
              fraction: compaction.fraction,
              finished: finished,
            ),
            const SizedBox(height: 6),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(
                          text: label,
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            color: finished
                                ? colors.textSecondary
                                : colors.textPrimary,
                          ),
                        ),
                        if (facts.isNotEmpty)
                          TextSpan(
                            text: ' · ${facts.join(' · ')}',
                            style: TextStyle(color: colors.textSecondary),
                          ),
                      ],
                    ),
                    style: const TextStyle(fontSize: 12.5, height: 1.3),
                  ),
                ),
                if (!finished) ...[
                  const SizedBox(width: 10),
                  Text(
                    formatTurnElapsed(compaction.elapsed(now)),
                    key: const ValueKey('compaction-elapsed'),
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: colors.textSecondary,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ],
              ],
            ),
            if (note != null)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(
                  note!,
                  style: TextStyle(fontSize: 12, color: colors.textSecondary),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// La línea: indeterminada (segmento que se mueve), determinada (relleno real)
/// o llena (terminada). Con movimiento reducido, un raíl quieto.
class CompactionLine extends StatefulWidget {
  const CompactionLine({
    required this.fraction,
    required this.finished,
    super.key,
  });

  /// Solo un progreso publicado por el backend (ver [parseCompactionChunks]).
  final double? fraction;
  final bool finished;

  @override
  State<CompactionLine> createState() => _CompactionLineState();
}

class _CompactionLineState extends State<CompactionLine>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1500),
  );

  bool get _moving => widget.fraction == null && !widget.finished;

  void _sync() {
    final reduce = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (_moving && !reduce) {
      if (!_controller.isAnimating) _controller.repeat();
    } else {
      _controller.stop();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  @override
  void didUpdateWidget(CompactionLine oldWidget) {
    super.didUpdateWidget(oldWidget);
    _sync();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).hermes;
    final reduce = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    final fraction = widget.finished ? 1.0 : widget.fraction;
    return ClipRRect(
      borderRadius: BorderRadius.circular(2),
      child: SizedBox(
        height: 3,
        child: fraction != null
            ? LinearProgressIndicator(
                key: const ValueKey('compaction-line-fill'),
                value: fraction,
                minHeight: 3,
                backgroundColor: colors.divider,
                color: widget.finished ? colors.success : colors.accent,
              )
            : AnimatedBuilder(
                animation: _controller,
                builder: (context, _) => CustomPaint(
                  key: const ValueKey('compaction-line-moving'),
                  painter: _SegmentPainter(
                    track: colors.divider,
                    segment: colors.accent,
                    t: reduce ? null : _controller.value,
                  ),
                  size: const Size.fromHeight(3),
                ),
              ),
      ),
    );
  }
}

class _SegmentPainter extends CustomPainter {
  _SegmentPainter({required this.track, required this.segment, this.t});

  final Color track;
  final Color segment;

  /// `0..1` a lo largo del recorrido; `null` (movimiento reducido): solo raíl.
  final double? t;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = track);
    final position = t;
    if (position == null) return;
    final width = size.width * 0.3;
    final eased = Curves.easeInOut.transform(position);
    final left = -width + (size.width + width) * eased;
    canvas.drawRect(
      Rect.fromLTWH(left, 0, width, size.height).intersect(Offset.zero & size),
      Paint()..color = segment,
    );
  }

  @override
  bool shouldRepaint(_SegmentPainter old) =>
      old.t != t || old.track != track || old.segment != segment;
}
