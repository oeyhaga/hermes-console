import 'package:flutter/material.dart';

import '../models/compaction_progress.dart';
import '../theme/app_theme.dart';

/// Barra de progreso honesta de una compactación.
///
///  * con estimación aprendida: llena hasta `elapsed / típico` (máx. 95 %);
///  * sin historial: barra indeterminada (o un raíl vacío con movimiento
///    reducido), porque Hermes no publica ningún porcentaje;
///  * terminada: llena y en color de éxito.
class CompactionBar extends StatelessWidget {
  const CompactionBar({
    required this.compaction,
    required this.now,
    this.minHeight = 4,
    this.rounded = false,
    super.key,
  });

  final CompactionProgress compaction;
  final DateTime now;
  final double minHeight;
  final bool rounded;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).hermes;
    final reduceMotion = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    final double? value;
    if (compaction.isFinished) {
      value = 1;
    } else {
      final fraction = compaction.fraction(now);
      value = fraction ?? (reduceMotion ? 0 : null);
    }
    final bar = LinearProgressIndicator(
      key: const ValueKey('compaction-bar'),
      value: value,
      minHeight: minHeight,
      backgroundColor: colors.divider,
      color: compaction.isFinished ? colors.success : colors.accent,
    );
    return rounded
        ? ClipRRect(borderRadius: BorderRadius.circular(minHeight), child: bar)
        : bar;
  }
}
