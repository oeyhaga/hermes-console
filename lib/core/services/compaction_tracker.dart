import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/compaction_progress.dart';

/// Persistencia del historial de duraciones de compactación.
///
/// Una sola clave corta por conexión+modelo (`hc.compact.v1.<conexión>.<modelo>`)
/// con las últimas [CompactionHistory.capacity] mediciones. Es un dato local y
/// descartable: si el almacenamiento falla, la barra sigue funcionando sin
/// estimación.
class CompactionHistoryStore {
  const CompactionHistoryStore();

  static String keyFor(String connectionId, String model) =>
      'hc.compact.v1.$connectionId.${model.isEmpty ? '-' : model}';

  Future<CompactionHistory> load(String key) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return CompactionHistory.decode(prefs.getString(key));
    } catch (_) {
      return CompactionHistory.empty;
    }
  }

  Future<CompactionHistory> record(String key, CompactionSample sample) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final next = CompactionHistory.decode(prefs.getString(key)).add(sample);
      await prefs.setString(key, next.encode());
      return next;
    } catch (_) {
      return CompactionHistory.empty.add(sample);
    }
  }
}

/// Sigue la compactación (automática o manual) de la sesión abierta.
///
/// El chat le pasa cada cambio de estado con [sync]; el tracker mide el tiempo,
/// aprende la duración típica y conserva el resultado unos segundos tras el
/// fin ([linger]) para que la pastilla pueda mostrar «Compactado: A → B».
class CompactionTracker extends ChangeNotifier {
  CompactionTracker({
    this.store = const CompactionHistoryStore(),
    DateTime Function()? clock,
    this.linger = const Duration(seconds: 6),
    this.settleWait = const Duration(seconds: 3),
  }) : _clock = clock ?? DateTime.now;

  final CompactionHistoryStore store;
  final DateTime Function() _clock;

  /// Cuánto se enseña el resultado tras terminar.
  final Duration linger;

  /// Cuánto se espera al resultado de un `/compress` cuya bandera ya se apagó.
  final Duration settleWait;

  CompactionProgress? _current;
  CompactionHistory _history = CompactionHistory.empty;
  String _historyKey = '';
  int _loadGeneration = 0;
  Timer? _lingerTimer;
  Timer? _settleTimer;
  bool _awaitingResult = false;
  bool _disposed = false;

  /// Compactación en curso o recién terminada (dentro del [linger]).
  CompactionProgress? get current => _current;

  /// Compactación todavía en marcha (no terminada).
  bool get running => _current != null && !_current!.isFinished;

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  /// Refleja el estado del chat. Idempotente: llamarlo en cada evento es barato.
  void sync({
    required bool active,
    required bool manual,
    required String historyKey,
    DateTime? startedAt,
    int? tokensBefore,
    int? messagesBefore,
    String? note,
  }) {
    if (_disposed) return;
    final now = _clock();
    final current = _current;
    if (active) {
      _settleTimer?.cancel();
      _settleTimer = null;
      _awaitingResult = false;
      if (current == null || current.isFinished) {
        _lingerTimer?.cancel();
        _lingerTimer = null;
        _current = CompactionProgress(
          startedAt: startedAt ?? now,
          manual: manual,
          tokensBefore: tokensBefore,
          messagesBefore: messagesBefore,
          estimate: _historyKey == historyKey
              ? _history.estimate(tokensBefore: tokensBefore)
              : null,
          note: note,
        );
        _ensureHistory(historyKey);
        _notify();
        return;
      }
      final knowsMore =
          (tokensBefore != null && tokensBefore != current.tokensBefore) ||
          (messagesBefore != null &&
              messagesBefore != current.messagesBefore) ||
          (manual && !current.manual);
      if (knowsMore) {
        final tokens = tokensBefore ?? current.tokensBefore;
        _current = CompactionProgress(
          startedAt: current.startedAt,
          manual: manual || current.manual,
          tokensBefore: tokens,
          messagesBefore: messagesBefore ?? current.messagesBefore,
          estimate: _history.estimate(tokensBefore: tokens) ?? current.estimate,
          note: note ?? current.note,
        );
        _notify();
      }
      return;
    }
    if (current == null || current.isFinished) return;
    if (current.manual) {
      // El resultado del RPC llega justo después de que la bandera se apague:
      // se le concede un margen antes de descartar la barra en silencio (abort,
      // lock_held, transporte incierto: el chat ya avisa por su cuenta).
      if (_awaitingResult) return;
      _awaitingResult = true;
      _settleTimer?.cancel();
      _settleTimer = Timer(settleWait, () {
        _settleTimer = null;
        _awaitingResult = false;
        if (running) _clear();
      });
      return;
    }
    _finish(now);
  }

  /// Resultado numérico exacto de un `session.compress` (o del histórico).
  void reportResult({
    int? tokensBefore,
    int? tokensAfter,
    int? messagesBefore,
    int? messagesAfter,
  }) {
    if (_disposed) return;
    final current = _current;
    if (current == null || current.isFinished) return;
    _settleTimer?.cancel();
    _settleTimer = null;
    _awaitingResult = false;
    _finish(
      _clock(),
      tokensBefore: tokensBefore,
      tokensAfter: tokensAfter,
      messagesBefore: messagesBefore,
      messagesAfter: messagesAfter,
    );
  }

  /// Uso de contexto observado tras terminar: completa el «después» de una
  /// compactación automática, que no trae cifras propias.
  void observeContextTokens(int? used) {
    final current = _current;
    if (_disposed ||
        used == null ||
        current == null ||
        !current.isFinished ||
        current.tokensAfter != null) {
      return;
    }
    final before = current.tokensBefore;
    if (before == null || used <= 0 || used >= before) return;
    _current = current.copyWith(tokensAfter: used);
    _notify();
  }

  void _finish(
    DateTime now, {
    int? tokensBefore,
    int? tokensAfter,
    int? messagesBefore,
    int? messagesAfter,
  }) {
    final current = _current;
    if (current == null) return;
    final finished = current.copyWith(
      finishedAt: now,
      tokensBefore: tokensBefore,
      tokensAfter: tokensAfter,
      messagesBefore: messagesBefore,
      messagesAfter: messagesAfter,
    );
    _current = finished;
    final duration = finished.duration;
    if (duration != null && duration > Duration.zero) {
      final key = _historyKey;
      final sample = CompactionSample(
        durationMs: duration.inMilliseconds,
        tokensBefore: finished.tokensBefore,
      );
      if (key.isNotEmpty) {
        unawaited(
          store.record(key, sample).then((next) {
            if (!_disposed && _historyKey == key) _history = next;
          }),
        );
      }
    }
    _lingerTimer?.cancel();
    _lingerTimer = Timer(linger, () {
      _lingerTimer = null;
      _clear();
    });
    _notify();
  }

  void _ensureHistory(String key) {
    if (key.isEmpty) return;
    if (_historyKey == key && !_history.isEmpty) return;
    _historyKey = key;
    final generation = ++_loadGeneration;
    unawaited(
      store.load(key).then((loaded) {
        if (_disposed || generation != _loadGeneration) return;
        _history = loaded;
        final current = _current;
        if (current != null && !current.isFinished) {
          final estimate = loaded.estimate(tokensBefore: current.tokensBefore);
          if (estimate != null && estimate != current.estimate) {
            _current = current.copyWith(estimate: estimate);
            _notify();
          }
        }
      }),
    );
  }

  void _clear() {
    _lingerTimer?.cancel();
    _lingerTimer = null;
    _settleTimer?.cancel();
    _settleTimer = null;
    _awaitingResult = false;
    if (_current == null) return;
    _current = null;
    _notify();
  }

  /// Descarta cualquier estado (cambio de sesión, cierre de pantalla).
  void reset() => _clear();

  @override
  void dispose() {
    _disposed = true;
    _lingerTimer?.cancel();
    _settleTimer?.cancel();
    super.dispose();
  }
}
