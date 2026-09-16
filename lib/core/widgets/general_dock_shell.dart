import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../screens/chat_screen.dart';
import '../screens/mission_control_screen.dart';
import '../screens/settings_screen.dart';
import '../services/connection_manager.dart';
import 'dock_shortcuts.dart';
import 'general_mode_dock.dart';

/// Envuelve el `body` de una pantalla de navegación del perfil "General"
/// (fuera de una conversación abierta) con el mismo dock flotante que ya usa
/// `HomeDashboardScreen`: mismo patrón Stack + Positioned + callbacks
/// (onCreate/onOpenBots/onOpenSettings/...), gestionando por su cuenta el
/// "Atrás" contextual (RouteAware) para no duplicar esa lógica ni la lista
/// de callbacks en cada pantalla que se sume (Ajustes, lista de sesiones).
///
/// Deliberadamente NO se usa dentro de una conversación (`ChatScreen`): ahí
/// ya viven el composer y el pill flotante de subagentes; superponer el
/// dock los taparía/competiría con ellos.
class GeneralDockShell extends StatefulWidget {
  final Widget body;
  final SavedConnection connection;
  final ConnectionManager connManager;

  /// Acción de "Crear". Si es null, crea una conversación nueva genérica
  /// (mismo comportamiento que Inicio); algunas pantallas (p.ej. la lista de
  /// sesiones) ya tienen su propia creación con refresco de estado y la
  /// pasan aquí en vez de usar el fallback.
  final VoidCallback? onCreate;

  /// Variante contextual de [onCreate]: cuando no es null, tiene prioridad
  /// sobre `onCreate`/el fallback genérico. Recibe la `GlobalKey` ya anclada
  /// al tile "+" del dock (ver [GeneralModeDock.createAnchorKey]) para que
  /// quien la use pueda abrir un popover anclado a ese botón (p.ej. crear un
  /// cron job o una tarea directamente ahí) en vez de navegar.
  final void Function(GlobalKey anchorKey)? onCreateAnchored;

  /// False cuando esta pantalla YA ES Ajustes: evita apilar Ajustes sobre
  /// Ajustes al tocar el item "Ajustes" del dock.
  final bool includeSettingsAction;

  /// False cuando esta pantalla YA ES la lista de sesiones (solo aplica si
  /// el usuario activó el acceso opcional "Sesiones" del catálogo).
  final bool includeSessionsAction;

  const GeneralDockShell({
    required this.body,
    required this.connection,
    required this.connManager,
    this.onCreate,
    this.onCreateAnchored,
    this.includeSettingsAction = true,
    this.includeSessionsAction = true,
    super.key,
  });

  @override
  State<GeneralDockShell> createState() => _GeneralDockShellState();
}

class _GeneralDockShellState extends State<GeneralDockShell> {
  // "Atrás" debe aparecer en cuanto ESTA pantalla es en sí misma una
  // subpantalla (se llegó a ella con un push, p.ej. desde Inicio), no
  // cuando algo se apila POR ENCIMA de ella: lo segundo, que es lo que
  // rastreaba la versión anterior vía RouteAware (`didPushNext`/
  // `didPopNext`), solo se vuelve true justo cuando esta pantalla queda
  // tapada por la nueva ruta — momento en el que su propio dock (con el
  // "Atrás" ya activado) es invisible para el usuario. Por eso "Atrás"
  // nunca llegaba a verse en la práctica (bug confirmado en dispositivo
  // real): la señal se calculaba sobre la pantalla equivocada del par
  // padre/hijo. `Route.isFirst` sobre la ruta de ESTA pantalla es la señal
  // correcta y no necesita observar el Navigator en absoluto.
  bool get _isSubscreen => ModalRoute.of(context)?.isFirst != true;

  // Solo se instancia cuando `onCreateAnchored` está presente: el resto de
  // pantallas (Ajustes, Sesiones) no necesitan que el "+" cargue una key.
  final GlobalKey _createAnchorKey = GlobalKey(
    debugLabel: 'general-dock-create-anchor',
  );

  void _handleCreate() {
    final anchored = widget.onCreateAnchored;
    if (anchored != null) {
      anchored(_createAnchorKey);
      return;
    }
    (widget.onCreate ?? _defaultCreate)();
  }

  void _defaultCreate() {
    final session = Session(
      id: GatewayChatClient.generateSessionId(),
      title: Strings.of(context).drawerNewChat,
      model: 'hermes-agent',
      source: 'mobile',
      messageCount: 0,
      isActive: true,
      preview: '',
      startedAt: DateTime.now().millisecondsSinceEpoch.toDouble() / 1000,
    );
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) =>
            ChatScreen(connection: widget.connection, session: session),
      ),
    );
  }

  void _openBots() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => MissionControlScreen(
          connection: widget.connection,
          connManager: widget.connManager,
        ),
      ),
    );
  }

  void _openSettings() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => SettingsScreen(
          connection: widget.connection,
          connManager: widget.connManager,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        widget.body,
        GeneralModeDock(
          onCreate: _handleCreate,
          createAnchorKey: widget.onCreateAnchored != null
              ? _createAnchorKey
              : null,
          onOpenBots: _openBots,
          onOpenSettings: widget.includeSettingsAction ? _openSettings : null,
          onOpenHome: () => Navigator.of(context).popUntil((r) => r.isFirst),
          onOpenCron: () =>
              openDockCron(context, widget.connection, widget.connManager),
          onOpenTasks: () =>
              openDockTasks(context, widget.connection, widget.connManager),
          onOpenSessions: widget.includeSessionsAction
              ? () => openDockSessions(
                  context,
                  widget.connection,
                  widget.connManager,
                )
              : null,
          onOpenTools: () =>
              openDockTools(context, widget.connection, widget.connManager),
          showBackContext: _isSubscreen,
          onBack: () => Navigator.of(context).maybePop(),
        ),
      ],
    );
  }
}
